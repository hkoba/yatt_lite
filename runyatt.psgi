#!/usr/bin/perl
# -*- perl -*-
use strict;
use warnings FATAL => qw(all);

my (@tmpldir);
BEGIN {
  require File::Spec;
  require File::Basename;
  my $rootname = sub { my $fn = shift; $fn =~ s/\.\w+$//; join "", $fn, @_ };
  my $script = File::Spec->rel2abs(__FILE__);
  my @roots = $rootname->($script);
  while (-l $script) {
    my $linked = readlink $script;
    my $real = File::Spec->file_name_is_absolute($linked) ? $linked : do {
      my ($file, $dir) = File::Basename::fileparse $script;
      File::Spec->catfile($dir, $linked);
    };
    # print "$script => [$linked] => $real\n";
    push @roots, $rootname->($real);
    $script = $real;
  }
  # print @libs, "\n";
  foreach my $root (@roots) {
    my $lib = "$root.lib";
    if (-d $lib and not grep {$_ eq $lib} @INC) {
      unshift @INC, $lib;
    }
    my $ytmpl = "$root.ytmpl";
    if (-d $ytmpl) {
      unshift @tmpldir, $ytmpl
    }
  }
}

use YATT::Lite::Web::Dispatcher;

my $dispatcher = YATT::Lite::Web::Dispatcher->new
  (document_root => File::Basename::dirname(File::Spec->rel2abs(__FILE__))
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
