#!/usr/bin/env perl
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}
use base qw(File::Spec);

use FindBin;
use File::Basename;
use lib "$FindBin::Bin/lib";

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

my $dispatcher = YATT::Lite::Factory->find_load_factory_script || do {
    require YATT::Lite::WebMVC0::Toplevel;
    YATT::Lite::WebMVC0::Toplevel->new
	(appns => 'MyApp'
	 , namespace => ['yatt', 'perl', 'js']
	 , header_charset => 'utf-8'
	 , tmpldirs => [grep {-d} "ytmpl"]
	 , debug_cgen => $ENV{DEBUG}
	 , debug_cgi  => $ENV{DEBUG_CGI}
	 # , is_gateway => $ENV{GATEWAY_INTERFACE} # Too early for FastCGI.
	 # , tmpl_encoding => 'utf-8'
	);
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