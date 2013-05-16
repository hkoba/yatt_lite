# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use FindBin; my $libdir; BEGIN { local @_ = "$FindBin::Bin/.."; ($libdir) = do "$FindBin::Bin/../t_lib.pl" }

my $app_root = ::dirname(::untaint_any(__FILE__));

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
