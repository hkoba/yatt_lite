package YATT::Lite::LRXML::FormatEntpath;
use strict;
use warnings qw(FATAL all NONFATAL misc);

use YATT::Lite::Constants;
use YATT::Lite::LRXML::ParseEntpath;
*close_ch = *YATT::Lite::LRXML::ParseEntpath::close_ch;
*close_ch = *YATT::Lite::LRXML::ParseEntpath::close_ch;

sub inverse_hash {
  my ($fromHash, $toHash) = @_;
  $toHash //= {};
  $toHash->{$fromHash->{$_}} = $_ for keys %$fromHash;
}

our (%name2sym);
BEGIN {
  inverse_hash(\%name2sym, \%YATT::Lite::LRXML::ParseEntpath::open_head);
  inverse_hash(\%name2sym, \%YATT::Lite::LRXML::ParseEntpath::open_rest);
}

sub ME () {__PACKAGE__}
sub format_entpath {
  my ($node) = @_;
  my ($type, @rest) = @$node;
  my $sub = ME->can("format__$type")
    or Carp::croak "Unknown entpath type: $type";
  $sub->(@rest);
}

sub format__call {
  my ($name, @args) = @_;
  sprintf(":%s(%s)", $name
	    , join(",", map {format_entpath(lxnest($_))} @args));
}

sub format__var {
  my ($name) = @_;
  ":$name";
}

1;
