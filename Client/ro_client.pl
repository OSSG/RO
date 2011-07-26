#!/usr/bin/perl -w
# RO (Repository Observer) - Client script
# Copyright (C) 2007-2011 Fedor A. Fetisov <faf@ossg.ru>. All Rights Reserved
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use Getopt::Long qw(:config no_ignore_case bundling no_auto_abbrev);
use LWP::UserAgent;
use Data::Dumper;
use Encode qw(from_to);

use constant PACKAGES_LIMIT => 500; # максимальное количество пакетов, пересылаемое в одном XML-документе
				    # внимание - при запросе обновления отсылается два XML-документа

my $VERSION = '0.9.17svn'; # версия клиента

my $date = localtime(time); # для записи в кеш - на всякий случай

my $system_cmd = 'rpm -qa --queryformat "%{NAME}/%{VERSION}/%{RELEASE}/%{SERIAL}\n"';
my $repository_cmd = 'find <path> -name \'*.rpm\' -print0 | xargs -r0 rpm -q --queryformat="%{NAME}\t%{VERSION}\t%{RELEASE}\t%{SERIAL}\n%{SUMMARY}\n%%%%\n%{CHANGELOGTEXT}\n%%%%\n" -p';

my $options = {};

GetOptions(
    $options, 'help|?|h', 'version|v', 'debug', 'config=s'
) or die "For usage information try: \t$0 --help\n";

if ($options->{'help'}) {
    print <<HELP
RO (Repository Observer) client script
Usage: $0 [options]
Options available:
    --help | -?	| -h	Prints this help
    --version | -v	Displays version
    --debug		Turns debug mode on
    --config=<file>	Specifies configuration file. If config option is omited
			script will use default configuration (./config)
HELP
;

    exit;
}
elsif ($options->{'version'}) {
    print <<VERSION
RO (Repository Observer) client script
Version $VERSION
VERSION
;
    exit;
}

# выставление флага вывода отладочной информации
my $debug_mode = $options->{'debug'} || 0;

print STDERR "[DEBUG] Try to read configuration.\n" if $debug_mode;

# чтение конфигурации
my $config_file = $options->{'config'} || './config';

die "Can't find configuration file $config_file\n" unless -f $config_file;

print STDERR "[DEBUG] Configuration obtained. Parsing.\n" if $debug_mode;

my $config = do($config_file);
if ($@) {
    print STDERR "[ERROR] Bad configuration syntax!\n";
    print STDERR $@;
    exit;
}

# определние режима работы скрипта: система или репозиторий
unless (defined $config->{'type'}) {
    print STDERR "[ERROR] You must specify work type in configuration.\n";
    exit;
}

my $rep_flag = 0;
my $pseudo_mode = 0;
if (($config->{'type'} eq 'system') || ($config->{'type'} eq 'sys')) {
    print STDERR "[DEBUG] Entered work mode 'system'.\n" if $debug_mode;
}
elsif (($config->{'type'} eq 'repository') || ($config->{'type'} eq 'rep')) {
    print STDERR "[DEBUG] Entered work mode 'repository'.\n" if $debug_mode;
    $rep_flag = 1;
}
elsif ($config->{'type'} eq 'pseudo') {
    print STDERR "[DEBUG] Entered work mode 'pseudo'.\n" if $debug_mode;
    $pseudo_mode = 1;
}
else {
    print STDERR "[ERROR] Unknown type: '$config->{'type'}'. Available options: sys[tem] | rep[ository] | pseudo\n";
    exit;
}

