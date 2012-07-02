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
  $libdir = dirname(dirname(untaint_any($FindBin::Bin)));
}
use lib $libdir;
#----------------------------------------

use YATT::Lite::Util qw(appname list_isa);
sub myapp {join _ => MyTest => appname($0), @_}

use Test::More qw(no_plan);

sub NSBuilder () {'YATT::Lite::NSBuilder'}

use_ok(NSBuilder);

{
  my $builder = NSBuilder->new(app_ns => 'Foo');
  sub Foo::bar {'baz'}
  is my $pkg = $builder->buildns('INST'), 'Foo::INST1', "inst1";
  is $pkg->bar, "baz", "$pkg->bar";
}

{
  my $WDH = 'YATT::Lite::WebMVC0::App';
  {
    package MyTest_NSB_Web;
    use base qw(YATT::Lite::NSBuilder);
    use YATT::Lite::MFields;
    sub default_default_app {$WDH}
    use YATT::Lite::Inc;
  }
  my $NS = 'MyTest_NSB';
  my $builder = MyTest_NSB_Web->new(app_ns => $NS);

  my $sub = $builder->buildns('INST');
  is_deeply [list_isa($sub, 1)]
    , [[$NS, [$WDH, list_isa($WDH, 1)]]]
      , "sub inherits $NS, which inherits $WDH only.";

  ok $WDH->can('handle_yatt'), "$WDH is loaded (can handle_yatt)";
}

my $i = 0;
{
  my $CLS = myapp(++$i);
  is $CLS, 'MyTest_instpkg_1', "sanity check of test logic itself";
  my $builder = NSBuilder->new(app_ns => $CLS);
  sub MyTest_instpkg_1::bar {'BARRR'}
  is my $pkg = $builder->buildns, "${CLS}::INST1", "$CLS inst1";
  is $pkg->bar, "BARRR", "$pkg->bar";

  is my $pkg2 = $builder->buildns('TMPL'), "${CLS}::TMPL1", "$CLS tmpl1";
  is $pkg2->bar, "BARRR", "$pkg2->bar";
}

{
  my $NS = myapp(++$i);
  my $builder = NSBuilder->new(app_ns => $NS);

  my $base1 = $builder->buildns('TMPL');
  # my $base2 = $builder->buildns('TMPL');

  my $sub1 = $builder->buildns(INST => $base1);

  is_deeply [list_isa($sub1, 1)]
    , [[$base1, [$NS, ['YATT::Lite', list_isa('YATT::Lite', 1)]]]]
      , "sub1 inherits base1";
}

{
  my $YL = 'MyTest_instpkg_YL';
  {
    package MyTest_instpkg_YL;
    use base qw(YATT::Lite);
    use YATT::Lite::Inc;
  }

  my $NS = myapp(++$i);
  my $builder = NSBuilder->new(app_ns => $NS);

  my $sub = $builder->buildns(INST => $YL);
  is_deeply [list_isa($sub, 1)]
    , [[$YL, ['YATT::Lite', list_isa('YATT::Lite', 1)]]]
      , "sub inherits $YL only.";

  my $unknown = 'MyTest_instpkg_unk';
  eval {
    $builder->buildns(INST => $unknown);
  };
  like $@, qr/^None of baseclass inherits YATT::Lite: $unknown/
    , "Unknown baseclass should raise error";
}
