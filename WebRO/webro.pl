#!/usr/bin/perl -wT
# WebRO - Web interface for RO (Repository Observer) - Core script
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
use lib qw(.);

use CGI::Fast;
use Template;

use WebRO::DB;

use constant NOT_FOUND => 404;
use constant SERVER_ERROR => 500;
use constant OK => 200;

# известные действия
my $actions = { 'packages' => 'WebRO::Actions::Packages',
		'package' => 'WebRO::Actions::Package',
		'nodes' => 'WebRO::Actions::Nodes',
		'node' => 'WebRO::Actions::Node',
		'export_node' => 'WebRO::Actions::Export::Node'
};

# конфигурация (лежит в файле './config')
my $config = do('./config');

my $db = WebRO::DB->new($config->{'database'});

# подготовка объекта-обработчика шаблонов
my $output = Template->new( {	ABSOLUTE	 	=> 1,
				RELATIVE	 	=> 1,
				INTERPOLATE	 	=> 0,
				POST_CHOMP		=> 1,
				COMPILE_EXT	 	=> '.tt2',
				COMPILE_DIR	 	=> $config->{'cache'},
				INCLUDE_PATH		=> './templates',
				EVAL_PERL		=> 1
} );

# основной рабочий цикл
while(my $request = new CGI::Fast) {

# определение запрошенного url
    my $url = $request->url(-relative => 1, -path_info => 1);

# действие по-умолчанию - при запросе пустового $url
    $url ||= defined $config->{'default_action'} ? $config->{'default_action'} : 'nodes';

    if (defined $actions->{$url}) {

	eval "require $actions->{$url};";
	if ($@) {
	    print $request->header({'status' => SERVER_ERROR, 'type' => 'text/plain'});
	    print "500 Internal Server Error\nCaused by work module";
	}
	else {
	    *func = $actions->{$url} . '::action';
	    my $data = func(\$db, \$request, $config);
# общие для всех данные, использующиеся в шаблонах
	    $data->{'uri'} = $url;
	    $data->{'static'} = $config->{'static'};
	    my $res;
	    if ($output->process($url . '.template', $data, \$res)) {
		print $request->header($data->{'_header'} || {'status' => OK, 'type' => 'text/html; charset=utf-8'});
		print $res;
	    }
	    else {
		print $request->header({'status' => SERVER_ERROR, 'type' => 'text/plain'});
	        print "500 Internal Server Error\nCaused by output object";
	    }
	}
    }
    else {
	print $request->header({'status' => NOT_FOUND, 'type' => 'text/plain'});
	print '404 File Not Found';
    }
}