# получение списка игнорируемых пакетов
my @ignoring_packages;
my $ignore_counter;
my $ignore_list_regexp_flag;
if (defined $config->{'ignore_list'}) {
    if (defined $config->{'ignore_list'}->{'packages'}) {
	$ignore_list_regexp_flag = $config->{'ignore_list'}->{'use_regexp'} || 0;
	print STDERR "[DEBUG] Found ignore list. Fetching.\n" if $debug_mode;
	$ignore_counter = 0;
	unless (ref($config->{'ignore_list'}->{'packages'})) {
	    if (!$ignore_list_regexp_flag || check_regexp($config->{'ignore_list'}->{'packages'})) {
		push (@ignoring_packages, $config->{'ignore_list'});
	    }
	    else {
		print STDERR "[ERROR] Bad package name wildcard in ignore list: $_\n";
	        exit;
	    }
	}
	elsif (ref($config->{'ignore_list'}->{'packages'}) eq 'ARRAY') {
	    foreach (@{$config->{'ignore_list'}->{'packages'}}) {
		if (!$ignore_list_regexp_flag || check_regexp($_)) {
		    push (@ignoring_packages, $_);
		}
		else {
		    print STDERR "[ERROR] Bad package name wildcard in ignore list: $_\n";
		    exit;
		}
	    }
	}
	else {
	    print STDERR "[ERROR] Invalid ignore list format!\n";
	    exit;
	}
    }
}

# получение текущего списка пакетов в виде хеша
# ключи - объединённые нулевым символом \0 имя, версия, релиз и сериал пакета
# значения - хеши с остальными параметрами (критичность, описание)
my $packages = {};
my %added_packages;
my %removed_packages;

if ($rep_flag) {

    print STDERR "[DEBUG] Checking packages sources.\n" if $debug_mode;
    unless (defined $config->{'source'}) {
        print STDERR "[ERROR] Packages sources not specified!\n";
        exit;
    }

    my @paths;
    unless (ref($config->{'source'})) { push (@paths, $config->{'source'}); }
    elsif (ref($config->{'source'}) eq 'ARRAY') { @paths = @{$config->{'source'}}; }
    else {
	print STDERR "[ERROR] Invalid packages source format!\n";
	exit;
    }

    print STDERR "[DEBUG] Preparing available packages list.\n" if $debug_mode;
    foreach my $path (@paths) {
	print STDERR "[DEBUG] Try to enter '$path'.\n" if $debug_mode;
	unless ($path && chdir($path)) {
	    print STDERR "Can't enter source directory '$path': $!\n";
	    exit;
	}
	print STDERR "[DEBUG] Try to get packages list from '$path'.\n" if $debug_mode;
	my $element = {'summary' => '', 'changelog' => ''};
	my $summary_flag = 0;
	my $changelog_flag = 0;
    	my $cmd = $repository_cmd;
	$cmd =~ s/\<path\>/$path/;
	open(IN, "$cmd |") or die "Can't get packages list from '$path': $!\n";
	while (<IN>) {
	    chomp;
	    if ($summary_flag) {
	        if (/^%%$/) {
		    $summary_flag = 0;
		    $changelog_flag = 1;
		}
		else {
		    $element->{'summary'} .= $_ . "/n";
		}
	    }
	    elsif ($changelog_flag) {
		if (/^%%$/) {
		    $changelog_flag = 0;
# пакет учитывается, когда его нет в перечне игнорируемых
		    unless (ignore_package(\@ignoring_packages, $element->{'name'}, $ignore_list_regexp_flag)) {
			$packages->{join("\0", $element->{'name'}, $element->{'version'}, $element->{'release'}, $element->{'serial'})} = 
			    { 'summary' => $element->{'summary'}, 'importance' => determine_importance($element->{'changelog'}) };
		    }
		    else {
			$ignore_counter++;
		    }
		    $element = {'summary' => '', 'changelog' => ''};
		}
		else {
		    $element->{'changelog'} .= $_ . "/n";
		}
	    }
	    else {
		my @temp = split(/\t/);
		$element->{'name'} = $temp[0];
		$element->{'version'} = $temp[1];
		$element->{'release'} = $temp[2];
		$element->{'serial'} = $temp[3];
		$summary_flag = 1;
	    }
	}
	close(IN);
    }
    print STDERR "[DEBUG] Available packages (" . scalar(values(%{$packages})) . ") list prepared.\n" if $debug_mode;
}
elsif (!$pseudo_mode) {
    print STDERR "[DEBUG] Preparing installed packages list.\n" if $debug_mode;
    open(IN, "$system_cmd |") or die "Can't get packages list: $!\n";
    while (<IN>) {
        chomp;
	my @temp = split("/", $_);
# пакет учитывается, когда его нет в перечне игнорируемых
	unless (ignore_package(\@ignoring_packages, $temp[0], $ignore_list_regexp_flag)) {
    	    $packages->{join("\0", @temp)} = {};
	}
	else {
	    $ignore_counter++;
	}
    }
    close(IN);
    print STDERR "[DEBUG] Installed packages (" . scalar(values(%{$packages})) . ") list prepared.\n" if $debug_mode;
}

