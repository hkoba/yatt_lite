#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}
use base qw(File::Spec);
use File::Basename;

use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
my $libdir;
BEGIN {
  unless (grep {$_ eq 'YATT'} MY->splitdir($FindBin::Bin)) {
    die "Can't find YATT in runtime path: $FindBin::Bin\n";
  }
  $libdir = dirname(dirname(dirname(untaint_any($FindBin::Bin))));
}
use lib $libdir;
#----------------------------------------

use base qw/YATT::Lite::Object
	    YATT::Lite::Util::CmdLine/;
use fields qw/cf_file cf_debug/;

MY->run(\@ARGV);

sub cmd_test {
  (my MY $self, my @args) = @_;
  print "TEST(@args)\n";
}
