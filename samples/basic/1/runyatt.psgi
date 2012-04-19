#!/usr/bin/perl
# -*- perl -*-
use strict;
use warnings FATAL => qw(all);

use File::Spec;
require File::Basename;

my ($rootname);
BEGIN {
  $rootname = (sub { my $fn = shift; $fn =~ s/\.\w+$//; join "", $fn, @_ })
    ->(__FILE__);
  my $libdir = "$rootname.lib";
  if (-d $libdir and not grep {$libdir eq $_} @INC) {
    unshift @INC, $libdir;
  }
}

use YATT::Lite::Web::Dispatcher;

my $dispatcher = YATT::Lite::Web::Dispatcher->new
  (document_root => File::Basename::dirname(File::Spec->rel2abs(__FILE__))
   , appns => 'MyApp'
   , namespace => ['yatt', 'perl', 'js']
   , header_charset => 'utf-8'
   , tmpldirs => [grep {-d} "$rootname.ytmpl"]
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