print STDERR "[DEBUG] Ignoring $ignore_counter package(s).\n" if (defined $ignore_counter && $debug_mode);

my $cache;
my $refresh_mode = 0;

unless ($pseudo_mode) {
    if (-f $config->{'cache'}) {
# попытка чтения кеша
	print STDERR "[DEBUG] Try to read cache.\n" if $debug_mode;
	open(IN, '<' . $config->{'cache'}) || die "Can't open existing cache file $config->{'cache'} for read: $!\n";
	my @temp = <IN>;
	close IN;
# анализ произошедшего - если получилось, вызов в режиме обновления, если нет - в режиме инициализации
	print STDERR "[DEBUG] Cache obtained. Parsing.\n" if $debug_mode;
	$cache = eval(join("\n", @temp));

	$refresh_mode = !$@ && (defined $cache->{$config->{'signature'}});
# если версия клиента не совпадает с версией кеша - режим инициализации
	$refresh_mode &&= (defined $cache->{$config->{'signature'}}->{'version'} && ($VERSION eq $cache->{$config->{'signature'}}->{'version'}));
	print STDERR "[DEBUG] Refresh flag set " . ($refresh_mode ? 'on' : 'off') . ".\n" if $debug_mode;
    }
    elsif ($debug_mode) {
	print STDERR "[DEBUG] Cache not found.\n";
    }
}

