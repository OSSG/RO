#!/usr/bin/perl -wT
# RO (Repository Observer) - Server script
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
use CGI::Fast;
use DBI;
use XML::Simple;

use constant NOT_FOUND => 404;
use constant OK => 200;

my $xs = new XML::Simple(ForceArray => [ 'package' ], KeyAttr => []);

# конфигурация (лежит в файле './config')
my $config = do('./config');

# установка флага ведения лога
my $log_mode = ((defined $config->{'log'}) && (ref($config->{'log'}) eq 'HASH') && $config->{'log'}->{'use_log'}) ? 1 : 0;

# инициализация соединения с базой данных и подготовка необходимых запросов
my $dbh = DBI->connect('dbi:' . $config->{'database'}->{'db_driver'} .
			':dbname=' . $config->{'database'}->{'db_name'} .
			';host=' . $config->{'database'}->{'db_host'},
			$config->{'database'}->{'db_user'},
			$config->{'database'}->{'db_passwd'},
			$config->{'database'}->{'db_options'}) ||
		die "[ERROR]: Cann't connect to events database: $DBI::errstr";

# для предотвращения автоматического разрыва умным mysql соединения по тайм-ауту (т.н. 'morning bug')
$dbh->{'mysql_auto_reconnect'} = 1 if ($config->{'database'}->{'db_driver'} eq 'mysql');

my $requests = {};
$requests->{'check_node_id'} = $dbh->prepare('select id from nodes where signature=?');
$requests->{'add_new_package'} = $dbh->prepare('insert into packages (name) values (?)');
$requests->{'add_node_package'} = $dbh->prepare('insert into packages_vs_nodes (package, node, version, packages_vs_nodes.release, serial, importance, summary) values (?, ?, ?, ?, ?, ?, ?)');
$requests->{'check_package_existence'} = $dbh->prepare('select id from packages where name=?');
$requests->{'check_node_package_existence'} = $dbh->prepare('select count(*) as count from packages_vs_nodes where node=? and package=(select id from packages where name = ?) and version = ? and packages_vs_nodes.release=? and serial=?');
$requests->{'check_node_sync_time'} = $dbh->prepare('select (sync_time <> \'0000-00-00 00:00:00\') as result from nodes where id=?');
$requests->{'delete_node_package'} = $dbh->prepare('delete from packages_vs_nodes where node=? and package=(select id from packages where name = ?) and version = ? and packages_vs_nodes.release=? and serial=?');
$requests->{'delete_node_packages'} = $dbh->prepare('delete from packages_vs_nodes where node=?');
$requests->{'update_node_status'} = $dbh->prepare('update nodes set to_check=? where id=? or id in (select system from nodes_vs_nodes where repository=?)');
$requests->{'update_node_sync_time'} = $dbh->prepare('update nodes set sync_time=now() where id=?');

$requests->{'garbage_collector'} = $dbh->prepare('delete from packages where (select count(*) from packages_vs_nodes where package=packages.id) = ?');

