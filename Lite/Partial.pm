package YATT::Lite::Partial;
use strict;
use warnings FATAL => qw/all/;
use mro 'c3';

sub Meta () {'YATT::Lite::Partial::Meta'}

sub import {
  my $pack = shift;
  my $callpack = caller;
  $pack->Meta->define_partial_class($callpack, @_);
}

package
  YATT::Lite::Partial::Meta; sub Meta () {__PACKAGE__}
use parent qw/YATT::Lite::MFields/;
use YATT::Lite::Util qw/globref lexpand/;
use Carp;

sub define_partial_class {
  my ($pack, $callpack) = splice @_, 0, 2;
  mro::set_mro($callpack => 'c3');
  my %opts = @_;
  my Meta $meta = $pack->get_meta($callpack);
  if (my (@class) = map {lexpand(delete $opts{$_})} qw/parent parents/) {
    add_isa_to($callpack, @class);
  }
  if (my @fields = lexpand(delete $opts{fields})) {
    $pack->define_fields($callpack, @fields);
  }
  if (%opts) {
    croak "Unknown options for Partial definition: "
      .join(", ", sort keys %opts);
  }
  # my Meta $meta = $pack->define_fields($callpack, @_);
  *{globref($callpack, 'import')} = sub {
    shift;
    my $fullclass = caller;
    $meta->export_partial_class_to($fullclass, @_);
  };
}

sub add_isa_to {
  (my $fullclass, my @class) = @_;
  # print "# add $fullclass isa @class\n";
  my $isa; {
    my $sym = globref($fullclass, 'ISA');
    unless ($isa = *{$sym}{ARRAY}) {
      *$sym = $isa = [];
    }
  };
  push @$isa, @class;
}

sub export_partial_class_to {
  (my Meta $partial, my $fullclass) = @_;

  # print "# partial $partial->{cf_package} is imported to $fullclass\n";

  add_isa_to($fullclass, $partial->{cf_package});

  my Meta $full = Meta->get_meta($fullclass);

  $full->import_fields_from($partial);
}

1;
