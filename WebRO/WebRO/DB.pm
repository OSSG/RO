# WebRO - Web interface for RO (Repository Observer)
# DB interaction module
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

# модуль взаимодействия с БД
# обеспечивает установку соединения с БД, выполнение запросов в БД,
# кеширование запросов в памяти

package WebRO::DB;

use strict;

use DBI;

# метод-конструктор
# возвращает объект с БД (параметры подключения задаются в конфигурации)
sub new {
    my $package = shift;
    my $param = shift;
    my $self = {};

# приготовление кеша запросов в БД
    $self->{'requests'} = {};

# установка соединения с начальной базой
    unless (${$self->{'database'}} = DBI->connect('dbi:' . $param->{'db_driver'} .
					    ':dbname=' . $param->{'db_name'} .
					    ';host=' . $param->{'db_host'},
					    $param->{'db_user'}, $param->{'db_passwd'},
					    $param->{'db_options'})) {
        warn "Cann't connect to database server: $DBI::errstr";
        ${$self->{'database'}} = undef;
    }

# для предотвращения автоматического разрыва умным mysql соединения по тайм-ауту (т.н. 'morning bug')
    ${$self->{'database'}}->{'mysql_auto_reconnect'} = 1 if ($param->{'db_driver'} eq 'mysql');

    $self = bless($self, $package);

    return $self;
}

# метод для выполнения запроса к БД, не предполагающего получение какой либо выборки
# (update / insert / delete и т.д.)
# аргументы: первый (опционально) - флаг кеширования запроса в виде массива из одного элемента
# (по умолчанию запрос кешируется)
# затем - запрос и массив подстановочных данных (на место плейсхолдеров)
# примеры: $database->sql_exec([0], 'select 1');
# возвращает 0 в случае ошибки запроса, либо 1 в случае успешного выполнения запроса
sub sql_exec {
    my $self = shift;
    my $request = shift;
# определение необходимости кеширования запроса
    my $cache = 1;
    if (ref($request) eq 'ARRAY') {
	$cache = $request->[0];
	$request = shift;
    }
    my @args = @_;
# вызов внутреннего метода непосредственного выполнения запроса
    my $res = $self->_request($request, @args);
# не кешировать запрос, если указано
    if ((defined $cache) && ($cache == 0)) {
	$self->{'requests'}->{$request}->finish();
	delete $self->{'requests'}->{$request};
    }
    return $res;

}

# метод для выполнения запроса к БД, предполагающих получение какой либо выборки (select)
# аргументы: первый (опционально) - флаг кеширования запроса в виде массива из одного элемента.
# (по умолчанию запрос кешируется)
# затем - запрос и массив подстановочных данных (на место плейсхолдеров)
# возвращает массив хешей, каждый из которых содержит в себе все данные одной строки выборки
sub sql_select {
    my $self = shift;
    my $request = shift;
# определение необходимости кеширования запроса
    my $cache = 1;
    if (ref($request) eq 'ARRAY') {
	$cache = $request->[0];
	$request = shift;
    }
    my @args = @_;
    my $res = [];
# выполнение запроса к БД
    if ($self->_request($request, @args)) {
# формирование массива результата
	while (my $temp = $self->{'requests'}->{$request}->fetchrow_hashref()) {
	    push (@$res, $temp);
	}
    }
# не кешировать запрос, если указано
    if ((defined $cache) && ($cache == 0)) {
	$self->{'requests'}->{$request}->finish();
	delete $self->{'requests'}->{$request};
    }
    return $res;
}

# внутренний метод для выполнения произвольного запроса к БД
# аргументы: запрос и массив подстановочных данных
# (на место плейсхолдеров)
# возвращает 1 в случае успешного запроса, 0 - в случае ошибки
sub _request {
    my $self = shift;
    my $request = shift;
    my @args = @_;

# проверка на существование подключения к БД
    return 0 unless defined ${$self->{'database'}};

# подготовка запроса
    $self->{'requests'}->{$request} = ${$self->{'database'}}->prepare($request)
				unless (defined $self->{'requests'}->{$request});

# выполнение запроса
    return $self->{'requests'}->{$request}->execute(@args) ? 1 : 0;

}

# метод-деструктор
# вызывается при уничтожении объекта
# корректно (используя соответствующий метод объекта) закрывает соединение с базой данных
sub DESTROY {
    my $self = shift;

# проверить существование соединения
    if (defined $self->{'database'}) {
# проверить существование кешированных запросов
	if (defined $self->{'requests'}) {
# все кешированные запросы закрываются
	    foreach (keys %{$self->{'requests'}}) {
		$self->{'requests'}->{$_}->finish();
	    }
	    delete $self->{'requests'};
	}
#	$self->{'database'}->disconnect();
	delete $self->{'database'};
	return 1;
    }
    else {
# соединение не существует
	return 0;
    }

}

1;
