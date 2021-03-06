package Config::JFDI;
# ABSTRACT: Just * Do it: A Catalyst::Plugin::ConfigLoader-style layer over Config::Any

use warnings;
use strict;


use Moo;
use namespace::clean;

use Config::JFDI::Carp;
use Config::JFDI::CLSource;
use Config::Loader ();

use Path::Class;
use Hash::Merge::Simple;
use Sub::Install;
use Data::Visitor::Callback;
use Clone qw//;

has package => qw/ is ro  /;

has source => (
    is => 'lazy',
    clearer => 'clear_source',
    predicate => 'has_source',
    handles => [qw/default load_config/],
    builder => sub { $_[0]->source_builder->() },
);
has source_builder => (
    is => 'ro'
);

has load_once => qw/ is ro required 1 /, default => 1;

# has substitution => qw/ reader _substitution is ro  /,
#     builder => sub {
#         return {};
#     };

has path_to => qw/ reader _path_to is lazy  /,
    builder => sub {
        print "# first is ", $_[0]->source, "\n";
        # print "# config is ", $_[0]->config, "\n";
        ($_[0]->config || {} )->{home}  ||
        !$_[0]->source->path_is_file && $_[0]->source->path ||
        "."
    };

has _config => qw/ is rw  /;


sub BUILD {
    my $self = shift;
    my $args = shift;

    my $source_builder = sub {

        my @params = qw/name path file path_is_file local_suffix config_local_suffix
                        no_env no_local env_lookup default/;
        my %source_args = map { $_, $args->{$_} } grep exists $args->{$_}, @params;

        my $cl = Config::Loader->new_source( '+Config::JFDI::CLSource', %source_args);
        my $s = Config::Loader->new_source(
            'Filter::Substitution',
            source => $cl,
            substitutions => {

                ## defaults:
                HOME => sub { $self->path_to( '' ); },
                path_to => sub { $self->path_to( @_ ); },
                literal => sub { return $_[ 1 ]; },

            }
        );

        return $cl;

        ## THIS WON'T WORK - MOVE ALL OF CLSOURCE UP HERE INSTEAD

    };

    ## FIX THIS - ITS RO AFTER ALL
    $self->{source_builder} = $source_builder;

    $self->{package} = $args->{name} if defined $args->{name} &&
        !defined $self->{package} && ! ref $args->{name};

    # ($self->{substitution}) = grep $_, @{$args}{qw/substitute substitutes substitutions substitution/};

    if (my $package = $args->{install_accessor}) {
        $package = $self->package if $package eq 1;
        Sub::Install::install_sub({
            code => sub {
                return $self->config;
            },
            into => $package,
            as => "config"
        });

    }

}

sub open {
    unless ( ref $_[0] ) {
        my $class = shift;
        return $class->new( @_ == 1 ? (file => $_[0]) : @_ )->open;
    }
    my $self = shift;
    carp "You called ->open on an instantiated object with arguments" if @_;
    return unless $self->found;
    return wantarray ? ($self->config, $self) : $self->config;
}

sub get {
    my $self = shift;
    return $self->config;
    # TODO Expand to allow dotted key access (?)
}

sub config {
    my $self = shift;
    return $self->_config if $self->has_source;
    return $self->load;
}

sub load {
    my $self = shift;
    return $self->_config if $self->has_source && $self->load_once;
    $self->_config( $self->load_config );

    # {
    #     my $visitor = Data::Visitor::Callback->new(
    #         plain_value => sub {
    #             return unless defined $_;
    #             $self->substitute($_);
    #         }
    #     );
    #     $visitor->visit( $self->config );

    # }

    return $self->config;
}

sub clone {
    my $self = shift;
    return Clone::clone($self->config);
}

sub reload {
    my $self = shift;
    $self->clear_source;
    return $self->load;
}

# sub substitute {
#     my $self = shift;

#     my $substitution = $self->_substitution;
#     $substitution->{ HOME }    ||= sub { shift->path_to( '' ); };
#     $substitution->{ path_to } ||= sub { shift->path_to( @_ ); };
#     $substitution->{ literal } ||= sub { return $_[ 1 ]; };
#     my $matcher = join( '|', keys %$substitution );

#     for ( @_ ) {
#         s{__($matcher)(?:\((.+?)\))?__}{ $substitution->{ $1 }->( $self, $2 ? split( /,/, $2 ) : () ) }eg;
#     }
# }

sub path_to {
    my $self = shift;
    my @path = @_;

    my $path_to = $self->_path_to;

    my $path = Path::Class::Dir->new( $path_to, @path );

    if ( -d $path ) {
        return $path;
    }
    else {
        return Path::Class::File->new( $path_to, @path );
    }
}


# sub _env (@) {
#     my $key = uc join "_", @_;
#     $key =~ s/::/_/g;
#     $key =~ s/\W/_/g;
#     return $ENV{$key};
# }
sub file_extension ($) {
    my $path = shift;
    return if -d $path;
    my ($extension) = $path =~ m{\.([^/\.]{1,4})$};
    return $extension;
}
# sub _get_path {
#     my $self = shift;

