#!/usr/bin/env perl
package YATT::Lite::LanguageServer;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use YATT::Lite::LanguageServer::Generic -as_base;

MY->run(\@ARGV) unless caller;

1;
