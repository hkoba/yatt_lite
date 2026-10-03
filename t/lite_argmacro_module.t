#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#
# Perl モジュールで定義した ArgMacro (YATT::Lite::ArgMacro) のテスト。
#
#  - 1 pm = 1 macro。use YATT::Lite::ArgMacro out => [...], in => [...]
#  - Site 設定 argmacro => {name => 'Module'} で登録し、%name; で使う
#  - Args/Vars/Result の field 名 typo は pm のコンパイル時に検出される
#  - argmacro => [[ns => {name => 'Module'}], {...}] で名前空間付き登録。
#    %ns:name; は登録表のみ、%name; はページ内 → base → primary ns の登録
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

  (map {
    my ($pkg, $out, $in, $value) = @$_;
    ("$libdir/TestArgMacro/$pkg.pm" => <<END);
package TestArgMacro::$pkg;
use strict;
use warnings;
use YATT::Lite::ArgMacro
  out => [qw($out)],
  in  => [qw($in)];

sub on_expand {
  (my MY \$class, my CGen \$cgen, my Args \$args, my Vars \$vars) = \@_;
  my Result \$result = {};
  \$result->{$out} = q{$value};
  \$result;
}
1;
END
  } ([SrcA => src => tag => 'modA'], [SrcB => src => tag => 'modB'],
     [OtherC => other => otag => 'modC'])),

  "$libdir/TestArgMacro/NotAMacro.pm" => <<'END',
package TestArgMacro::NotAMacro;
sub on_expand {}
1;
END
);