# формирование данных для отсылки
my $params = [];
if ($refresh_mode) {
# структура кеша:
#{
#    'repository' => { 'last_time' => '<дата>', 'packages' => { <хеш пакетов> } },
#    'system' => { 'last_time' => '<дата>', 'packages' => { <хеш пакетов> } }
#}

# сравнение текущего списка пакетов с кешем и выявление разницы

    print STDERR "[DEBUG] Comparing cache (" . scalar(values(%{$cache->{$config->{'signature'}}->{'packages'}})) . ") and current packages (" . scalar(values(%{$packages})) . ") list to determine added and removed packages.\n" if $debug_mode;

    %removed_packages = %{$cache->{$config->{'signature'}}->{'packages'}};
    %added_packages = %{$packages};

    foreach (keys %{$cache->{$config->{'signature'}}->{'packages'}}) {
        if (exists $packages->{$_}) {
    	    delete $added_packages{$_};
	    delete $removed_packages{$_};
	}
    }

    print STDERR "[DEBUG] Added (" . scalar(values(%added_packages)) . ") and removed (" . scalar(values(%removed_packages)) . ") packages determined.\n" if $debug_mode;

    print STDERR "[DEBUG] Determining amount of data portions.\n" if $debug_mode;
    my $added_packages_list = split_packages_hash(\%added_packages);
    my $removed_packages_list = split_packages_hash(\%removed_packages);

    print STDERR "[DEBUG] There should be " . ((scalar(@$added_packages_list) + scalar(@$removed_packages_list)) || 1) . " data portions.\n" if $debug_mode;

    print STDERR "[DEBUG] Preparing xml data to send.\n" if $debug_mode;

    my $end = (scalar(@$added_packages_list) <=> scalar(@$removed_packages_list)) > 0 ?
		    scalar(@$added_packages_list) : scalar(@$removed_packages_list);

    for(my $i=0; $i<$end; $i++) {
        $params->[$i]->{'added_packages'} = make_xml(($i < scalar(@$added_packages_list)) ? $added_packages_list->[$i] : {});
	$params->[$i]->{'removed_packages'} = make_xml(($i < scalar(@$removed_packages_list)) ? $removed_packages_list->[$i] : {});
	$params->[$i]->{'action'} = 'refresh';
	$params->[$i]->{'node'} = $config->{'signature'};
    }
    print STDERR "[DEBUG] All data prepared.\n" if $debug_mode;
}
elsif (!$pseudo_mode) {
    print STDERR "[DEBUG] Determining amount of data portions.\n" if $debug_mode;
    my $packages_list = split_packages_hash($packages);

    print STDERR "[DEBUG] There should be " . ((scalar(@$packages_list)) || 1) . " data portions.\n" if $debug_mode;

    print STDERR "[DEBUG] Preparing xml data to send.\n" if $debug_mode;

    for(my $i=0; $i<scalar(@$packages_list); $i++) {
	$params->[$i]->{'node'} = $config->{'signature'};
	if ($i) {
	    $params->[$i]->{'added_packages'} = make_xml($packages_list->[$i]);
	    $params->[$i]->{'removed_packages'} = make_xml({});
	    $params->[$i]->{'action'} = 'refresh';
	}
	else {
	    $params->[$i]->{'packages'} = make_xml($packages_list->[$i]);
	    $params->[$i]->{'action'} = 'init';
	}
    }

    print STDERR "[DEBUG] All data prepared.\n" if $debug_mode;
}
# Режим псевдо-узла - данные для отсылки на сервер системы берутся непосредственно из указанного файла (файлов)
else {
    print STDERR "[DEBUG] Checking packages sources.\n" if $debug_mode;

    my @files;
    unless (ref($config->{'source'})) { push (@files, $config->{'source'}); }
    elsif (ref($config->{'source'}) eq 'ARRAY') { @files = @{$config->{'source'}}; }
    else {
	print STDERR "[ERROR] Invalid packages source format!\n";
	exit;
    }

    my $i = 0;
    my $data;
    foreach (@files) {
	print STDERR "[DEBUG] Try to read packages data from file '$_'.\n" if $debug_mode;
	unless (-f $_) {
	    print STDERR "[ERROR] Can't use not existed file '$_' as packages source!\n";
	    exit;
	}
	if (open(IN, "<$_")) {
	    $data = join("\n", <IN>);
	    close IN;
	    print STDERR "[DEBUG] Data obtained.\n" if $debug_mode;
	}
	else {
	    print STDERR "[ERROR] Can't open packages source file '$_': $!\n";
	    exit;
	}
    	if ($i) {
	    $params->[$i]->{'added_packages'} = $data;
	    $params->[$i]->{'removed_packages'} = make_xml({});
	    $params->[$i]->{'action'} = 'refresh';
	}
	else {
	    $params->[$i]->{'packages'} = $data;
	    $params->[$i]->{'action'} = 'init';
	}
	$params->[$i]->{'node'} = $config->{'signature'};
	$i++;
    }

    print STDERR "[DEBUG] All data prepared.\n" if $debug_mode;
}