#     my $name = $self->name;
#     my $path;
# #    $path = _env($name, 'CONFIG') if $name && ! $self->no_env;
#     $path = $self->_env_lookup('CONFIG') unless $self->no_env;
#     $path ||= $self->path;

#     my $extension = file_extension $path;

#     if (-d $path) {
#         $path =~ s{[\/\\]$}{}; # Remove any trailing slash, e.g. apple/ or apple\ => apple
#         $path .= "/$name"; # Look for a file in path with $self->name, e.g. apple => apple/name
#     }

#     return ($path, $extension);
# }
# sub _env_lookup {
#     my $self = shift;
#     my @suffix = @_;

#     my $name = $self->name;
#     my $env_lookup = $self->env_lookup;
#     my @lookup;
#     push @lookup, $name if $name;
#     push @lookup, @$env_lookup;

#     for my $prefix (@lookup) {
#         my $value = _env($prefix, @suffix);
#         return $value if defined $value;
#     }

#     return;
# }
# sub _get_local_suffix {
#     my $self = shift;

#     my $name = $self->name;
#     my $suffix;
#     $suffix = $self->_env_lookup('CONFIG_LOCAL_SUFFIX') unless $self->no_env;
# #    $suffix = _env($self->name, 'CONFIG_LOCAL_SUFFIX') if $name && ! $self->no_env;
#     $suffix ||= $self->local_suffix;

#     return $suffix;
# }
# sub _get_extensions {
#     return @{ Config::Any->extensions }
# }
# sub _find_files { # Doesn't really find files...hurm...
#     my $self = shift;

#     if ($self->path_is_file) {
#         my $path;
#         $path = $self->_env_lookup('CONFIG') unless $self->no_env;
#         $path ||= $self->path;
#         return ($path);
#     }
#     else {
#         my ($path, $extension) = $self->_get_path;
#         my $local_suffix = $self->_get_local_suffix;
#         my @extensions = $self->_get_extensions;
#         my $no_local = $self->no_local;

#         my @files;
#         if ($extension) {
#             croak "Can't handle file extension $extension" unless grep { $_ eq $extension } @extensions;
#             push @files, $path;
#             unless ($no_local) {
#                 (my $local_path = $path) =~ s{\.$extension$}{_$local_suffix.$extension};
#                 push @files, $local_path;
#             }
#         }
#         else {
#             push @files, map { "$path.$_" } @extensions;
#             push @files, map { "${path}_${local_suffix}.$_" } @extensions unless $no_local;
#         }

#         my (@cfg, @local_cfg);
#         for (sort @files) {

#             if (m{$local_suffix\.}ms) {
#                 push @local_cfg, $_;
#             } else {
#                 push @cfg, $_;
#             }

#         }

#         my @final_files = $no_local ?
#             @cfg : (@cfg, @local_cfg);

#         @final_files = grep -r, @final_files;

#         return @final_files;

#     }
# }

## The rest
sub found {
    my $self = shift;
    die if @_;
    return unless $self->has_source;
    return ( map { @{$_->files_loaded} }
             grep { $_->can("files_loaded") }
             @{ $self->source->source_objects } );
}
around found => sub {
    my $inner = shift;
    my $self = shift;
    $self->load unless $self->has_source;
    return $inner->( $self, @_ );
};

1;

__END__

=head1 SYNPOSIS

    use Config::JFDI;

    my $config = Config::JFDI->new(name => "my_application", path => "path/to/my/application");
    my $config_hash = $config->get;

This will look for something like (depending on what Config::Any will find):

    path/to/my/application/my_application_local.{yml,yaml,cnf,conf,jsn,json,...} AND

    path/to/my/application/my_application.{yml,yaml,cnf,conf,jsn,json,...}

... and load the found configuration information appropiately, with _local taking precedence.

You can also specify a file directly:

    my $config = Config::JFDI->new(file => "/path/to/my/application/my_application.cnf");

To later reload your configuration, fresh from disk:

    $config->reload;

=head1 DESCRIPTION

Config::JFDI is an implementation of L<Catalyst::Plugin::ConfigLoader> that exists outside of L<Catalyst>.

Essentially, Config::JFDI will scan a directory for files matching a certain name. If such a file is found which also matches an extension
that Config::Any can read, then the configuration from that file will be loaded.

Config::JFDI will also look for special files that end with a "_local" suffix. Files with this special suffix will take
precedence over any other existing configuration file, if any. The precedence takes place by merging the local configuration with the
"standard" configuration via L<Hash::Merge::Simple>.

Finally, you can override/modify the path search from outside your application, by setting the <NAME>_CONFIG variable outside your application (where <NAME>
is the uppercase version of what you passed to Config::JFDI->new).

=head1 Config::Loader

We are currently kicking around ideas for a next-generation configuration loader. The goals are:

    * A universal platform for configuration slurping and post-processing
    * Use Config::Any to do configuration loading
    * A sane API so that developers can roll their own loader according to the needs of their application
    * A friendly interface so that users can have it just DWIM
    * Host/application/instance specific configuration via _local and %ENV

