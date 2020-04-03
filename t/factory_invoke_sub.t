#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test::More;

use YATT::Lite;
use YATT::Lite::Factory;
sub Factory () {'YATT::Lite::Factory'}

use YATT::Lite::Util qw(appname catch);

sub myapp {join _ => MyTest => appname($0), @_}

#----------------------------------------
# invoke_sub_in
#----------------------------------------

my $i = 0;
{
  my $theme = "invoke_sub_in";
  my $item = "sess_backed/2/app.psgi";
  my $fn = "$FindBin::Bin/../samples/$item";
  my $CLS = myapp($i);
  ok(my $app = Factory->load_factory_script($fn), $item);

  is_deeply($app->invoke_sub_in("/", +{}, sub {
    my ($dh, $con) = @_;
    $dh->EntNS->entity_psgix_session;
  }), +{}, "entity_session");
}


done_testing();

