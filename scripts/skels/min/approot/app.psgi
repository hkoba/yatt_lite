# -*- perl -*-
sub MY () {__PACKAGE__}; # omissible
use FindBin;
use lib "$FindBin::Bin/lib";
use YATT::Lite::WebMVC0::SiteApp -as_base;
# use YATT::Lite -Entity;
{
  my $site = MY->new(doc_root => "$FindBin::Bin/html");
  $site->to_app;
}
