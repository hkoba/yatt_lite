#!/usr/bin/perl
# -*- perl -*-
use strict;
use warnings FATAL => qw(all);

use Cwd;
use lib getcwd() . "/runyatt.lib";
my @tmpldir = getcwd() . "/runyatt.ytmpl";

use YATT::Lite::Web::Dispatcher;
my $appdir = getcwd();
my $docroot = $ENV{YATT_DOCUMENT_ROOT} || "$appdir/html";

unless (-d $docroot) {
  die "Can't find document root for " . __FILE__ . ": $docroot";
}

my $dispatcher = YATT::Lite::Web::Dispatcher->new
  (document_root => $docroot
   , basens => 'MyApp'
   , namespace => ['yatt', 'perl', 'js']
   , header_charset => 'utf-8'
   , tmpldirs => \@tmpldir
   , debug_cgen => $ENV{DEBUG}
   , debug_cgi  => $ENV{DEBUG_CGI}
   # , is_gateway => $ENV{GATEWAY_INTERFACE} # Too early for FastCGI.
   # , tmpl_encoding => 'utf-8'
  );

unless (caller) {
  require Plack::Runner;
  my $runner = Plack::Runner->new;
  $runner->parse_options(@ARGV);
  return $runner->run($dispatcher->to_app);
}

$dispatcher->to_app;