my $make_app = sub {
  my ($argmacro, @rest) = @_;
  my @opts = ref $rest[0] eq 'ARRAY' ? @{shift @rest} : ();
  my %files = @rest;
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
    @opts,
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

{
  my @ns = (namespace => [qw(myteam myorg yatt perl)]);

  # XXX: SiteApp->render は一度成功した後のエラーを \"DONE" で返すため、
  # エラーになるページを先に render する。
  my $render_err = sub {
    my ($site, $page) = @_;
    local $@;
    my $out = eval {$site->render($page)};
    $@ || $out;
  };

  my $use = sub {
    my ($ref) = @_;
    (my $fn = "$ref.yatt") =~ s/:/_/g;
    ($fn => <<END);
<yatt:w tag=1/>

<!yatt:widget w %$ref;>
src=&yatt:src;
END
  };

  my $local_foo = <<'END';
<!yatt:argmacro foo=[src] tag>
$result->{src} = q{local};
END

  describe "namespace: argmacro registered with namespace", sub {
    my $site = $make_app->(
      [[myorg => {foo => 'TestArgMacro::SrcA'}]], [@ns],
      $use->('myorg:foo'),
      $use->('foo'),
      'override.yatt' => <<END,
<yatt:w tag=1/><yatt:w2 tag=1/>
$local_foo
<!yatt:widget w %foo;>
w=&yatt:src;
<!yatt:widget w2 %myorg:foo;>
w2=&yatt:src;
END
    );

    it "should not be referenced without namespace", sub {
      expect($render_err->($site, "foo"))
        ->to_match(qr/Unknown argmacro 'foo'/);
    };

    it "should be referenced with the namespace", sub {
      expect($render_err->($site, "myorg_foo"))->to_match(qr/src=modA/);
    };

    it "should prefer page-local argmacro only for %foo;", sub {
      expect($render_err->($site, "override"))
        ->to_match(qr/w=local\s*w2=modA/);
    };
  };

  describe "namespace: argmacro registered without namespace", sub {
    my $site = $make_app->(
      {foo => 'TestArgMacro::SrcA'}, [@ns],
      $use->('foo'),
      $use->('myteam:foo'),
      $use->('myorg:foo'),
      $use->('yatt:foo'),
    );

    it "should not be referenced with other namespace (myorg)", sub {
      expect($render_err->($site, "myorg_foo"))
        ->to_match(qr/Unknown argmacro 'myorg:foo'/);
    };

    it "should not be referenced with other namespace (yatt)", sub {
      expect($render_err->($site, "yatt_foo"))
        ->to_match(qr/Unknown argmacro 'yatt:foo'/);
    };

    it "should be referenced without namespace", sub {
      expect($render_err->($site, "foo"))->to_match(qr/src=modA/);
    };

    it "should be referenced with primary namespace", sub {
      expect($render_err->($site, "myteam_foo"))->to_match(qr/src=modA/);
    };
  };

  describe "namespace: argmacro registered with primary namespace", sub {
    my $site = $make_app->(
      [[myteam => {foo => 'TestArgMacro::SrcA'}]], [@ns],
      $use->('foo'),
    );

    it "should be referenced without namespace too", sub {
      expect($render_err->($site, "foo"))->to_match(qr/src=modA/);
    };
  };

  describe "namespace: same name in different namespaces", sub {
    my $site = $make_app->(
      [[myorg => {foo => 'TestArgMacro::SrcA'}],
       {foo => 'TestArgMacro::OtherC'}], [@ns],
      'both.yatt' => <<'END',
<yatt:w tag=1 otag=1/>

<!yatt:widget w %myorg:foo; %foo;>
src=&yatt:src; other=&yatt:other;
END
    );

    it "should be usable together in one widget", sub {
      expect($render_err->($site, "both"))
        ->to_match(qr/src=modA other=modC/);
    };
  };

  describe "namespace: registration errors", sub {
    my $reg_err = sub {
      my ($argmacro) = @_;
      local $@;
      eval {
        my $site = $make_app->($argmacro, [@ns], $use->('foo'));
        $site->render("foo");
      };
      $@;
    };

    it "should reject duplicate registration in primary namespace", sub {
      expect($reg_err->([{foo => 'TestArgMacro::SrcA'},
                         [myteam => {foo => 'TestArgMacro::SrcB'}]]))
        ->to_match(qr/Duplicate argmacro registration 'myteam:foo'/);
    };

    it "should reject duplicate registration in the same namespace", sub {
      expect($reg_err->([[myorg => {foo => 'TestArgMacro::SrcA'}],
                         [myorg => {foo => 'TestArgMacro::SrcB'}]]))
        ->to_match(qr/Duplicate argmacro registration 'myorg:foo'/);
    };

    it "should reject unknown namespace", sub {
      expect($reg_err->([[nosuch => {foo => 'TestArgMacro::SrcA'}]]))
        ->to_match(qr/Unknown namespace 'nosuch' in argmacro registration/);
    };

    it "should reject malformed spec", sub {
      expect($reg_err->([[myorg => 'TestArgMacro::SrcA']]))
        ->to_match(qr/Invalid argmacro registration/);
    };

    it "should reject invalid macro name", sub {
      expect($reg_err->({'foo-bar' => 'TestArgMacro::SrcA'}))
        ->to_match(qr/Invalid argmacro name 'foo-bar'/);
    };
  };

  describe "namespace: reference errors", sub {
    my $site = $make_app->(
      {}, [@ns],
      $use->('bogus:foo'),
      'multi.yatt' => <<'END',
<!yatt:widget w %myorg:foo:bar;>
END
      'localonly.yatt' => <<END,
<yatt:w tag=1/>
$local_foo
<!yatt:widget w %myorg:foo;>
END
    );

    it "should reject unknown namespace", sub {
      expect($render_err->($site, "bogus_foo"))
        ->to_match(qr/Unknown namespace 'bogus' in argmacro reference/);
    };

    it "should reject extra path", sub {
      expect($render_err->($site, "multi"))
        ->to_match(qr/Invalid argmacro reference/);
    };

    it "should hint page-local argmacro", sub {
      expect($render_err->($site, "localonly"))
        ->to_match(qr/Unknown argmacro 'myorg:foo' \(page-local argmacro 'foo' can only be referenced as %foo;\)/);
    };
  };
}

done_testing();
