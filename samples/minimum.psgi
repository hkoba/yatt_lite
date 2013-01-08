# -*- perl -*-
sub MY () {__PACKAGE__}; # omissible
use FindBin;
use YATT::Lite::WebMVC0::SiteApp -as_base;
{
  my $site = MY->new(doc_root => "$FindBin::Bin/html");
  $site->to_app;
}
