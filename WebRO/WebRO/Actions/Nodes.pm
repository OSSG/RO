# WebRO - Web interface for RO (Repository Observer)
# Nodes management module
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

# модуль работы с узлами
package WebRO::Actions::Nodes;

use strict;

use WebRO::Analyzer;
use WebRO::Common;
use WebRO::Misc;

sub action {
    my $db = shift;
    $db = $$db;
    my $request = shift;
    $request = $$request;
    my $config = shift;

    my $data;

# определение запрошенного действия (если оно было)
    my $action = $request->param('action') || '';
# создание нового узла
    if ($action eq 'create_node') {
	my $node = {'name' => $request->param('node_name'),
		    'signature' => $request->param('signature'),
		    'notes' => $request->param('notes') || '',
		    'node_type' => $request->param('node_type')
	};
	$data->{'error'} = check_node(\$db, $node);
	unless (defined $data->{'error'}) {
	    if ($db->sql_exec('insert into nodes (name, signature, notes, node_type) values (?, ?, ?, ?)', $node->{'name'}, $node->{'signature'}, $node->{'notes'}, $node->{'node_type'})) {
		$data->{'message'} = 'Node created.';
	    }
	    else {
		$data->{'error'} = 'Database error!';
	    }
	}
    }
# удаление существующего узла
    elsif ($action eq 'drop_node') {
	my $node = $request->param('id');
	if (defined $node && check_digit($node)) {
	    $db->sql_exec('update nodes set to_check=? where id in (select system from nodes_vs_nodes where repository=?)', 1, $node);
	    if ($db->sql_exec('delete from nodes where id=?', $node)) {
		$db->sql_exec('delete from packages_vs_nodes where node=?', $node);
		$db->sql_exec('delete from nodes_vs_nodes where system=? or repository=?', $node, $node);
		$data->{'message'} = 'Node deleted.';
	    }
	    else {
		$data->{'error'} = 'Database error!';
	    }
	}
	else {
	    $data->{'error'} = 'Bad node id!';
	}
    }

    my $limit = check_digit($config->{'nodes_list_limit'}) ? $config->{'nodes_list_limit'} : 25;

# подготовка к возможной фильтрации узлов
    my @args;
    my $condition = '';
    $data->{'query_string'} = '';

# проверка задания фильтра
    my $filter = $request->param('filter') || '';
    if ($filter ne '') {
# фильтр задан - в запросе появляется условие отбора
	$condition = ' where upper(name) like ?';
	push(@args, '%' . uc(db_pattern_quote($filter)) . '%');
# информация о критерии отбора будет передана в шаблон
	$data->{'filter'} = quote($filter);
	$data->{'query_string'} .= '&amp;filter=' . $request->escape($filter);
    }

# получение общего числа узлов
    my $count = $db->sql_select('select count(*) as count from nodes' . $condition, @args)->[0]->{'count'};

    my $page = $request->param('page');
    $page = (defined $page && check_digit($page)) ? $page : 0;

# создание пейджера для списка узлов. если указанная страница превышает общее число страниц списка,
# то считается, что запрошена первая страница и пейджер создается заново.

    do {
	if ($data->{'pager'}) { $page = 0; }
	$data->{'pager'} = pager({'limit' => $limit, 'count' => $count, 'page' => $page});

    } while (($page >= $data->{'pager'}->{'pages_count'}) && ($count > 0));

# получение списка пакетов (нужной страницы)
    $data->{'nodes'} = $db->sql_select('select * from nodes' . $condition . ' order by node_type asc, state desc, importance desc, name asc limit ' . $limit . ' offset ' . $page*$limit, @args);

    foreach (@{$data->{'nodes'}}) {
	$_->{'name'} = quote($_->{'name'});
	$_->{'signature'} = quote($_->{'signature'});
	$_->{'troubles'} = analyze_node(\$db, $_->{'id'});
    }

    return {'data' => $data};
}

1;
