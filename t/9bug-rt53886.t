#!/usr/bin/env perl
use strict;
use warnings;
use Test::Most;

use Config::JFDI;

warning_is { Config::JFDI->new( local_suffix => 'local' )->source } undef;
warning_like { Config::JFDI->new( file => 'xyzzy',local_suffix => 'local' )->source } qr/will be ignored if 'file' is given, use 'path' instead/;

done_testing;
