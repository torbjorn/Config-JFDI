use strict;
use warnings;

use Test::More;

plan skip_all => "Config::General is required for this test" unless eval "require Config::General;";
plan qw/no_plan/;

use Config::JFDI;

$ENV{CONFIG_LOADER_SOURCE_FILE_MANY_FILES_ALLOW} = 1;

my $config = Config::JFDI->new(qw{ name xyzzy path t/assets/order });

ok($config->get);
is($config->get->{'last'}, 'local_pl');
is($config->get->{$_}, 1) for qw/pl perl local_pl local_perl cnf local_cnf conf local_conf/;
