#!/usr/bin/perl -w
use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin;
use ApacheConfig;

our $context = "";
my ($line);
while (<>) {
  chomp;
  if ($line = m{^(\Q<IfModule mod_userdir.c>\E)} .. m{^\Q</IfModule>\E}) {
    $context = $1 if $line == 1;
    set_config(qw(UserDir public_html));
  } elsif ($line = m{^\#?(\Q<Directory /home/*/public_html>\E)}
	   .. m{^\#?</Directory}) {
    $context = $1 if $line == 1;
    s/^\#//;
    set_config("AllowOverride", "All");
    # ensure_config("Options", "ExecCGI");
  }
} continue {
  print "$_\n";
}
