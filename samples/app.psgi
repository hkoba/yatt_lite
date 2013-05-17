# -*- perl -*-
use strict;
use warnings FATAL => qw(all);

use File::Spec;
use File::Basename ();
use Cwd ();
use Carp;
use List::MoreUtils qw/last_index/;

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

    require lib; import lib @libdir;

    if (not eval {require YATT::Lite::Breakpoint}
	and -l __FILE__
	and (my $d = last_index {$_ eq 'samples'}
	     my @d = File::Spec->splitdir(__FILE__)) >= 0) {
      print STDERR "d=$d; @d\n";
      my $dir = File::Spec->catdir(@d[0 .. ($d - 1)]);
      my $hook = sub {
	my ($this, $orig_modfn) = @_;
	return unless (my $modfn = $orig_modfn) =~ s!^YATT/!!;
	Carp::cluck("orig_modfn=$orig_modfn\n") if $ENV{DEBUG_INC};
	return unless -r (my $realfn = "$dir/../$modfn");
	warn "=> found $realfn" if $ENV{DEBUG_INC};
	open my $fh, '<', $realfn or die "Can't open $realfn:$!";
	$fh;
      };

      unshift @INC, $hook;
      push @INC, $hook, $hook;
      # XXX: Why I need to put this into @INC-hook 3times?!
    }
  }

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
