# -*- perl -*-
use strict;
use warnings FATAL => qw(all);

use File::Spec;
use File::Basename ();
use Cwd ();

{
  my ($app_root, @libdir);
  #
  # First, locate YATT library dir.
  #
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

  #
  # Now, we are ready to load YATT libraries.
  #

  use YATT::Lite::WebMVC0::SiteApp -as_base;
  use YATT::Lite qw/Entity *CON/; # For Entity and $CON.

  # To add other option, use MFields like this:
  # use YATT::Lite::MFields qw/cf_dbi_dsn cf_auto_deploy /;
  #

  my $site = MY->new
    (app_ns => 'MyApp'
     , app_root => $app_root
     , doc_root => "$app_root/html"
     , (-d "$app_root/ytmpl" ? (app_base => '@ytmpl') : ())
     , namespace => ['yatt', 'perl', 'js']
     , header_charset => 'utf-8'
     , use_subpath => 1
     , debug_cgen => $ENV{DEBUG_CGEN}
    );

  {
    ;
#
# Site wide entity can be defined here.
#
#    Entity foo => sub {
#      my ($this, $arg) = @_;
#    };
  }

  my $app = $site->to_app;

  unless (caller) {
    # If this script is the toplevel.
    require Plack::Runner;
    my $runner = Plack::Runner->new(app => $app);
    $runner->parse_options(@ARGV);
    $runner->run;

  } elsif ($site->want_object) {
    # When caller wants $site object itself rather than app sub.
    #  (Usually for yatt.lint and other utils)
    return $site;

  } else {
    # Otherwise, returns psgi app.
    return $app;
  }
}
