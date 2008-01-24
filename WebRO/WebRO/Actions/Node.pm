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

# модуль работы с узлом
package WebRO::Actions::Node;

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

    my $node = $request->param('id');
    $node = (defined $node && check_digit($node)) ? $node : undef;
    return {'error' => 1} unless defined $node;

    $node = _get_node(\$db, $node);
    return {'error' => 1} unless (defined $node->{'id'});

# определение запрошенного действия (если оно было)
    my $action = $request->param('action') || '';

    my $data = {};

# изменение узла
    if ($action eq 'change_node') {
	my $new_node = {'name' => $request->param('node_name'),
		    'signature' => $request->param('signature'),
		    'notes' => $request->param('notes') || '',
		    'node_type' => $node->{'node_type'},
		    'id' => $node->{'id'}
	};
	if ($node->{'node_type'} == 0 && !$node->{'to_check'}) {
	    $db->sql_exec('delete from nodes_vs_nodes where system=?', $node->{'id'});
	    my @temp = $request->param('repositories');
	    if (scalar(@temp)) {
	        foreach (@temp) {
		    if (check_digit($_)) {
			$db->sql_exec('insert into nodes_vs_nodes (system, repository) values (?, ?)', $node->{'id'}, $_);
		    }
		}
	    }
	    $db->sql_exec('update nodes set to_check=? where id=?', 1, $node->{'id'});
	}

	$data->{'error'} = check_node(\$db, $new_node);
	unless (defined $data->{'error'}) {
	    if ($db->sql_exec('update nodes set name=?, signature=?, notes=? where id=?', $new_node->{'name'}, $new_node->{'signature'}, $new_node->{'notes'}, $node->{'id'})) {
		$data->{'message'} = 'Node changed.';
# обновление информации об узле
		$node = _get_node(\$db, $node->{'id'});
	    }
	    else {
		$data->{'error'} = 'Database error!';
	    }
	}
    }

    $node->{'troubles'} = analyze_node(\$db, $node->{'id'});

# получение идентификаторов всех узлов, связанных с узлом
    my $nodes = $db->sql_select(
	($node->{'node_type'} == 1) ?
	    'select system as node_id from nodes_vs_nodes where repository=?' :
	    'select repository as node_id from nodes_vs_nodes where system=?', $node->{'id'});

    foreach (@$nodes) {
	$_ = _get_node(\$db, $_->{'node_id'});
	$_->{'troubles'} = analyze_node(\$db, $_->{'id'});
    }

    my $result = {'node' => $node, 'nodes' => $nodes, 'data' => $data};

# получение всех доступных репозиториев - если речь идёт о системе
    if ($node->{'node_type'} == 0) {
	my $repositories = $db->sql_select('select *, (select count(*) from nodes_vs_nodes where repository=nodes.id and system=?) as selected from nodes where node_type=? order by name', $node->{'id'}, 1);
	foreach (@$repositories) {
	    $_ = quote_hash($_);
	}
	$result->{'repositories_list'} = $repositories;
	$result->{'repositories_list_limit'} = check_digit($config->{'repositories_list_limit'}) ? $config->{'repositories_list_limit'} : 5;
    }

    return $result;
}

# функция получение узла системы
# аргументы: ссылка на объект работы с БД, id узла
# возвращает хеш с данными узла
sub _get_node {
    my $db = shift;
    $db = $$db;
    my $node = shift;

    $node = $db->sql_select('select *, (select count(*) from packages_vs_nodes where node=nodes.id) as packages from nodes where id=?', $node)->[0];

    if (defined $node->{'id'}) {
	$node = quote_hash($node);
    }

    return $node;    
}

1;
