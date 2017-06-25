# -*- perl -*-
use strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use YATT::Lite::WebMVC0::SiteApp -as_base;

use YATT::Lite::WebMVC0::Partial::Session2;
{
  my $site = MY->load_factory_for_psgi($0, environment => $ENV{PLACK_ENV} // 'development');

  $site->to_app;
}
