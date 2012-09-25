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
  $libdir = dirname(dirname(untaint_any($FindBin::Bin)));
}
use lib $libdir;
#----------------------------------------

use Test::More qw(no_plan);

{
  BEGIN {
    use_ok('YATT::Lite::Util', qw/incr_opt unique/);
  }

  my $list = [qw/foo bar/];
  is_deeply [incr_opt(depth => $list), $list]
    , [{depth => 1}, $list], "no hash";

  $list = [{}, qw/foo bar/];
  is_deeply [incr_opt(depth => $list), $list]
    , [{depth => 1}, $list], "has hash but no depth";

  $list = [{depth => 1}, qw/foo bar/];
  is_deeply [incr_opt(depth => $list), $list]
    , [{depth => 2}, $list], "depth is incremented";

  is_deeply [unique qw/foo bar foo/], [qw/foo bar/]
    , "(order preserving) unique";
}
