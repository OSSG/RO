# WebRO - Web interface for RO (Repository Observer)
# Analyzer module
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

# модуль анализатора проблем с узлами
# (проверка проблемности пакета / узла, вывод всех проблемных пакетов в RO и по конкретному узлу)

package WebRO::Analyzer;

use strict;

use WebRO::Misc;

use Exporter;

@WebRO::Analyzer::ISA = ('Exporter');
@WebRO::Analyzer::EXPORT = qw(&analyze_package &analyze_node);


# отталкиваемся от систем
# берём все системы
# по каждой из систем берём соответствующие репозитории
# смотрим _максимальные_ версию, релиз и сериал пакета в репозиториях
# первична - версия, затем - релиз, затем - сериал
# и сравниваем с показателями для системы
# если не равно -> проблема
sub analyze_package {
    my $db = shift;
    $db = $$db;
    my $package_id = shift;

    my $result = [];

    my $request = 'select a.*, b.to_check, b.id as node_id, b.name as node_name, c.name as state
		    from packages_vs_nodes as a, nodes as b, package_states as c
		    where b.id=a.node and a.package=? and b.node_type=? and c.id=a.state';

# получение списка с данными по системам, где установлен пакет
    my $temp = $db->sql_select($request, $package_id, 0);

    foreach (@$temp) {
	    push (@$result, {
		'system' => {'id' => $_->{'node_id'}, 'name' => quote($_->{'node_name'}), 'to_check' => $_->{'to_check'}},
	        'trouble' => ($_->{'state'} eq 'Normal') ? 0 : 1,
		'state' => $_->{'state'},
		'version' => $_->{'version'},
		'release' => $_->{'release'},
		'serial' => $_->{'serial'},
		'importance' => $_->{'importance'}
	    });
    }

    return $result;
}

sub analyze_node {
    my $db = shift;
    $db = $$db;
    my $node_id = shift;

    my $system = $db->sql_select('select a.id, a.node_type, b.name as state, a.importance, a.to_check from nodes as a, node_states as b where a.id=? and b.id=a.state', $node_id)->[0];

    return {'trouble' => 0, 'state' => 'Normal'} if (!defined $system->{'id'} || ($system->{'node_type'} == 1) || $system->{'to_check'} || ($system->{'state'} eq 'Normal'));

    my $result = {'trouble' => 1, 'state' => $system->{'state'}, 'importance' => $system->{'importance'}};

    $result->{'packages'} = $db->sql_select('select b.id, b.name, a.version, a.release, a.serial, a.importance, c.name as state
					    from packages_vs_nodes as a, packages as b, package_states as c
				    where a.node=? and a.state=c.id and a.package=b.id and c.name <> ? order by name', $node_id, 'Normal');

    foreach (@{$result->{'packages'}}) {
	$_->{'name'} = quote($_->{'name'});
    }

    return $result;
}

1;
