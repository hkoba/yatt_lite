package YATT::Lite::Util::AsBase;
use strict;
use warnings FATAL => qw/all/;
use Carp;

require Exporter;
our @EXPORT = qw/import _import_as_base/;
our @EXPORT_OK = @EXPORT;

use YATT::Lite::Util qw/ckeval globref/;

require YATT::Lite::MFields;

sub import {
  parse_args(\@_, scalar caller);
  goto &Exporter::import;
}

#
# Scan -zzz flag and call $pack->_import_zzz($callpack)
#
sub parse_args ($$) {
  my ($arglist, $callpack) = @_;
  return unless $arglist and @$arglist and defined (my $target = $arglist->[0]);
  $callpack //= caller(1);

  while ($arglist and @$arglist >= 2
	 and defined $arglist->[1]
	 and $arglist->[1] =~ /^-(.+)/) {
    splice @$arglist, 1, 1;
    my $sub = $target->can('_import_' . $1)
      or carp "Unknown flag $1 for target class $target";
    $sub->($target, $callpack);
  }
}

# Called like: use Foo -as_base;

sub _import_as_base {
  my ($myPack, $callpack) = @_;

  {
    my $sym = globref($callpack, 'ISA');
    my $isa;
    unless ($isa = *{$sym}{ARRAY}) {
      *$sym = $isa = [];
    }
    unless (grep {$_ eq $myPack} @$isa) {
      push @$isa, $myPack;
    }
  }

  # Fill $callpack's %FIELDS, by current ISA.
  YATT::Lite::MFields->define_fields($callpack);

  my $sym = globref($callpack, 'MY');
  *$sym = sub () { $callpack } unless *{$sym}{CODE};
}

1;
