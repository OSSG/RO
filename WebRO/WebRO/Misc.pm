# WebRO - Web interface for RO (Repository Observer)
# Service functions module
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

# модуль сервисных функций

package WebRO::Misc;

use strict;

use Exporter;

@WebRO::Misc::ISA = ('Exporter');
@WebRO::Misc::EXPORT = qw(&pager &check_digit &quote &quote_hash &db_pattern_quote);

# function: pager
# args: структура данных
# returns: навигационная структура
# description: строит по структуре данных навигационную структуру
# формат структуры данных: {	'limit' => число записей на странице,
#				'count' => число записей,
#				'page' => текущая страница}
# формат навигационной структуры: {	'pages_count' => число страниц,
#					'limit => число записей на странице,
#					'page' => текущая страница,
#					'items' => число записей,
#	 				'beg' => страница, начинающая навигацию,
#					'end' => страница, заканчивающая навигацию
#				}
sub pager {
    my $data = shift;

    my $pager = {
	'pages_count' => int($data->{'count'} / $data->{'limit'}) + ($data->{'count'} % $data->{'limit'} ? 1 : 0),
	'limit'	=> $data->{'limit'},
	'page' => $data->{'page'},
	'items' => $data->{'count'}
    };

    if ($pager->{'pages_count'} > 9) {
	$pager->{'beg'} = ($pager->{'page'} < 4) ? 0 : ($pager->{'page'}  - 4);
	$pager->{'end'} = (($pager->{'pages_count'} - $pager->{'page'}) > 5) ? ($pager->{'page'} + 4) : ($pager->{'pages_count'} - 1);
	if (($pager->{'end'} - $pager->{'beg'})<8) {
	    if ($pager->{'end'} == ($pager->{'pages_count'} - 1)) { $pager->{'beg'} = $pager->{'end'} - 8; }
	    else { $pager->{'end'} = $pager->{'beg'} + 8; }
	}
    } else {
	$pager->{'beg'} = 0;
	$pager->{'end'} = $pager->{'pages_count'} - 1;
    }

    return $pager;
}

# function: check_digit
# args: проверяемая величина
# returns: 0 в случае неудачной проверки, 1 в случае удачной
# description: проверяет, является ли величина целым числом
sub check_digit {
    my $value = shift;

    return 0 unless defined $value;
    return ($value =~ /^[0-9]+$/);
}

# function: quote
# args: строка
# returns: квотированная строка
# description: квотирует строку для использования в html/xhtml
# можно было бы воспользоваться средствами модуля CGI, но там есть проблемы с юникодом.
sub quote {
    my $string = shift;
    return undef unless defined $string;
    $string =~ s/\&/\&amp\;/g;
    $string =~ s/\"/\&quot\;/g;
    $string =~ s/\</\&lt\;/g;
    $string =~ s/\>/\&gt\;/g;
    return $string;
}

# function: quote_hash
# args: ссылка на хеш
# returns: ссылка на квотированный хеш
# description: функция квотирования всех полей хеша
sub quote_hash {
    my $hash = shift;

    foreach my $field (keys (%$hash)) {
    	$hash->{$field} = quote($hash->{$field});
    }

    return $hash;
}

# function: db_pattern_quote
# args: строка-шаблон
# returns: квотированная строка-шаблон
# description: функция квотирования шаблона поиска в БД
sub db_pattern_quote {
    my $string = shift;
    $string =~ s/\\/\\\\/g;
    $string =~ s/\%/\\\%/g;
    $string =~ s/_/\\_/g;
    return $string;
}

1;
