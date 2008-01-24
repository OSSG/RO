# WebRO - Web interface for RO (Repository Observer)
# Packages management module
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

# модуль работы с пакетами
package WebRO::Actions::Packages;

use strict;

use WebRO::Analyzer;
use WebRO::Misc;

sub action {
    my $db = shift;
    $db = $$db;
    my $request = shift;
    $request = $$request;
    my $config = shift;

    my $limit = check_digit($config->{'packages_list_limit'}) ? $config->{'packages_list_limit'} : 25;

    my $count = $db->sql_select('select count(distinct(package)) as count from packages_vs_nodes')->[0]->{'count'};

    my $page = $request->param('page');
    $page = (defined $page && check_digit($page)) ? $page : 0;

# создание пейджера для списка узлов, если указанная страница превышает общее число страниц списка,
# то считается, что запрошена первая страница и пейджер создается заново.
    my $list;
    do {
	if ($list->{'pager'}) { $page = 0; }
	$list->{'pager'} = pager({'limit' => $limit, 'count' => $count, 'page' => $page});

    } while (($page >= $list->{'pager'}->{'pages_count'}) && ($count > 0));

# получение списка пакетов (нужной страницы)
    $list->{'packages'} = $db->sql_select('select distinct(package) as id, name from packages_vs_nodes right join packages on packages.id=packages_vs_nodes.package order by name limit ' . $limit . ' offset ' . $page*$limit);

    foreach (@{$list->{'packages'}}) {
	$_->{'name'} = quote($_->{'name'});
	$_->{'troubles'} = analyze_package(\$db, $_->{'id'});
    }

    return {'data' => $list};
}

1;
