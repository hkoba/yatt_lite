#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);

use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/..");

use YATT::Lite::Util qw(appname);
sub myapp {join _ => MyTest => appname($0), @_}

use Test::More qw(no_plan);

use YATT::Lite;
use YATT::Lite::Factory;
sub Factory () {'YATT::Lite::Factory'}

{
  isa_ok(YATT::Lite->EntNS, 'YATT::Lite::Entities');
}


my $YL = 'YATT::Lite';

my $dummy_root = "/dummy%d/docs";
my $dummy_tmpl = "/dummy%d/tmpls";
my $i = 0;
{
  # MyApp が未定義で、 .htyattconfig.xhf も無いケース

  my $rootdir = sprintf $dummy_root, ++$i;
  my $tmpldir = sprintf $dummy_tmpl, ++$i;

  my $factory = Factory->new(appns => my $CLS = myapp()
			     , allow_missing_dir => 1
			     , document_root => $rootdir
			     , tmpldirs => [$tmpldir]);

  ok $CLS->isa($YL), "$CLS isa $YL";

  is $factory->get_pathns($rootdir)
    , my $rootns = $CLS . "::INST1"
      , "get rootns";

  is $factory->get_pathns($tmpldir)
    , my $tmplns = $CLS . "::TMPL1"
      , "get tmplns";
  ok $rootns->isa($tmplns), "$rootns isa $tmplns";

  is $rootns->EntNS, my $rooten = $rootns."::EntNS"
    , "root entns";
  ok $rooten->isa($YL->EntNS), "$rooten isa YATT::Lite::EntNS";

  is $tmplns->EntNS, my $tmplen = $tmplns."::EntNS"
    , "tmpl entns";
  ok $tmplen->isa($YL->EntNS), "$tmplen isa YATT::Lite::EntNS";

  ok $rooten->isa($tmplen), "$rooten isa $tmplen";
}

# xhf から baseclass[] をロードする
# 親クラスを生成し、 isa に代入する

# ディレクトリに pkg を割り当てる, のも Factory の仕事