# основной рабочий цикл
while(my $request = new CGI::Fast) {

# определение запрошенного url
    my $url = $request->url(-relative => 1);

    log_string('Incoming request.', 'notice') if $log_mode;

    my $content = '';

# url не должен отличаться от корневого - иначе документ не найден
    unless (defined $url) {

# получение операции над списком пакетов узла (инициализация или обновление)
	my $action = $request->param('action') || '';
	if (($action eq 'init') || ($action eq 'refresh')) {

# получение сигнатуры узла
	    my $node = $request->param('node') || '';

# проверка сигнатуры узла - получение id узла
	    $requests->{'check_node_id'}->execute($node);
	    my $temp = $requests->{'check_node_id'}->fetchrow_hashref();
	    if ((defined $temp) && (my $node_id = $temp->{'id'})) {

# инициализация узла
		if ($action eq 'init') {

		    log_string('Initializing node ' . $node, 'notice') if $log_mode;

# получение списка пакетов (один параметр)
		    my $packages = $request->param('packages');
		    if (defined $packages) {

# парсинг списка
			my $packages_list = eval { $xs->XMLin($packages) };
# список есть, но его формат неизвестен - ошибка
			if ($@) {
			    $content = "[ERROR] Unknown packages list format!\n";
			    log_string('Unknown packages list format!', 'error') if $log_mode;
			}
# список пакетов доступен в виде массива анонимных хешей
			else {

# удаление всех старых пакетов
			    $requests->{'delete_node_packages'}->execute($node_id);

# если старые пакеты были - об этом можно сказать
			    if (my $temp = $requests->{'delete_node_packages'}->rows()) {
			        $content .= "[NOTICE] $temp old packages removed.\n";
				log_string($temp . ' old packages removed.', 'notice') if $log_mode;
			    }

# добавление списка в базу
# инициализация счётчика добавленных пакетов
			    my $counter = 0;
			    foreach my $package (@{$packages_list->{'package'}}) {
				unless (defined $package->{'name'} &&
				    defined $package->{'version'} &&
				    defined $package->{'release'} &&
				    defined $package->{'serial'}) {
					$content .= "[ERROR] Encountered bad package description!\n";
					log_string('Encountered bad package description!', 'error') if $log_mode;
					next;
				}
# известен ли пакет?
				$requests->{'check_package_existence'}->execute($package->{'name'});
# попытка получения id пакета
				my $temp = $requests->{'check_package_existence'}->fetchrow_hashref();
				if ((!defined $temp) || !($package->{'id'} = $temp->{'id'})) {
# если пакет неизвестен - добавление имени пакета и получение id добавленного
				    $requests->{'add_new_package'}->execute($package->{'name'});
# 				    $package->{'id'} = $dbh->{'mysql_insertid'};
				    $requests->{'check_package_existence'}->execute($package->{'name'});
				    $package->{'id'} = $requests->{'check_package_existence'}->fetchrow_hashref()->{'id'};
				}

# добавление в базу связи между пакетом и узлом системы
				$requests->{'add_node_package'}->execute($package->{'id'}, $node_id, $package->{'version'}, $package->{'release'}, $package->{'serial'}, $package->{'importance'} || 1, $package->{'summary'} || '');
				$counter++;
			    }
# установка нового времени последней синхронизации системы
			    $requests->{'update_node_sync_time'}->execute($node_id);
# помечаем узел и все связанные узлы как требующие проверки
			    $requests->{'update_node_status'}->execute(1, $node_id, $node_id);
			    log_string('Added ' . $counter . ' packages.', 'notice') if $log_mode;
			}
		    }
		    else {
			$content = "[ERROR] Packages list not specified!\n";
			log_string('Packages list not specified!', 'error') if $log_mode;
		    }
		
		}
# обновление узла
		else {
		
		    log_string('Refreshing node ' . $node, 'notice') if $log_mode;
# проверка времени прежней синхронизации (была ли она вообще)
		    $requests->{'check_node_sync_time'}->execute($node_id);
		    if ($requests->{'check_node_sync_time'}->fetchrow_hashref()->{'result'}) {
# получение двух списков: 1) удалённые 2) добавленные
			my $added_packages = $request->param('added_packages');
			my $removed_packages = $request->param('removed_packages');
			if (defined $added_packages && defined $removed_packages) {
			    my $added_packages_list = eval { $xs->XMLin($added_packages) };
			    my $temp = $@;
			    my $removed_packages_list = eval { $xs->XMLin($removed_packages) };
			    if ($temp || $@) {
				$content = "[ERROR] Unknown packages list format!\n";
				log_string('Unknown packages list format!', 'error') if $log_mode;
			    }
			    else {
# удаление пакетов
# инициализация счётчика удалённых пакетов
				my $counter = 0;
				foreach my $package (@{$removed_packages_list->{'package'}}) {
				    unless (defined $package->{'name'} &&
					defined $package->{'version'} &&
					defined $package->{'release'} &&
					defined $package->{'serial'}) {
					    $content .= "[ERROR] Encountered bad package description!\n";
					    log_string('Encountered bad package description!', 'error') if $log_mode;
					    next;
				    }
# установлен ли удаляемый пакет?
				    $requests->{'check_node_package_existence'}->execute($node_id, $package->{'name'}, $package->{'version'}, $package->{'release'}, $package->{'serial'});
# если пакет установлен - он удаляется
				    if ($requests->{'check_node_package_existence'}->fetchrow_hashref()->{'count'}) {
					$requests->{'delete_node_package'}->execute($node_id, $package->{'name'}, $package->{'version'}, $package->{'release'}, $package->{'serial'});
					$counter++;
				    }
# если удаляемый пакет не был установлен - предупреждение
				    else {
					$content .= "[WARNING] Can't delete not installed package!\n";
					log_string('Can\'t delete not installed package (\'' . $package->{'name'} . '\')!', 'warn') if $log_mode;
				    }
				}

				log_string('Removed ' . $counter . ' packages.', 'notice') if $log_mode;

# добавление пакетов
# инициализация счётчика добавленных пакетов
				$counter = 0;
				foreach my $package (@{$added_packages_list->{'package'}}) {
				    unless (defined $package->{'name'} &&
					defined $package->{'version'} &&
					defined $package->{'release'} &&
					defined $package->{'serial'}) {
					    $content .= "[ERROR] Encountered bad package description!\n";
					    log_string('Encountered bad package description!', 'error') if $log_mode;
					    next;
				    }
# установлен ли уже добавляемый пакет?
				    $requests->{'check_node_package_existence'}->execute($node_id, $package->{'name'}, $package->{'version'}, $package->{'release'}, $package->{'serial'});

				    unless ($requests->{'check_node_package_existence'}->fetchrow_hashref()->{'count'}) {
# известен ли уже пакет?
					$requests->{'check_package_existence'}->execute($package->{'name'});
# попытка получения id пакета
					my $temp = $requests->{'check_package_existence'}->fetchrow_hashref();
					if ((!defined $temp) || !($package->{'id'} = $temp->{'id'})) {
# если пакет неизвестен - добавление имени пакета и получение id добавленного
					    $requests->{'add_new_package'}->execute($package->{'name'});
# 				    $package->{'id'} = $dbh->{'mysql_insertid'};
					    $requests->{'check_package_existence'}->execute($package->{'name'});
					    my $temp = $requests->{'check_package_existence'}->fetchrow_hashref();
					    $package->{'id'} = defined $temp ? $temp->{'id'} : 0;
					}
# добавление в базу связи между пакетом и узлом системы
					$requests->{'add_node_package'}->execute($package->{'id'}, $node_id, $package->{'version'}, $package->{'release'}, $package->{'serial'}, $package->{'importance'} || 1, $package->{'summary'} || '');
					$counter++;
				    }
# если пакет уже установлен - предупреждение
				    else {
					$content .= "[WARNING] Can't add already installed package!\n";
					log_string('Can\'t add already installed package (\'' . $package->{'name'} . '\')!', 'warn') if $log_mode;
				    }
				}
# установка нового времени последней синхронизации системы
				$requests->{'update_node_sync_time'}->execute($node_id);
# помечаем узел и все связанные узлы как требующие проверки
				$requests->{'update_node_status'}->execute(1, $node_id, $node_id);
				log_string('Added ' . $counter . ' packages.', 'notice') if $log_mode;
			    }
			}
			else {
			    $content = "[ERROR] Packages lists not specified!\n";
			    log_string('Packages lists not specified!', 'error') if $log_mode;
			}
		    }
		    else {
			$content = "[ERROR] Can't refresh not initialized node!\n";
			log_string('Can\'t refresh not initialized node!', 'error') if $log_mode;
		    }
		}
	    }
	    else {
# проверка сигнатуры провалена - узел неизвестен
		$content = "[ERROR] Unknown node!\n";
		log_string('Unknown node \'' . $node . '\'!', 'error') if $log_mode;
	    }

	}
	else {
	    $content = "[ERROR] Unknown action!\n";
	    log_string('Unknown action \'' . $action . '\'!', 'error') if $log_mode;
	}

# вывод результата работы
	print $request->header({'type'=>'text/plain'});
	print $content;

# очистка мусора
	$requests->{'garbage_collector'}->execute(0);
    }
# документ не найден
    else {
	print $request->header({'status' => NOT_FOUND, 'type' => 'text/plain'});
	log_string('Bad request! Requested URL: ' . $url, 'error') if $log_mode;
	print '404 Not Found';
    }



}

# по завершению работы - завершаем все запросы к БД
map ($requests->{$_}->finish(), keys(%$requests));

# закрыли соединение с базой
$dbh->disconnect();

sub log_string {
    my $string = shift;
    my $type = shift;

# попытка открыть лог
    unless (open(LOG, '>>' . $config->{'log'}->{'log_file'}) && flock(LOG, 2)) {
# открыть лог не удалось, но на работу скрипта это влиять не должно,
# просто выругались и вернулись к основному делу
        warn "Can't open and lock log file $config->{'log'}->{'log_file'} for write: $!\n";
        return 0;
    }
    else {
	print LOG "[" . localtime(time) . "] [$$] [" . ({'notice' => 'NOTICE', 'error' => 'ERROR', 'warn' => 'WARNING'}->{$type} || 'NOTICE') . "] " . $string . "\n";
    }

# закрыли лог
    close LOG;
    return 1;
}