# подготовка к логированию
my $log_mode = 0;
if ((defined $config->{'log'}) && (ref($config->{'log'}) eq 'HASH') && $config->{'log'}->{'use_log'}) {
    print STDERR "[DEBUG] Checking log file.\n" if $debug_mode;
    print STDERR "[ERROR] Log file not specified!\n" unless (defined $config->{'log'}->{'log_file'});
    print STDERR "[DEBUG] Log file doesn't exist. Will try to create it.\n" unless (-f $config->{'log'}->{'log_file'} || !$debug_mode);
    open(LOG, '>>' . $config->{'log'}->{'log_file'}) || die "Can't open log file $config->{'log'}->{'log_file'} for write: $!\n";
    flock(LOG, 2) || die "Can't lock log file $config->{'log'}->{'log_file'} for write: $!\n";
    $log_mode = 1;
    print LOG "[" . localtime(time) . "] [NOTICE] " . ($refresh_mode ? 'Refresh' : 'Init') . " operation starts.\n";
}

# отсылка данных
print STDERR "[DEBUG] Initializing user agent to send data.\n" if $debug_mode;

# инициализация клиента для отсылки данных
my %ua_options;
# при работе через https по умолчанию не проверять сертификат сервера
$ua_options{'ssl_opts'} = {'verify_hostname' => 0 } if (($config->{'server'}->{'proto'} eq 'https') && !($LWP::UserAgent::VERSION =~ /^[0-5]\./));
# задание/переопределение опций клиента, указанных в конфигурации
if ((defined $config->{'lwp_ua_options'}) && (ref($config->{'lwp_ua_options'}) eq 'HASH')) {
    foreach (keys(%{$config->{'lwp_ua_options'}})) {
	$ua_options{$_} = $config->{'lwp_ua_options'}->{$_};
    }
}

my $ua = scalar(keys(%ua_options)) ? LWP::UserAgent->new(%ua_options) : LWP::UserAgent->new();

# если данных для отсылки нет, должны быть отосланы пустые данные,
# чтобы обновить дату синхронизации системы на сервере
unless (scalar(@$params)) {
# в случае если пакетов вообще нет - попытка обновления системы приведёт к ошибке,
# т.к. сервер посчитает систему ещё не инициализированной
# соответственно, в этом случае даже в режиме обновления отсылаются пустые данные с командой 'init'
	if ($refresh_mode && scalar(values(%{$packages}))) {
	    $params->[0]->{'added_packages'} = make_xml({});
	    $params->[0]->{'removed_packages'} = make_xml({});
	    $params->[0]->{'action'} = 'refresh';
	}
	else {
	    $params->[0]->{'packages'} = make_xml({});
	    $params->[0]->{'action'} = 'init';
	}
	$params->[0]->{'node'} = $config->{'signature'};
}

my $error;
my $i = 0;
my $result;
foreach my $current_params (@$params) {
    $i++;
    print STDERR "[DEBUG] Sending $i data portion to server (" . $config->{'server'}->{'proto'} . '://' . $config->{'server'}->{'host'} . ':' . $config->{'server'}->{'port'} . "/).\n" if $debug_mode;
    my $response = $ua->post($config->{'server'}->{'proto'} . '://' . $config->{'server'}->{'host'} . ':' . $config->{'server'}->{'port'} . '/', $current_params);
    print STDERR "[DEBUG] Analizing server response for $i data portion.\n" if $debug_mode;
# анализ ответа сервера
    unless ($response->is_success()) {
	print STDERR "[ERROR] Server error: " . $response->status_line . "\n";
	if ($log_mode) {
	    print LOG "[" . localtime(time) . "] [ERROR] Server error: " . $response->status_line . "\n";
	    close LOG;
	}
	exit;
    }
    $result = $response->content;

    if ($error = ($result =~ /\[ERROR\]/)) {
	print STDERR $result;
    }
    else {
        print STDERR "[DEBUG] Server response looks good:\n\n$result\n" if $debug_mode;
    }

# логирование события
    if ($log_mode) {
	print STDERR "[DEBUG] Writing to log file.\n" if $debug_mode;
	print LOG "[" . localtime(time) . "] " . ($error ? '[ERROR]' : '[NOTICE]') . " Send " . ($refresh_mode || ($i>1) ? 'refresh' : 'init') . " request to server.";
	if ($error) {
	    print LOG " Got error:\t$result\n";
	    last;
	}
	else {
	    print LOG " Success.\n";
	}
    }
}

