#!/usr/bin/env perl
# -*- coding: utf-8 -*-
use strict;
use warnings;

use File::Spec;
use File::Basename ();
use Cwd ();
{
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

  # To have siteapp-wide entity, we extend it.
  use YATT::Lite::WebMVC0::SiteApp -as_base;
  use YATT::Lite qw/Entity *CON/;

  my $dispatcher = MY->new
    (app_ns => 'MyApp'
     , app_root => $app_root
     , doc_root => "$app_root/html"
     , (-d "$app_root/ytmpl" ? (app_base => '@ytmpl') : ())
     , namespace => ['yatt', 'perl', 'js']
     , header_charset => 'utf-8'
     , tmpl_encoding => 'utf-8'
     , output_encoding => 'utf-8'
    );

  # Use given argument as docpath (or use current directory instead).
  {
    my @docpath;
    while (@ARGV and -d $ARGV[0]) {
      push @docpath, $dispatcher->rel2abs(shift @ARGV);
    }

    unless (@docpath) {
      push @docpath, $dispatcher->rel2abs(Cwd::cwd());
    }

    push @docpath, map {
      if (-d "$_/pod") {
	("$_/pod", $_)
      } else {
	$_
      }
    } grep {-d} @INC;

    my $dirapp = $dispatcher->get_yatt('/');

    $dirapp->configure(docpath => \@docpath);
  }

  unless (caller) {
    require Plack::Runner;
    my $runner = Plack::Runner->new(app => $dispatcher->to_app);
    $runner->parse_options(@ARGV);
    $runner->run;
  }

  return $dispatcher->to_app;
}

BEGIN {
  Entity default_lang => sub {'en'};

  Entity want_lang => sub {
    my ($this) = @_;
    my $lang = $CON->param('--lang') || do {
      my MY $yatt = $this->YATT;
      my $avail = $yatt->cget('lang_available') || [qw/en ja/];
      $CON->accept_language(filter => $avail);
    };
    unless ($lang =~ /^\w{2}$/) { # XXX: How about country suffix? (like en_GB)
      $CON->error("Invalid langugae: %s", $lang);
    }
    $lang;
  };
}

sub before_dirhandler {
  (my MY $self, my ($dh, $con, $file)) = @_;
  $self->set_lang($con);
}

sub set_lang {
  (my MY $self, my $con) = @_;
  my $yatt = $con->cget('yatt');
  my $lang = $self->EntNS->entity_want_lang
    || $self->EntNS->entity_default_lang;
  $con->configure(lang => $lang);
  $yatt->get_lang_msg($lang);
}
