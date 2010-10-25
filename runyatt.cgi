#!/usr/bin/perl -wT
#!/usr/bin/perl -w
package main; # For do 'runyatt.cgi'.
use strict;
use warnings FATAL => qw(all);
use sigtrap die => qw(normal-signals);

#----------------------------------------
# Ensure ENV, for mod_fastcgi+FCGI.pm
$ENV{PATH} ||= "/sbin:/usr/sbin:/bin:/usr/bin";

#----------------------------------------
# To allow do 'runyatt.cgi', we should avoid using FindBin.
my $untaint_any; BEGIN { $untaint_any = sub { $_[0] =~ m{.*}s; $& } }
sub rootname { my $fn = shift; $fn =~ s/\.\w+$//; join "", $fn, @_ }
sub extname { my $fn = shift; $fn =~ s/\.(\w+)$// and $1 }
use Cwd qw(realpath);
my $rootname;
use lib ($rootname = rootname($untaint_any->(realpath(__FILE__)))).".lib";
#
use YATT::Lite::Breakpoint;
use YATT::Lite::Web::Dispatcher;

#----------------------------------------
my @opts;
for (; @ARGV and $ARGV[0] =~ /^--(\w+)(?:=(.*))?/s; shift @ARGV) {
  push @opts, $1, defined $2 ? $2 : 1;
}

#----------------------------------------
# You may edit params.

my $dispatcher = YATT::Lite::Web::Dispatcher->new
  (basens => 'MyApp'
   , namespace => ['yatt', 'perl', 'js']
   , header_charset => 'utf-8'
   , tmpldirs => [grep {-d} "$rootname.ytmpl"]
   , debug_cgen => $ENV{DEBUG}
   , debug_cgi  => $ENV{DEBUG_CGI}
   # , is_gateway => $ENV{GATEWAY_INTERFACE} # Too early for FastCGI.
   # , tmpl_encoding => 'utf-8'
   , @opts
  );

if (caller) {
  # For do 'runyatt.cgi'.
  return $dispatcher;
} else {
  $dispatcher->runas(extname($0), \*STDOUT, @ARGV);
}
