#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}
use base qw(File::Spec);
use File::Basename;

use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
my $libdir;
BEGIN {
  unless (grep {$_ eq 'YATT'} MY->splitdir($FindBin::Bin)) {
    die "Can't find YATT in runtime path: $FindBin::Bin\n";
  }
  $libdir = dirname(dirname(dirname(untaint_any($FindBin::Bin))));
}
use lib $libdir;
#----------------------------------------

use Test::More;

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
  my $args = '';
  if (-r (my $fn = "$src.in")) {
    $args .= " " . read_file($fn);
  }
  if (not defined(my $out = qx($^X -I$libdir $script $src$args)) or $?) {
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