Find more information and contribute at:

Roadmap: L<http://sites.google.com/site/configloader/>

Mailing list: L<http://lists.scsys.co.uk/cgi-bin/mailman/listinfo/config-loader>

=head1 Behavior change of the 'file' parameter in 0.06

In previous versions, Config::JFDI would treat the file parameter as a path parameter, stripping off the extension (ignoring it) and globbing what remained against all the extensions that Config::Any could provide. That is, it would do this:

    Config::JFDI->new( file => 'xyzzy.cnf' );
    # Transform 'xyzzy.cnf' into 'xyzzy.pl', 'xyzzy.yaml', 'xyzzy_local.pl', ... (depending on what Config::Any could parse)

This is probably not what people intended. Config::JFDI will now squeak a warning if you pass 'file' through, but you can suppress the warning with 'no_06_warning' or 'quiet_deprecation'

    Config::JFDI->new( file => 'xyzzy.cnf', no_06_warning => 1 );
    Config::JFDI->new( file => 'xyzzy.cnf', quiet_deprecation => 1 ); # More general

If you *do* want the original behavior, simply pass in the file parameter as the path parameter instead:

    Config::JFDI->new( path => 'xyzzy.cnf' ); # Will work as before

=head1 METHODS

=head2 $config = Config::JFDI->new(...)

You can configure the $config object by passing the following to new:

    name                The name specifying the prefix of the configuration file to look for and
                        the ENV variable to read. This can be a package name. In any case,
                        :: will be substituted with _ in <name> and the result will be lowercased.

                        To prevent modification of <name>, pass it in as a scalar reference.

    path                The directory to search in

    file                Directly read the configuration from this file. Config::Any must recognize
                        the extension. Setting this will override path

    no_local            Disable lookup of a local configuration. The 'local_suffix' option will be ignored. Off by default

    local_suffix        The suffix to match when looking for a local configuration. "local" By default
                        ("config_local_suffix" will also work so as to be drop-in compatible with C::P::CL)

    no_env              Set this to 1 to disregard anything in the ENV. The 'env_lookup' option will be ignored. Off by default

    env_lookup          Additional ENV to check if $ENV{<NAME>...} is not found

    driver              A hash consisting of Config:: driver information. This is passed directly through
                        to Config::Any

    install_accessor    Set this to 1 to install a Catalyst-style accessor as <name>::config
                        You can also specify the package name directly by setting install_accessor to it
                        (e.g. install_accessor => "My::Application")

    substitute          A hash consisting of subroutines called during the substitution phase of configuration
                        preparation. ("substitutions" will also work so as to be drop-in compatible with C::P::CL)
                        A substitution subroutine has the following signature: ($config, [ $argument1, $argument2, ... ])

    path_to             The path to dir to use for the __path_to(...)__ substitution. If nothing is given, then the 'home'
                        config value will be used ($config->get->{home}). Failing that, the current directory will be used.

    default             A hash filled with default keys/values

Returns a new Config::JFDI object

=head2 $config_hash = Config::JFDI->open( ... )

As an alternative way to load a config, ->open will pass given arguments to ->new( ... ), then attempt to do ->load

Unlike ->get or ->load, if no configuration files are found, ->open will return undef (or the empty list)

This is so you can do something like:

    my $config_hash = Config::JFDI->open( "/path/to/application.cnf" ) or croak "Couldn't find config file!"

In scalar context, ->open will return the config hash, NOT the config object. If you want the config object, call ->open in list context:

    my ($config_hash, $config) = Config::JFDI->open( ... )

You can pass any arguments to ->open that you would to ->new

=head2 $config->get

=head2 $config->config

=head2 $config->load

Load a config as specified by ->new( ... ) and ENV and return a hash

These will only load the configuration once, so it's safe to call them multiple times without incurring any loading-time penalty

=head2 $config->found

Returns a list of files found

If the list is empty, then no files were loaded/read

=head2 $config->clone

Return a clone of the configuration hash using L<Clone>

This will load the configuration first, if it hasn't already

=head2 $config->reload

Reload the configuration, examining ENV and scanning the path anew

Returns a hash of the configuration

=head2 $config->substitute( <value>, <value>, ... )

For each given <value>, if <value> looks like a substitution specification, then run
the substitution macro on <value> and store the result.

There are three default substitutions (the same as L<Catalyst::Plugin::ConfigLoader>)

=over 4

=item * C<__HOME__> - replaced with C<$c-E<gt>path_to('')>

=item * C<__path_to(foo/bar)__> - replaced with C<$c-E<gt>path_to('foo/bar')>

=item * C<__literal(__FOO__)__> - leaves __FOO__ alone (allows you to use
C<__DATA__> as a config value, for example)

=back

The parameter list is split on comma (C<,>).

You can define your own substitutions by supplying the substitute option to ->new

=head1 SEE ALSO

L<Catalyst::Plugin::ConfigLoader>

L<Config::Any>

L<Catalyst>

L<Config::Merge>

L<Config::General>
