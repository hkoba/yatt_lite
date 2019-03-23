#!/usr/bin/env perl
package YATT::Lite::LanguageServer::Spec2Types;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base;

use YATT::Lite::LanguageServer::SpecParser qw/Interface Decl/;

sub make_typespec_from {
  (my MY $self, my ($typeDict, @names)) = @_;
  map {
    $self->interface2typespec($typeDict->{$_}, $typeDict);
  } @names;
}

sub interface2typespec {
  (my MY $self, my Interface $if, my $typeDict) = @_;
  # Type is not used currently.
  my @spec = [fields => map {
    my Decl $slotDecl = $_;
    if (ref $slotDecl eq 'ARRAY') {
      my ($name, @typeunion) = @$slotDecl;
      $name;
    } elsif ($slotDecl->{kind}) {
      Carp::croak "Not implemented for interface body: $slotDecl->{kind}";
    } elsif ($slotDecl->{deprecated}) {
      ();
    } else {
      my $name = $slotDecl->{body}[0];
      $name =~ s/\?\z//;
      if ($slotDecl->{comment}) {
        [$name => doc => $slotDecl->{comment}];
      } else {
        $name
      }
    }
  } @{$if->{body}}];
  if ($if->{extends}) {
    my ($superName, $superSpec)
      = $self->interface2typespec($typeDict->{$if->{extends}}, $typeDict);
    ($superName, [@$superSpec, [subtypes => $if->{name}, \@spec]]);
  } else {
    ($if->{name}, \@spec);
  }
}

sub gather_interfaces {
  (my MY $self, my @decls) = @_;
  my %dict;
  foreach my Interface $if (@decls) {
    next unless ref $if eq 'HASH';
    next unless $if->{kind} eq 'interface';
    $dict{$if->{name}} = $if;
  }
  \%dict;
}

MY->run(\@ARGV) unless caller;

1;
