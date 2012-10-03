# -*- perl -*-
use strict;
use warnings FATAL => qw(all);

use File::Spec;
use File::Basename ();
use Cwd ();
my ($app_root, @libdir);
BEGIN {
  if (-r __FILE__) {
    # detect where app.psgi is placed.
    $app_root = File::Basename::dirname(File::Spec->rel2abs(__FILE__));
  } else {
    # older uwsgi do not set __FILE__ correctly, so use cwd instead.
    $app_root = Cwd::cwd();
  }
  if (-d (my $dn = "$app_root/lib")) {
    push @libdir, $dn
  } elsif (my ($found) = $app_root =~ m{^(.*?/)YATT/}) {
    push @libdir, $found;
  }
  if (-d (my $dn = "$app_root/extlib")) {
    push @libdir, $dn;
  }
}
use lib @libdir;

use YATT::Lite::WebMVC0::SiteApp;

my $dispatcher = YATT::Lite::WebMVC0::SiteApp->new
  (app_ns => 'MyApp'
   , app_root => $app_root
   , doc_root => "$app_root/html"
   , (-d "$app_root/ytmpl" ? (app_base => '@ytmpl') : ())
   , namespace => ['yatt', 'perl', 'js']
   , header_charset => 'utf-8'
   , debug_cgen => $ENV{DEBUG_CGEN}
   # , is_gateway => $ENV{GATEWAY_INTERFACE} # Too early for FastCGI.
   # , tmpl_encoding => 'utf-8'
  );

$dispatcher->to_app;

