#!/usr/bin/env perl
use strict;
use warnings;
use Test::Most;

use Config::JFDI;

sub file_extension ($) { Config::JFDI::file_extension shift }

is( file_extension 'test.conf', 'conf' );
is( file_extension '...', undef );
is( file_extension '../.', undef );
is( file_extension '.../.', undef );
is( file_extension 't/assets/order/..', undef );
is( file_extension 't/assets/dir.cnf', undef );

done_testing;
