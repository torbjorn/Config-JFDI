package Config::JFDI::CLSource;

use Moo;
use MooX::HandlesVia;
use namespace::clean;

use Sub::Quote 'quote_sub';
use File::Basename qw/fileparse/;
use File::Spec::Functions qw/catfile/;
use Config::JFDI::Carp;

extends "Config::Loader::Source::Merged";

has name => qw/ is ro required 0 /;

has path_is_file => qw/ is ro default 0 /;
has path => qw/ is ro default . /;
has no_env => qw/ is ro /, default => 0;
has no_local => qw/ is ro /, default => 0;
has local_suffix => qw/ is ro required 1 default local /;

has env_lookup => (
   is => 'ro',
   ## puts it in an array ref if receives a scalar
   coerce => sub { ref $_[0] eq "ARRAY" && $_[0] || [$_[0]] },
   handles_via => "Array",
   handles => { "env_lookups" => "elements" },
   default => quote_sub q{ [] },
);
has _found => qw/ is rw /;
has driver => qw/ is ro lazy_build 1 /,
    builder => sub { {} };
has default => (
   is => 'ro',
   default => sub { {} },
);
has '+sources' => (
    lazy => 1,
    builder => \&_build_sources,
);
has env_source => (
    is => 'lazy',
    builder => sub {
        my $self = shift;

        return {} if $self->source_args->{no_env};

        ## arrayify env_lookup
        my @env_search = ref $self->source_args->{env_lookup} eq "ARRAY"
            && $self->source_args->{env_lookup}
                || [$self->source_args->{env_lookup}];

        my ($prefix) = grep defined, $self->name,
            @env_search;

        $prefix = uc $prefix;

        ## fetch path and suffix and set up a hashref with those
        my $c = Config::Loader->new_source( 'ENV', {
            env_prefix => $prefix,
            env_search => [qw/config config_local_suffix/],
        })->load_config;
# use Devel::Dwarn; Dwarn $c;
        my ($env_path,$env_suffix) = @{$c}{ qw/config config_local_suffix/ };

        return {
            path => $env_path,
            suffix => $env_suffix,
        };

    }
);
has source_args => (
    is => "ro", default => sub {{}}
);

has file => qw/is ro/;

sub substitute {
    my $self = shift;

    my $substitution = $self->_substitution;
    $substitution->{ HOME }    ||= sub { shift->path_to( '' ); };
    $substitution->{ path_to } ||= sub { shift->path_to( @_ ); };
    $substitution->{ literal } ||= sub { return $_[ 1 ]; };
    my $matcher = join( '|', keys %$substitution );

    for ( @_ ) {
        s{__($matcher)(?:\((.+?)\))?__}{ $substitution->{ $1 }->( $self, $2 ? split( /,/, $2 ) : () ) }eg;
    }
}

sub _env_lookup {
    my $self = shift;
    my @suffix = @_;

    my $name = $self->name;
    my $env_lookup = $self->env_lookup;
    my @lookup;
    push @lookup, $name if $name;
    push @lookup, @$env_lookup;

    for my $prefix (@lookup) {
        my $value = _env($prefix, @suffix);
        return $value if defined $value;
    }

    return;
}
sub _env (@) {
    my $key = uc join "_", @_;
    $key =~ s/::/_/g;
    $key =~ s/\W/_/g;
    return $ENV{$key};
}
sub _local_suffixed_filepath {

    my ($file,$local_suffix) = (shift,shift);

    die "local_suffix must be provided" unless defined $local_suffix;

    ## This assumes $file is a file or a stem. Cases where it
    ## is a directory needs to be explored later
    my( $name, $dirs, $suffix ) = fileparse( $file, qr/\.[^.]*/ );

    my $new_with_local = $name . "_" . $local_suffix;

    my $new_local_file = catfile( $dirs, $new_with_local );

    $new_local_file .= $suffix ? $suffix : "";

    return $new_local_file;


}
sub _get_local_suffix {
    my $self = shift;

    my $name = $self->name;
    my $suffix;
    $suffix = $self->_env_lookup('CONFIG_LOCAL_SUFFIX') unless $self->no_env;
#    $suffix = _env($self->name, 'CONFIG_LOCAL_SUFFIX') if $name && ! $self->no_env;
    $suffix ||= $self->local_suffix;

    return $suffix;
}

sub _build_sources {

    my $self = shift;

    my $path = $self->env_source->{path} || $self->path;
    my $path_is_file = $self->path_is_file;
    my $no_local = $self->source_args->{no_local};

    if ($self->source_args->{file}) {

        $path_is_file = 1;
        $path = $self->source_args->{file};
        $no_local = 1;

    }

    if (-d $path) {
        $path = catfile( $path, $self->name );
    }

    return [[ 'FileWithLocal' => {
        file => $path,
        no_local => $no_local,
        exists $self->source_args->{local_suffix} ?
            (local_suffix => $self->source_args->{local_suffix}) : (),
    }]];

}

around BUILDARGS => sub {

    my ($orig,$self) = (shift,shift);

    my $args = $orig->($self,@_);

    if ( delete $args->{sources} ) {
        carp "Providing sources through constructor is not supported. Any values passed will be discarded.";
    }

    if ($args->{file}) {

        $args->{path_is_file} = 1;
        $args->{path} = $args->{file};

        if ( exists $args->{local_suffix} ) {
            carp "Warning, 'local_suffix' will be ignored if 'file' is given, use 'path' instead"
        }

    }

    if ( defined( my $name = $args->{name} )) {
        if (ref $name eq "SCALAR") {
            $name = $$name;
        } else {
            $name =~ s/::/_/g;
            $name = lc $name;
        }
        $args->{name} = $name;
    }

    $args->{local_suffix} = $args->{config_local_suffix}
        if $args->{config_local_suffix} and not exists $args->{local_suffix};


    my @params = qw/name local_suffix no_local no_env env_lookup file/;
    my %source_args = map { $_, $args->{$_} } grep exists $args->{$_}, @params;
    $args->{source_args} = \%source_args;

    return $args;

};

1;
