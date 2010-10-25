#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}
use base qw(File::Spec);

use File::Basename;
sub updir {my ($n, $fn) = @_; $fn = dirname($fn) while $n-- > 0; $fn}
my $libdir;
use lib $libdir = updir(3, MY->rel2abs(__FILE__));

use YATT::Lite::Util::FindMethods;

use YATT::Lite qw(*YATT);
use YATT::Lite::Breakpoint;

my $dispatcher = do {
  (my $cgi = $libdir) =~ s/\.\w+$/.cgi/;
  if (-r $cgi) {
    do $cgi;
  } else {
    die "Not implemented yet. Can't find driver: $cgi\n";
  }
};

local $YATT = my $dirhandler = $dispatcher->get_dirhandler('.');

unless (@ARGV) {
  die <<END, join("\n", map {"  $_"} FindMethods($YATT, sub {s/^cmd_//}))."\n";
Usage: @{[basename($0)]} COMMAND args...

Available commands are:
END
}

my $command = shift;
my $sub = $YATT->can("cmd_$command")
  or die "No such command: $command\n";

$sub->($dirhandler, @ARGV);
