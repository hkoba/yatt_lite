package YATT::Lite::MFields; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw/all/;
use 5.009; # For real hash only. (not works for pseudo-hash)

require base;
require parent;

use base qw/YATT::Lite::Object/;
use fields qw/fields cf_package
	      known_parent
	     /; # XXX: Should not rely on fields.

use YATT::Lite::Util qw/globref list_isa/;
use Carp;

use YATT::Lite::Types
  ([Field => -fields => [qw/cf_is cf_isa cf_required cf_name
			    cf_default
			    cf_doc/]]);

sub import {
  my $pack = shift;
  my $callpack = caller;
  $pack->define_fields($callpack, @_);
}

sub configure_package {
  (my MY $self, my $pack) = @_;
  $self->{cf_package} = $pack;
  my $sym = globref($pack, 'FIELDS');
  *$sym = {} unless *{$sym}{HASH};
  $self->{fields} = *{$sym}{HASH};
}

{
  my %meta;
  # XXX: This might harm if we need to care about package removal.
  # $PACKAGE::FIELDS might be good alternative place.

  sub get_meta {
    my ($pack, $callpack) = @_;
    $meta{$callpack} //= $pack->new(package => $callpack);
  }
}

sub define_fields {
  my ($pack, $callpack) = splice @_, 0, 2;

  my MY $meta = $pack->get_meta($callpack);

  $meta->import_fields_from(list_isa($callpack));

  if (@_ == 1 and ref $_[0] eq 'CODE') {
    $_[0]->($meta);
  } else {
    foreach my $item (@_) {
      $meta->has(ref $item ? @$item : $item);
    }
  }

  $meta;
}

sub import_fields_from {
  (my MY $self) = shift;
  foreach my $item (@_) {
    my ($class, $fields);
    if (ref $item) {
      unless (UNIVERSAL::isa($item, MY)) {
	croak "Invalid item for MFields::Meta->import_fields_from: $item";
      }
      my MY $super = $item;
      $class = $super->{cf_package};
      next if $self->{known_parent}{$class}++;
      $fields = $super->{fields};
    } else {
      $class = $item;
      next if $self->{known_parent}{$class}++;
      my $sym = globref($class, 'FIELDS');
      $fields = *{$sym}{HASH}
	or next;
    }
    $self->has($_, $fields->{$_}) for keys %$fields;
  }
}

sub fields {
  (my MY $self) = @_;
  my $f = $self->{fields};
  wantarray ? map([$_ => $f->{$_}], keys %$f) : $f;
}

sub has {
  (my MY $self, my $name, my @atts) = @_;
  if (my $old = $self->{fields}->{$name}) {
    carp "Redefinition of field $self->{cf_package}.$name is prohibited!";
  }
  $self->{fields}->{$name} = do {
    if (@atts >= 2 || @atts == 0) {
      $self->Field->new(name => $name, @atts);
    } elsif (not defined $atts[0]
	     or not UNIVERSAL::isa($atts[0], $self->Field)) {
      $self->Field->new(name => $name);
    } else {
      $atts[0];
    }
  };
}

1;

__END__

=head1 NAME

YATT::Lite::Fields -- fields for multiple inheritance.

=head1 SYNOPSIS

  # Like fields.pm
  use YATT::Lite::MFields qw/foo bar baz/;

  # Or more descriptive (but these attributes are for documentation only)
  use YATT::Lite::MFields
    ([name => is => 'ro', doc => "Name of the user"]
    , [age => is => 'rw', doc => "Age of the user"]
    );

  # Or, more procedural way.
  use YATT::Lite::MFields sub {
    my ($meta) = @_;
    $meta->has(name => is => 'ro', doc => "Name of the user");
    $meta->has(age => is => 'rw', doc => "Age of the user");
  };

=head1 DESCRIPTION

This module manipulates caller's C<%FIELDS> hash at compile time so that
caller can detect field-name error at compile time.
Traditionally this is done by L<fields> module. But it explicitly prohibits
multiple inheritance.

Yes, avoiding care-less use of multiple inheritance is important.
But if used correctly, multi-inheritance is good tool
to make your program being modular.

