package
  MyBuilder;
use strict;
use warnings FATAL => qw(all);

use base qw(Module::Build);

sub rscan_and_subst {
  my ($self, $rscanSpec, $substSpec) = @_;
  my ($from, $to) = @$substSpec;
  my %hash = (
	      map {my ($std) = $_; $std =~ s{$from}{$to}; $_ => $std}
	      @{Module::Build->rscan_dir(@$rscanSpec)}
	     );
  \%hash;
}

1;
