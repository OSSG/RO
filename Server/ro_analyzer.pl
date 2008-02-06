#!/usr/bin/perl -w
# RO (Repository Observer) - Analyzer script
# Copyright (C) 2007, 2008 Fedor A. Fetisov <faf@ossg.ru>. All Rights Reserved
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
use DBI;
use Getopt::Long qw(:config no_ignore_case bundling no_auto_abbrev);

my $VERSION = '0.9.13svn'; # версия анализатора

# коды состояний (были заданы при создании БД)
my $states = {
		'package'	=> {	'normal'	=> 1,
					'old'		=> 2,
					'new'		=> 4,
					'orphaned'	=> 3
		},
		'node'		=> {	'normal'	=> 1,
					'trouble'	=> 3,
					'orphaned'	=> 2
		}
};

my $options = {};

GetOptions(
    $options, 'help|?|h', 'version|v', 'debug', 'config=s'
) or die "For usage information try: \t$0 --help\n";

if ($options->{'help'}) {
    print <<HELP
RO (Repository Observer) analyzer script
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
RO (Repository Observer) analyzer script
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

# установка флага ведения лога
my $log_mode = ((defined $config->{'log'}) && (ref($config->{'log'}) eq 'HASH') && $config->{'log'}->{'use_log'}) ? 1 : 0;
print STDERR "[DEBUG] Set log mode " . ($log_mode ? 'on' : 'off') . ".\n" if $debug_mode;

print STDERR "[DEBUG] Connecting to database.\n" if $debug_mode;
# инициализация соединения с базой данных и подготовка необходимых запросов
my $dbh = DBI->connect('dbi:' . $config->{'database'}->{'db_driver'} .
			':dbname=' . $config->{'database'}->{'db_name'} .
			';host=' . $config->{'database'}->{'db_host'},
			$config->{'database'}->{'db_user'},
			$config->{'database'}->{'db_passwd'},
			$config->{'database'}->{'db_options'}) ||
		die "[ERROR]: Cann't connect to events database: $DBI::errstr";


print STDERR "[DEBUG] Preparing all database requests.\n" if $debug_mode;
my $requests = {};
$requests->{'check_packages_count'} = $dbh->prepare('select count(*) as count from packages_vs_nodes where node=?');
$requests->{'check_repositories_count'} = $dbh->prepare('select count(*) as count from nodes_vs_nodes where system=?');
$requests->{'get_nodes'} = $dbh->prepare('select id, name, node_type, state, importance from nodes where to_check=?');
$requests->{'get_node_packages'} = $dbh->prepare('select * from packages_vs_nodes as a, packages as b where b.id=a.package and node=? order by name');
$requests->{'get_repository_packages'} = $dbh->prepare('select * from packages_vs_nodes as a, packages as b where b.id=a.package and node in (select repository from nodes_vs_nodes where system=?) and id=?');
$requests->{'reset_node'} = $dbh->prepare('update nodes set to_check=?, state=?, importance=? where id=?');
$requests->{'reset_node_package'} = $dbh->prepare('update packages_vs_nodes set state=?, importance=? where package=? and version=? and packages_vs_nodes.release=? and serial=? and node=?');
$requests->{'reset_node_packages'} = $dbh->prepare('update packages_vs_nodes set state=? where node=?');

# основной рабочий цикл
# получение всех узлов, требующих анализа
print STDERR "[DEBUG] Looking for nodes to be checked.\n" if $debug_mode;
$requests->{'get_nodes'}->execute(1);

while (my $node = $requests->{'get_nodes'}->fetchrow_hashref()) {
    print STDERR "[DEBUG] Proceeding with node " . $node->{'name'} . " (ID: " . $node->{'id'} . ").\n" if $debug_mode;
# проверка на репозиторий
    if ($node->{'node_type'} == 1) {
	print STDERR "[DEBUG] It's a repository. Set state to normal value and go to the next node.\n" if $debug_mode;
	$requests->{'reset_node'}->execute(0, $states->{'node'}->{'normal'}, $node->{'importance'}, $node->{'id'});
	$requests->{'reset_node_packages'}->execute($states->{'package'}->{'normal'}, $node->{'id'});
	next;
    }
# речь идёт о системе
    print STDERR "[DEBUG] It's a system. Packages count check.\n" if $debug_mode;
    $requests->{'check_packages_count'}->execute($node->{'id'});
    unless ($requests->{'check_packages_count'}->fetchrow_hashref()->{'count'}) {
	print STDERR "[DEBUG] There are no packages found. Set state to normal.\n" if $debug_mode;
	$requests->{'reset_node'}->execute(0, $states->{'node'}->{'normal'}, $node->{'importance'}, $node->{'id'});
	next;
    }

    print STDERR "[DEBUG] Packages found. Repositories count check.\n" if $debug_mode;
    $requests->{'check_repositories_count'}->execute($node->{'id'});
    unless ($requests->{'check_repositories_count'}->fetchrow_hashref()->{'count'}) {
	print STDERR "[DEBUG] There are no repositories found. Set state to orphaned.\n" if $debug_mode;
	$requests->{'reset_node'}->execute(0, $states->{'node'}->{'orphaned'}, $node->{'importance'}, $node->{'id'});
	$requests->{'reset_node_packages'}->execute($states->{'package'}->{'orphaned'}, $node->{'id'});	
	next;
    }

    print STDERR "[DEBUG] Repositories found. Looking for packages to be checked.\n" if $debug_mode;
# получение списка пакетов системы, нуждающихся в проверке
    $requests->{'get_node_packages'}->execute($node->{'id'});
# если в системе установлено несколько версий одного пакета, анализируется только старшая, остальные считаются нормальными
    my $packages = {};
    while (my $package = $requests->{'get_node_packages'}->fetchrow_hashref()) {
	if (defined $packages->{$package->{'id'}}) {
	    my $check = compare_packages($packages->{$package->{'id'}}, $package);
	    if ($check > 0) {
		$requests->{'reset_node_package'}->execute($states->{'package'}->{'normal'}, $package->{'importance'}, $package->{'id'}, $package->{'version'}, $package->{'release'}, $package->{'serial'}, $node->{'id'});
	    }
	    elsif ($check < 0) {
		$requests->{'reset_node_package'}->execute($states->{'package'}->{'normal'}, $packages->{$package->{'id'}}->{'importance'}, $package->{'id'}, $packages->{$package->{'id'}}->{'version'}, $packages->{$package->{'id'}}->{'release'}, $packages->{$package->{'id'}}->{'serial'}, $node->{'id'});
		$packages->{$package->{'id'}} = $package;
	    }
	}
	else {
	    $packages->{$package->{'id'}} = $package;
	}
    }

    unless (scalar(keys(%$packages))) {
	print STDERR "[DEBUG] There are no packages to be checked. Leave state as it was.\n" if $debug_mode;
	$requests->{'reset_node'}->execute(0, $node->{'state'}, $node->{'importance'}, $node->{'id'});
	next;
    }

    my $analyze = {'state' => $states->{'node'}->{'normal'}, 'importance' => $node->{'importance'}};

    print STDERR "[DEBUG] Packages to be checked found. Proceeding.\n" if $debug_mode;
    foreach my $package_id (keys %$packages) {
# по каждому из проверяемых пакетов определяем альтернативы из доступных репозиториев
# а уже из этих альтернатив выбираем последнюю доступную версию, с которой и будет
# сравниваться пакет, установленный в системе
	$requests->{'get_repository_packages'}->execute($node->{'id'}, $package_id);
	my $rep_package;
	while (my $temp = $requests->{'get_repository_packages'}->fetchrow_hashref()) {
	    $rep_package = ((defined $rep_package) && (compare_packages($rep_package, $temp) > 0)) ? $rep_package : $temp;
	}

# альтернативы нет, пакет - сирота
	unless (defined $rep_package) {
	    $analyze->{'state'} = $states->{'node'}->{'trouble'};
	    $requests->{'reset_node_package'}->execute($states->{'package'}->{'orphaned'}, $packages->{$package_id}->{'importance'}, $package_id, $packages->{$package_id}->{'version'}, $packages->{$package_id}->{'release'}, $packages->{$package_id}->{'serial'}, $node->{'id'});
	    next;
	}

# альтернатива есть, проверяем
	my $check = compare_packages($packages->{$package_id}, $rep_package);
	if ($check > 0) {
	    $analyze->{'state'} = $states->{'node'}->{'trouble'};
	    $requests->{'reset_node_package'}->execute($states->{'package'}->{'new'}, $packages->{$package_id}->{'importance'}, $package_id, $packages->{$package_id}->{'version'}, $packages->{$package_id}->{'release'}, $packages->{$package_id}->{'serial'}, $node->{'id'});
	}
	elsif ($check < 0) {
	    $analyze->{'importance'} = $analyze->{'importance'} > $rep_package->{'importance'} ? $analyze->{'importance'} : $rep_package->{'importance'};
	    $analyze->{'state'} = $states->{'node'}->{'trouble'};
	    $requests->{'reset_node_package'}->execute($states->{'package'}->{'old'}, $rep_package->{'importance'}, $package_id, $packages->{$package_id}->{'version'}, $packages->{$package_id}->{'release'}, $packages->{$package_id}->{'serial'}, $node->{'id'});
	}
	else {
	    $requests->{'reset_node_package'}->execute($states->{'package'}->{'normal'}, $packages->{$package_id}->{'importance'}, $package_id, $packages->{$package_id}->{'version'}, $packages->{$package_id}->{'release'}, $packages->{$package_id}->{'serial'}, $node->{'id'});
	}
    }

# if system is in normal state, reduce it's importance
    $analyze->{'importance'} = ($analyze->{'state'} == $states->{'node'}->{'normal'}) ? 1 : $analyze->{'importance'};

    print STDERR "[DEBUG] Packages checked. Updating system state.\n" if $debug_mode;
    $requests->{'reset_node'}->execute(0, $analyze->{'state'}, $analyze->{'importance'}, $node->{'id'});
}

# по завершению работы - завершаем все запросы к БД
print STDERR "[DEBUG] Closing all database requests.\n" if $debug_mode;
map ($requests->{$_}->finish(), keys(%$requests));

# закрыли соединение с базой
print STDERR "[DEBUG] Disconnecting from database.\n" if $debug_mode;
$dbh->disconnect();

# функция сравнения двух пакетов
# аргументы - ссылки на хеши, соответствующие пакетам
# результат - 0 - если пакеты равны
# 1 - если более новым является первый пакет
# -1 - если более новым является второй пакет
sub compare_packages {
    my $package_1 = shift;
    my $package_2 = shift;

    my $result;

    my $serial1 = $package_1->{'serial'};
    my $serial2 = $package_2->{'serial'};
    ($serial1 = -1) unless check_digit($serial1);
    ($serial2 = -1) unless check_digit($serial2);

    $result = ($serial1 <=> $serial2);

    return $result if $result;

    my @temp1 = split(/\./, $package_1->{'version'});
    my @temp2 = split(/\./, $package_2->{'version'});

    for (my $i=0; $i < scalar(@temp1); $i++) {
	if (defined $temp2[$i]) {
	    if (check_digit($temp1[$i]) && check_digit($temp2[$i])) {
		$result = ($temp1[$i] <=> $temp2[$i]);
	    }
	    else {
		$result = ($temp1[$i] cmp $temp2[$i]);
	    }
	}
	else {
	    $result = 1;
	}
    	last if $result;
    }

    return $result if $result;

    return -1 if (scalar(@temp2) > scalar(@temp1));

    if (check_digit($package_1->{'release'}) && check_digit($package_2->{'release'})) {
	$result = ($package_1->{'release'} <=> $package_2->{'release'});
    }
    else{
	($package_1->{'release'} =~ /^([A-Za-z]+)([0-9]+)/);
	my $prefix = $1;
	my $version = $2;
	if (defined $prefix && ($package_2->{'release'} =~ /^$prefix([0-9]+)/)) {
	    $result = ($version <=> $1);
	    if (!$result && ($package_1->{'release'} ne $package_2->{'release'})) {
		$result = ($package_1->{'release'} cmp $package_2->{'release'});
	    }
	}
	else {
	    $result = ($package_1->{'release'} cmp $package_2->{'release'});
	}
    }

    return $result;

}

# функция: check_digit
# args: проверяемая величина
# returns: 0 в случае неудачной проверки, 1 в случае удачной
# description: проверяет, является ли величина целым числом
sub check_digit {
    my $value = shift;

    return 0 unless defined $value;
    return ($value =~ /^[0-9]+$/);
}
