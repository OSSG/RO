# WebRO - Web interface for RO (Repository Observer)
# Package management module
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

# модуль работы с пакетом
package WebRO::Actions::Package;

use strict;

use WebRO::Analyzer;
use WebRO::Misc;

sub action {
    my $db = shift;
    $db = $$db;
    my $request = shift;
    $request = $$request;

    my $package = $request->param('id');
    $package = (defined $package && check_digit($package)) ? $package : undef;

    return {'error' => 1} unless defined $package;

    $package = $db->sql_select('select * from packages where id=?', $package)->[0];
    return {'error' => 1} unless (defined $package->{'id'});

    $package->{'name'} = quote($package->{'name'});

    $package->{'troubles'} = analyze_package(\$db, $package->{'id'});

# получение всех узлов, связанных с пакетом
    my $nodes = $db->sql_select('select b.name, b.id, b.to_check, b.node_type, a.version, a.release, a.serial, a.importance, a.summary from packages_vs_nodes as a, nodes as b where a.node=b.id and a.package=?', $package->{'id'});

# выделение систем и репозиториев
    my $systems = [];
    my $repositories = [];
# квотирование данных
    foreach (@$nodes) {
	$_ = quote_hash($_);
# дополнительные манипуляции с саммари пакета - для правильного отображения на веб-странице
	$_->{'summary'} =~ s~/n~<br />~g;
# репозитории
	if ($_->{'node_type'} == 1) {
	    push (@$repositories, $_);
	}
# системы
	else {
	    push (@$systems, $_);
	}
    }

    return {'package' => $package, 'repositories' => $repositories, 'systems' => $systems};
}

1;
