#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use Test::More;

sub MY () {__PACKAGE__}
use base qw(File::Spec);

use FindBin;
my $libdir;
BEGIN {
  ($libdir) = grep {-e "$_/YATT/Lite"} "$FindBin::Bin/../lib", @INC;
  BAIL_OUT("Can't find YATT/Lite directory!") unless defined $libdir;
}
use lib $libdir;

use File::Basename;

use YATT::Lite::Test::TestUtil;
use YATT::Lite::Util qw(dict_sort rootname);
my $func = rootname(basename($0));
my $script = "$libdir/YATT/scripts/yatt.$func";

unless (-x $script) {
  plan skip_all => "Can't find yatt.$func: $script";
}

my $tstdir = "$FindBin::Bin/ytmpl";

my @tests;
foreach my $fn (dict_sort glob("$tstdir/[1-9]*/index.yatt")) {
  foreach my $ext (qw(html err)) {
    if (-r (my $res = rootname($fn) . ".$ext")) {
      my $title = substr($fn, length($tstdir)+1);
      push @tests, [$ext, $fn, $res, $title];
      last;
    }
  }
}

plan tests => scalar @tests;

foreach my $test (@tests) {
  my ($how, @args) = @$test;
  __PACKAGE__->can("test_$how")->(@args);
}

sub test_html {
  my ($src, $res, $title) = @_;
  if (not defined(my $out = qx($^X -I$libdir $script $src)) or $?) {
    fail $src;
  } else {
    eq_or_diff $out, read_file($res), $title // $src;
  }
}

sub read_file {
  my $fn = shift;
  open my $fh, '<', $fn or die "Can't open '$fn': $!";
  local $/;
  <$fh>;
}
