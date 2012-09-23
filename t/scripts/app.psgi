# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}
use base qw(File::Spec);
use File::Basename;

use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
my ($libdir, $app_root);
BEGIN {
  my $fn = __FILE__;
  unless (grep {$_ eq 'YATT'} MY->splitdir(MY->rel2abs($fn))) {
    die "Can't find YATT in runtime path: $fn\n";
  }
  $app_root = dirname(untaint_any($fn));
  $libdir = dirname(dirname(dirname($app_root)));
  # print STDERR "libdir=$libdir";
}
use lib $libdir;

use YATT::Lite::WebMVC0::SiteApp -as_base;

{
  my MY $dispatcher = do {
    my @args = (app_ns => 'MyApp'
                , app_root => $app_root
                , doc_root => $app_root);
    MY->new(@args);
  };

  return $dispatcher->to_app;
}
