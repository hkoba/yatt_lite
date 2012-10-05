#!/usr/bin/perl -T
#!/usr/bin/perl -w
package main; # For do 'runyatt.cgi'.
use strict;
use warnings FATAL => qw(all);
use sigtrap die => qw(normal-signals);
use FindBin;

#----------------------------------------
# Ensure ENV, for mod_fastcgi+FCGI.pm and Taint check.
$ENV{PATH} = "/sbin:/usr/sbin:/bin:/usr/bin";

#----------------------------------------
# To allow do 'runyatt.cgi', we should avoid using FindBin.
my $untaint_any; BEGIN { $untaint_any = sub { $_[0] =~ m{.*}s; $& } }
# To avoid redefinition of sub rootname.
my ($get_rootname, $get_extname);
BEGIN {
  $get_rootname = sub { my $fn = shift; $fn =~ s/\.\w+$//; join "", $fn, @_ };
  $get_extname = sub { my $fn = shift; $fn =~ s/\.(\w+)$// and $1 };
}
use Cwd qw(realpath);
use File::Spec;
my $app_root;
my $rootname;
my @libdir;
BEGIN {
  ($app_root) = map {
    s{/html/cgi-bin/.*}{} ? $_ : ();
  } $untaint_any->(File::Spec->rel2abs(__FILE__));
  $rootname = $get_rootname->($untaint_any->(realpath(__FILE__)));
  if (defined $rootname and -d $rootname) {
    push @libdir, "$rootname.lib";
  } elsif (my ($found) = $FindBin::Bin =~ m{^(.*?)/YATT/}) {
    push @libdir, $found;
  } else {
    warn "Can't find libdir";
  }
  if (-d (my $dn = "$app_root/extlib")) {
    push @libdir, $dn;
  }
}
use lib @libdir;

#
use YATT::Lite::Breakpoint;
use YATT::Lite::WebMVC0::SiteApp -as_base;

#----------------------------------------
my @opts;
for (; @ARGV and $ARGV[0] =~ /^--(\w+)(?:=(.*))?/s; shift @ARGV) {
  push @opts, $1, defined $2 ? $2 : 1;
}

#----------------------------------------
# You may edit params.

my $dispatcher = MY->new
  (app_ns => 'MyApp'
   , app_root => $app_root
   , namespace => ['yatt', 'perl', 'js']
   , header_charset => 'utf-8'
   , (-d "$rootname.ytmpl" ? (app_base => "$rootname.ytmpl") : ())
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
  $dispatcher->runas($get_extname->($0), \*STDOUT, \%ENV, \@ARGV
		     , progname => __FILE__);
}
