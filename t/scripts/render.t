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
use YATT::Lite::Util qw(dict_sort rootname read_file);
my $func = rootname(basename($0));
my $script = "$libdir/YATT/scripts/yatt.$func";

unless (-x $script) {
  plan skip_all => "Can't find yatt.$func: $script";
}

$ENV{LANG} = "C"; # To avoid Wide char in $!
chdir($FindBin::Bin) or die "Can't chdir: $!"; # To avoid reading outer app.psgi.

my $tstdir = "$FindBin::Bin/$func.ytmpl";

my @tests;
foreach my $fn (dict_sort glob("$tstdir/[1-9]*/index.yatt")) {
  if (-r (my $minver_fn = dirname($fn) . "/perl_minver")) {
    chomp(my $minver = read_file($minver_fn));
    if ($] < $minver) {
      # XXX: should push explicit skip
      next;
    }
  }
  foreach my $ext (qw(html err)) {
    if (-r (my $res = rootname($fn) . ".$ext")) {
      my $title = substr($fn, length($tstdir)+1);
      push @tests, [$ext, $fn, $res, $title];
      last;
    }
  }
}

if (@tests) {
  plan tests => scalar @tests;
} else {
  plan skip_all => "Too old perl";
}

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

# use IPC::Open3; use Symbol qw/gensym/;

sub test_err {
  my ($src, $res, $title) = @_;
  my $args = '';
  if (-r (my $fn = "$src.in")) {
    $args .= " " . read_file($fn);
  }
  my $out = qx($^X -I$libdir $script $src$args 2>&1);
  if (defined $out and $?) {
    eq_or_diff_subst($out, read_file($res), $title // $src);
  } else {
    fail $src;
  }
}

sub eq_or_diff_subst {
  my ($got, $expect_pat, $title) = @_;
  my (@patlist, %dup_pat);
  my $fill = "___";
  $expect_pat =~ s{\[\[(.*?)\]\]}{
    do {
      unless ($dup_pat{$1}++) {
	push @patlist, $1;
      }
      $fill;
    }
  }eg;

  unless (defined $got) {
    fail $title;
    diag "got undef";
    return;
  }

  if (@patlist) {
    my $subst = join "|", @patlist;
    $got =~ s/$subst/$fill/g;
  }

  eq_or_diff($got, $expect_pat, $title);
}
