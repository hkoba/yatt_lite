#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use Test::More;

sub MY () {__PACKAGE__}
use base qw(File::Spec);
use File::Basename;
use FindBin;
sub updir {my ($n, $fn) = @_; $fn = dirname($fn) while $n-- > 0; $fn}
my $libdir;
use lib $libdir = do {
  if (-l __FILE__) {
    # If $script is symlink, symlink-resolved path is used as $libdir
    updir(2, ($FindBin::RealBin, $FindBin::RealBin)[0]);
  } else {
    # Otherwise, just use updir 3 of runyatt.lib/YATT/scripts/$script
    updir(3, MY->rel2abs(__FILE__))
  }
};
# print STDERR join("\n", __FILE__, $libdir), "\n";

use YATT::Lite::TestUtil;
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
  if (not defined(my $out = qx($script $src)) or $?) {
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