# закрываем лог, если он был открыт
    if ($log_mode) {
	if ($refresh_mode) {
	    print LOG "[" . localtime(time) . "] " . ($error ? '[ERROR]' : '[NOTICE]') . " During refresh operation server was told that there were " . scalar(values(%added_packages)) . " packages added and " . scalar(values(%removed_packages)) . " removed.\n";
	}
	elsif (!$pseudo_mode) {
    	    print LOG "[" . localtime(time) . "] " . ($error ? '[ERROR]' : '[NOTICE]') . " During init operation server was told that there were " . scalar(values(%{$packages})) . " packages found.\n";
	}
	close LOG;
    }

# если ошибки нет и работа происходит не в режиме псевдо-системы - запись в кеш
unless ($error || $pseudo_mode) {

# подготовка данных для записи в кеш
    print STDERR "[DEBUG] Preparing new cache.\n" if $debug_mode;
    $cache->{$config->{'signature'}} = {'version' => $VERSION, 'date' => $date, 'packages' => $packages};
    local $Data::Dumper::Indent = 0;
    $cache = Dumper($cache);
    $cache =~ s{\$VAR1 = }{};

# запись в кеш
    print STDERR "[DEBUG] Writing new cache.\n" if $debug_mode;
    open(OUT, '>' . $config->{'cache'}) || die "Can't open cache file $config->{'cache'} for write: $!\n";
    flock(OUT, 2) || die "Can't lock cache file $config->{'cache'} for write: $!\n";
    print OUT $cache;
    close OUT;
}




sub make_xml {
    my $packages = shift;

    my $res = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<packages>\n";
    foreach (keys %$packages) {
	my @temp = split(/\0/, $_);
	$res .= "\t<package>\n";
	$res .= "\t\t<name>$temp[0]</name>\n";
	$res .= "\t\t<version>$temp[1]</version>\n";
	$res .= "\t\t<release>$temp[2]</release>\n";
	$res .= "\t\t<serial>$temp[3]</serial>\n";
	if (defined $packages->{$_}->{'importance'}) {
	    $res .= "\t\t<importance>$packages->{$_}->{'importance'}</importance>\n";
	}
	if (defined $packages->{$_}->{'summary'}) {
# Фильтрация попадающихся "битых" юникодных символов в описаниях пакетов
	    from_to($packages->{$_}->{'summary'}, 'utf8', 'utf8');
	    $res .= "\t\t<summary><![CDATA[\n$packages->{$_}->{'summary'}\n\t\t]]></summary>\n";
	}
	$res .= "\t</package>\n";
    }
    $res .= "</packages>\n";

    return $res;
}

sub determine_importance {
    my $changelog = shift;
    return 2 if (($changelog =~ /vulnerab/) || ($changelog =~ /security fix/) || ($changelog =~ /CVE/));
    return 1;
}

sub split_packages_hash {
    my $hash = shift;

    my @result;
    my $counter = 0;
    my $temp;
    foreach (keys(%$hash)) {
	$counter++;
	if ($counter > PACKAGES_LIMIT) {
	    push(@result, $temp);
	    $temp = {};
	    $counter = 1;
	}
	$temp->{$_} = $hash->{$_};
    }
    push (@result, $temp) if (scalar(keys(%$temp)));

    return \@result;
}

sub check_regexp {
    my $regexp = shift;
    return eval { '' =~ /$regexp/; 1 } || 0;
}

sub ignore_package {
    my $wildcards = shift;
    my $package = shift;
    my $use_regexp = shift;

    foreach my $wildcard (@$wildcards) {
	    return 1 if ($use_regexp && ($package =~ /$wildcard/) ||
			 !$use_regexp && ($package eq $wildcard));
    }

    return 0;
}
