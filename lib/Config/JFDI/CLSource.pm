package Config::JFDI::CLSource;

use lib '../Config-Loader/lib';

use Moo;
extends "Config::Loader::Source::Profile::Default";

with "Config::Loader::SourceRole::FileHelper";

1;
