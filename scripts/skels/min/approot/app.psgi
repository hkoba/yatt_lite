# -*- perl -*-
sub MY () {__PACKAGE__}; # omissible
use FindBin;
use lib "$FindBin::Bin/lib";
use YATT::Lite::WebMVC0::SiteApp -as_base;
use YATT::Lite qw/Entity *CON/;
{
  my $site = MY->new(doc_root => "$FindBin::Bin/html");
  Entity param => sub { my ($this, $name) = @_; $CON->param($name) };
  return $site if MY->want_object;
  $site->to_app;
}
