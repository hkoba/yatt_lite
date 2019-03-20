#!/usr/bin/env perl
package YATT::Lite::Inspector;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base;


MY->run(\@ARGV) unless caller;

1;
