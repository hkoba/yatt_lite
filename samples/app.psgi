#!/usr/bin/perl
# -*- perl -*-
use strict;
use warnings FATAL => qw(all);

use File::Spec;
use File::Basename ();
my $appdir;
use lib ($appdir = File::Basename::dirname(File::Spec->rel2abs(__FILE__)))
  . "/lib";

use YATT::Lite::WebMVC0::Toplevel;

my $dispatcher = YATT::Lite::WebMVC0::Toplevel->new
  (document_root => "$appdir/html"
   , appns => 'MyApp'
   , namespace => ['yatt', 'perl', 'js']
   , header_charset => 'utf-8'
   , tmpldirs => [grep {-d} "$appdir/ytmpl"]
   , debug_cgen => $ENV{DEBUG}
   , debug_cgi  => $ENV{DEBUG_CGI}
   # , is_gateway => $ENV{GATEWAY_INTERFACE} # Too early for FastCGI.
   # , tmpl_encoding => 'utf-8'
  );

if (caller && YATT::Lite::Factory->loading) {
  return $dispatcher;
}

unless (caller) {
  require Plack::Runner;
  my $runner = Plack::Runner->new;
  $runner->parse_options(@ARGV);
  return $runner->run($dispatcher->to_app);
}

$dispatcher->to_app;
