#!/usr/bin/env perl
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}
use base qw(File::Spec);

use File::Basename;
sub updir {my ($n, $fn) = @_; $fn = dirname($fn) while $n-- > 0; $fn}
my $libdir;
use lib $libdir = updir(3, MY->rel2abs(__FILE__));

use YATT::Lite::Util::FindMethods;

use YATT::Lite::Factory;
use YATT::Lite qw(*YATT);
use YATT::Lite::Util qw(rootname);
use YATT::Lite::Breakpoint;

require YATT::Lite::Util::CmdLine;

use Getopt::Long;

GetOptions("if_can" => \ my $if_can
	  , "d=s" => \ my $o_dir)
  or exit 1;

my $dispatcher = do {
  (my $cgi = $libdir) =~ s/\.\w+$/.cgi/;
  if (-r $cgi) {
    YATT::Lite::Factory->load_factory_script($cgi);
  } else {
    require YATT::Lite::Web::Dispatcher;
    YATT::Lite::Web::Dispatcher->new
	(appns => 'MyApp'
	 , namespace => ['yatt', 'perl', 'js']
	 , header_charset => 'utf-8'
	 , tmpldirs => [grep {-d} rootname($libdir).".ytmpl"]
	 , debug_cgen => $ENV{DEBUG}
	 , debug_cgi  => $ENV{DEBUG_CGI}
	 # , is_gateway => $ENV{GATEWAY_INTERFACE} # Too early for FastCGI.
	 # , tmpl_encoding => 'utf-8'
	);
  }
};

local $YATT = my $dirhandler = $dispatcher->get_dirhandler($o_dir // '.');

unless (@ARGV) {
  die <<END, join("\n", map {"  $_"} FindMethods($YATT, sub {s/^cmd_//}))."\n";
Usage: @{[basename($0)]} COMMAND args...

Available commands are:
END
}

my $command = $ARGV[0];
if ($YATT->can("cmd_$command") || $YATT->can($command)) {
  YATT::Lite::Util::CmdLine::run($YATT, \@ARGV);
} elsif ($if_can) {
  exit
} else {
  die "No such command: $command\n";
}
