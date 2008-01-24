# WebRO - Web interface for RO (Repository Observer)
# Common special functions module
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

# модуль с общими для обработчиков специальными функциями
package WebRO::Common;

use strict;

use constant MAX_NODE_LENGTH => 127;
use constant MAX_SIGN_LENGTH => 32;

use Exporter;

@WebRO::Common::ISA = ('Exporter');
@WebRO::Common::EXPORT = qw(&check_node);

# функция проверки данных узла системы
# аргументы: ссылка на объект работы с БД, хеш с данными узла
# возвращает undef в случае успешной проверки, либо сообщение об ошибке
sub check_node {
    my $db = shift;
    my $node = shift;

    if ((!defined $node->{'name'}) || !length($node->{'name'}) || (length($node->{'name'}) > MAX_NODE_LENGTH)) {
	return 'Bad node name!';
    }
    elsif ((!defined $node->{'signature'}) || !length($node->{'signature'}) || (length($node->{'signature'}) > MAX_SIGN_LENGTH) || !_check_node_signature($db, $node->{'signature'}, $node->{'id'})) {
	return 'Bad signature!';
    }
    elsif (($node->{'node_type'} != 1) && ($node->{'node_type'} != 0)) {
	return 'Bad node type!';
    }

    return undef;
}

# функция проверки подписи узла (можно ли создать узел с указанной подписью или изменить подпись существующего узла)
# проверяет, существуют ли уже в БД узлы с указанной подписью
# возвращает 0 в случае проваленной проверки, 1 - в случае успешной)
# аргументы: ссылка на объект работы с БД, проверяемая подпись, опционально - id узла
sub _check_node_signature {
    my $db = shift;
    $db = $$db;
    my $signature = shift;
    my $id = shift;
    return 0 unless defined $signature;
    return defined $id ?
    ($db->sql_select('select count(*) as count from nodes where signature=? and id <> ?', $signature, $id)->[0]->{'count'} ? 0 : 1) :
    ($db->sql_select('select count(*) as count from nodes where signature=?', $signature)->[0]->{'count'} ? 0 : 1);
}

1;
