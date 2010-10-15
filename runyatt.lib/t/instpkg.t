#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);

use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/..");

use YATT::Lite::Util qw(appname);
sub myapp {join _ => MyTest => appname($0), @_}

use Test::More qw(no_plan);

sub NSBuilder () {'YATT::Lite::NSBuilder'}

{
  my $builder = NSBuilder->new;
  sub Foo::bar {'baz'}
  is my $pkg = $builder->buildns(INST => 'Foo'), NSBuilder.'::INST1', "inst1";
  is $pkg->bar, "baz", "$pkg->bar";
}

{
  my $CLS = myapp();
  my $builder = NSBuilder->new(basens => $CLS);
  sub MyTest_instpkg::bar {'BARRR'}
  is my $pkg = $builder->buildns, "${CLS}::INST1", "$CLS inst1";
  is $pkg->bar, "BARRR", "$pkg->bar";

  is my $pkg2 = $builder->buildns(TMPL => $CLS), "${CLS}::TMPL1", "$CLS tmpl1";
  is $pkg2->bar, "BARRR", "$pkg2->bar";

  sub MyTest_instpkg::EntNS::bar {'barrrr'}
  my $cache = $builder->tmplcache;
  $cache->{foo} ||= $builder->buildns(EntNS => 'MyTest_instpkg::EntNS');
  is $cache->{foo}, "${CLS}::EntNS1", "$CLS tmpl1";
  is $cache->{foo}->bar, 'barrrr', "tmplpkg";
}

{
  {
    package Extended; BEGIN {$INC{'Extended.pm'} = 1}
    use base qw(YATT::Lite::NSBuilder);
    # ?? constant 経由、つまり use base InstPkg だと BEGIN redefined に？？
    use fields qw(cf_newattr);
  }
  my Extended $builder = Extended->new(basens => 'MyApp2', newattr => 'bar');
  is $builder->{cf_newattr}, 'bar', "Extended attr";
}
