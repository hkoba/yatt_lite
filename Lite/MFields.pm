package YATT::Lite::MFields; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw/all/;
use 5.009; # For real hash only. (not works for pseudo-hash)

use parent qw/YATT::Lite::Object/;

sub Decl () {'YATT::Lite::MFields::Decl'}
BEGIN {
  package YATT::Lite::MFields::Decl;
  use parent qw/YATT::Lite::Object/;
  our %FIELDS = map {$_ => 1}
    qw/cf_is cf_isa cf_required cf_name
       cf_package
       cf_default
       cf_doc cf_label
      /;
}

BEGIN {
  our %FIELDS = map {$_ => Decl->new(name => $_)}
    qw/fields cf_package known_parent/;
}

use YATT::Lite::Util qw/globref look_for_globref list_isa fields_hash/;
use Carp;

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

sub has_fields {
  my ($pack, $callpack) = @_;
  fields_hash($callpack);
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
      my $sym = look_for_globref($class, 'FIELDS')
	or next;
      $fields = *{$sym}{HASH}
	or next;
    }

    foreach my $name (keys %$fields) {
      my Decl $importing = $fields->{$name};
      unless (UNIVERSAL::isa($importing, $self->Decl)) {
	croak "Importing raw field $class.$name is prohibited!";
      }

      unless (my Decl $existing = $self->{fields}->{$name}) {
	$self->{fields}->{$name} = $importing;
      } elsif (not UNIVERSAL::isa($existing, $self->Decl)) {
	croak "Importing $class.$name onto raw field"
	  . " (defined in $self->{cf_package}) is prohibited";
      } elsif ($importing != $existing) {
	croak "Conflicting import $class.$name"
	  . " (defined in $importing->{cf_package}) "
	    . "onto $existing->{cf_package}";
      }
    }
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
      $self->Decl->new(name => $name, @atts, package => $self->{cf_package});
    } elsif (not defined $atts[0]
	     or not UNIVERSAL::isa($atts[0], $self->Decl)) {
      $self->Decl->new(name => $name, package => $self->{cf_package});
    } else {
      $atts[0];
    }
  };
}

sub add_isa_to {
  my ($pack, $target, @base) = @_;
  my $sym = globref($target, 'ISA');
  my $isa;
  unless ($isa = *{$sym}{ARRAY}) {
    *$sym = $isa = [];
  }

  foreach my $base (@base) {
    next if grep {$_ eq $base} @$isa;
#    if (my $err = do {local $@; eval {
      push @$isa, $base
#    }; $@}) {
#      if ($err =~ /^Inconsistent hierarchy during C3 merge of class/) {
#	print "[inserting $base to $target] $err";
#	next;
#      }
#    }
  }

  $pack;
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

