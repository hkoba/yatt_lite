#!/usr/bin/env perl
package YATT::Lite::LanguageServer::Spec2Types;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base;

use YATT::Lite::LanguageServer::SpecParser qw/Interface Decl/;

sub interface2typespec {
  (my MY $self, my Interface $if) = @_;
  if ($if->{extends}) {
    ...
  } else {
    [$if->{name} => [fields => map {
      my Decl $slotDecl = $_;
      if ($slotDecl->{kind}) {
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
    } @{$if->{body}}]]
  }
}

MY->run(\@ARGV) unless caller;

1;
