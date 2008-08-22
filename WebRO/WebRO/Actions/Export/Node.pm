# WebRO - Web interface for RO (Repository Observer)
# Node management module
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

# модуль экспорта данных узла
package WebRO::Actions::Export::Node;

use strict;

use constant OK => 200;

use WebRO::Misc;

sub action {
    my $db = shift;
    $db = $$db;
    my $request = shift;
    $request = $$request;
    my $config = shift;

# получение id узла
    my $node = $request->param('id');
# проверка корректности id
    $node = (defined $node && check_digit($node)) ? $node : undef;
    return {'error' => 1} unless defined $node;
# проверка существования узла с указанным id
    return {'error' => 1} unless _check_node(\$db, $node);

# определение набора экспортируемых данных
    my $action = $request->param('action') || '';

    if ($action eq 'all_packages') {
# запрошен экспорт всех пакетов узла
# определение формата экспорта
	my $format = $request->param('format') || 'txt';
# проверка запрошенного формата
	return {'error' => 3} unless exists {'txt' => 1}->{$format};

# получение списка пакетов
	my $packages = $db->sql_select('select a.name as name from packages as a, packages_vs_nodes as b where a.id = b.package and b.node = ?', $node);

	if ($format eq 'txt') {
# выдача списка пакетов в виде простого текстового документа
	    return { '_header' => {'status' => OK, 'type' => 'text/plain'},
		     'export' => join("\n", sort (map { $_->{'name'} } (@$packages))) };
	}

    }
    else {
# набор экспортируемых данных неизвестен
	return {'error' => 2};
    }

}

# функция проверки узла системы на существование
# аргументы: ссылка на объект работы с БД, id узла
# возвращает 1 в случае существования узла, либо 0 в случае его отсутствия
sub _check_node {
    my $db = shift;
    $db = $$db;
    my $node = shift;

    return $db->sql_select('select count(*) as count from nodes where id=?', $node)->[0]->{'count'};
}

1;
