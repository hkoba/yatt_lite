#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings FATAL => qw(all);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
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
