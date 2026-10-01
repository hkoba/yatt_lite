#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#
# Perl モジュールで定義した ArgMacro (YATT::Lite::ArgMacro) のテスト。
#
#  - 1 pm = 1 macro。use YATT::Lite::ArgMacro out => [...], in => [...]
#  - Site 設定 argmacro => {name => 'Module'} で登録し、%name; で使う
#  - Args/Vars/Result の field 名 typo は pm のコンパイル時に検出される
#
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test::Kantan;
use File::Temp qw/tempdir/;

use YATT::t::t_preload; # To make Devel::Cover happy.
use YATT::Lite;
use YATT::Lite::WebMVC0::SiteApp;
use YATT::Lite::Util::File qw/mkfile_may_wait/;

my $tempdir = tempdir(CLEANUP => 1);
END {chdir "/"}
my $testno = 0;

my $libdir = "$tempdir/lib";
unshift @INC, $libdir;

YATT::Lite::Util::File->mkfile_may_wait(
  "$libdir/TestArgMacro/Pair.pm" => <<'END',
package TestArgMacro::Pair;
use strict;
use warnings;
use YATT::Lite::ArgMacro
  out => [qw(x y)],
  in  => [qw(pair)];

sub on_expand {
  (my MY $class, my CGen $cgen, my Args $args, my Vars $vars) = @_;
  my Result $result = {};
  my ($x, $y) = split /\s*,\s*/, $cgen->node_value($args->{pair});
  $result->{x} = $x;
  $result->{y} = $y;
  $result;
}
1;
END

  "$libdir/TestArgMacro/Enum.pm" => <<'END',
package TestArgMacro::Enum;
use strict;
use warnings;
use YATT::Lite::ArgMacro
  out => [qw(list=list)],
  in  => ['first=value/0', 'last=value!'];

sub on_expand {
  (my MY $class, my CGen $cgen, my Args $args, my Vars $vars) = @_;
  my Result $result = {};
  my $firstExpr = $args->{first} ? $cgen->node_value($args->{first})
    : $vars->{first}->default;
  my $lastExpr = $cgen->node_value($args->{last});
  $result->{list} = sprintf(q{%s .. %s}, $firstExpr, $lastExpr);
  $result;
}
1;
END

  "$libdir/TestArgMacro/Typo.pm" => <<'END',
package TestArgMacro::Typo;
use strict;
use warnings;
use YATT::Lite::ArgMacro
  out => [qw(x)],
  in  => [qw(pair)];

sub on_expand {
  (my MY $class, my CGen $cgen, my Args $args, my Vars $vars) = @_;
  my Result $result = {};
  $result->{xx} = $cgen->node_value($args->{pair});
  $result;
}
1;
END

  "$libdir/TestArgMacro/NotAMacro.pm" => <<'END',
package TestArgMacro::NotAMacro;
sub on_expand {}
1;
END
);

my $make_app = sub {
  my ($argmacro, %files) = @_;
  my $app_root = "$tempdir/t" . ++$testno;
  my $docroot = "$app_root/docs";
  YATT::Lite::Util::File->mkfile_may_wait(
    map {("$docroot/$_" => $files{$_})} keys %files
  );
  YATT::Lite::WebMVC0::SiteApp->new(
    app_ns => "TestArgMacroModule$testno",
    app_root => $app_root,
    doc_root => $docroot,
    argmacro => $argmacro,
  );
};

describe "argmacro defined in perl module", sub {
  my $site = $make_app->(
    {pair => 'TestArgMacro::Pair', enum => 'TestArgMacro::Enum'},
    'pair.yatt' => <<'END',
<yatt:foo pair="3, 8"/>

<!yatt:widget foo %pair;>
x=&yatt:x; y=&yatt:y;
END
    'enum.yatt' => <<'END',
<yatt:bar header=2 label=1/>

<!yatt:widget bar
  %enum(header=last);
  %enum(label=last);
>
<yatt:foreach my=row list=label_list><yatt:foreach my=col list=header_list
>[&yatt:row;&yatt:col;]</yatt:foreach></yatt:foreach>
END
    'override.yatt' => <<'END',
<yatt:foo pair="3, 8"/>

<!yatt:argmacro pair=[x y] pair>
my ($x, $y) = split /\s*,\s*/, $cgen->node_value($args->{pair});
$result->{x} = "local$x";
$result->{y} = "local$y";

<!yatt:widget foo %pair;>
x=&yatt:x; y=&yatt:y;
END
  );

  it "should expand macro from module", sub {
    expect($site->render("pair"))->to_match(qr/x=3 y=8/);
  };

  it "should expand renamed macro from module", sub {
    expect($site->render("enum"))
      ->to_match(qr/\[00\]\[01\]\[02\]\[10\]\[11\]\[12\]/);
  };

  it "should prefer argmacro declared in template", sub {
    expect($site->render("override"))->to_match(qr/x=local3 y=local8/);
  };
};

describe "errors", sub {
  my $site = $make_app->(
    {notamacro => 'TestArgMacro::NotAMacro'},
    'unknown.yatt' => <<'END',
<!yatt:widget foo %nosuch;>
END
    'notamacro.yatt' => <<'END',
<!yatt:widget foo %notamacro;>
END
  );

  it "should report unknown argmacro", sub {
    expect(do {local $@; eval {$site->render("unknown")}; $@})
      ->to_match(qr/Unknown argmacro 'nosuch'/);
  };

  it "should reject module which is not a YATT::Lite::ArgMacro", sub {
    expect(do {local $@; eval {$site->render("notamacro")}; $@})
      ->to_match(qr/is not a YATT::Lite::ArgMacro/);
  };

  it "should detect typo of field name at compile time of the module", sub {
    expect(do {local $@; eval {require TestArgMacro::Typo}; $@})
      ->to_match(qr/No such class field "xx" in variable \$result of type TestArgMacro::Typo::Result/);
  };
};

describe "declaration errors", sub {
  my $declare = sub {
    my @spec = @_;
    local $@;
    eval {YATT::Lite::ArgMacro->declare_into("TestArgMacro::Decl$testno", @spec)};
    $testno++;
    $@;
  };

  it "should require out", sub {
    expect($declare->(in => [qw(a)]))->to_match(qr/requires 'out'/);
  };

  it "should reject duplicate names", sub {
    expect($declare->(out => [qw(a)], in => [qw(a)]))
      ->to_match(qr/Duplicate arg name in ArgMacro: a/);
  };

  it "should reject unsupported types", sub {
    expect($declare->(out => [qw(a)], in => [qw(b=code)]))
      ->to_match(qr/not supported/);
  };
};

done_testing();
