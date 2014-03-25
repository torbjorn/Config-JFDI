package Config::JFDI::Source::Loader;

use Any::Moose;

use Config::Any;
use Carp;
use List::MoreUtils qw/ any /;




sub BUILD {
    my $self = shift;
    my $given = shift;

    if (defined( my $name = $self->name )) {
        if (ref $name eq "SCALAR") {
            $name = $$name;
        }
        else {
            $name =~ s/::/_/g;
            $name = lc $name;
        }
        $self->{name} = $name;
    }

    if (defined $self->env_lookup) {
        $self->{env_lookup} = [ $self->env_lookup ] unless ref $self->env_lookup eq "ARRAY";
    }

}


1;
