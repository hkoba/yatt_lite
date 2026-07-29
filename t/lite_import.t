#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#
# <!yatt:import> (GH-256) のテスト。
#
# <!yatt:import [name...]="file"> は別テンプレートの部品
# (widget/page/action/entity/argmacro) を現在のテンプレートへ
# 明示的に取り込む。
#
#  - rename:    [local=srcName]
#  - kind 注釈: [name:kind]  (widget / page / action / entity / argmacro)
#    無注釈はソース内で名前が一意な場合のみ自動判定
#  - 束縛は定義側に静的束縛 (取込側の同名 widget に負けない)
#  - ソース編集の追随は GH-255 の依存 product 再生成に乗る
#    (argmacro のみ base 継承と同等: 取込側の再 parse まで反映されない)
#
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test::Kantan;
use File::Temp qw/tempdir/;

use Plack::Test;
use HTTP::Request::Common;

use YATT::t::t_preload; # To make Devel::Cover happy.
use YATT::Lite;
use YATT::Lite::WebMVC0::SiteApp;
use YATT::Lite::Util::File qw/mkfile/;

my $tempdir = tempdir(CLEANUP => 1);
END {chdir "/"}
my $testno = 0;

my $make_app = sub {
  my (%files) = @_;
  my $app_root = "$tempdir/t" . ++$testno;
  my $docroot = "$app_root/docs";
  YATT::Lite::Util::File->mkfile(
    map {("$docroot/$_" => $files{$_})} keys %files
  );
  my $site = YATT::Lite::WebMVC0::SiteApp->new(
    app_ns => "TestImport$testno",
    app_root => $app_root,
    doc_root => $docroot,
  );
  ($docroot, $site);
};

my $future_mtime = time + 100;
my $rewrite = sub {
  my ($path, $content) = @_;
  YATT::Lite::Util::File->mkfile($path => $content);
  # mtime 比較 (Template::refresh) を確実に前進させる
  utime($future_mtime, $future_mtime, $path);
  $future_mtime += 10;
};

# エラー系は PSGI 経由で検査する。DirApp のエラーハンドラが
# エラーページを描画して DONE で脱出するため、render() 直呼びでは
# メッセージを捕捉できない (500 レスポンスの body に載る)。
my $expect_error = sub {
  my ($site, $path, $pattern) = @_;
  my $test = Plack::Test->create($site->to_app);
  my $res = $test->request(GET $path);
  expect($res->code)->to_be(500);
  expect($res->content)->to_match($pattern);
};

describe "widget import", sub {
  my ($docroot, $site) = $make_app->(
    'lib.ytmpl' => <<'END'
<!yatt:widget confirm x y>
confirm x=[&yatt:x;] y=[&yatt:y;]
<!yatt:widget register>
register widget
END
    ,
    'child.yatt' => <<'END'
<!yatt:import [confirm register]="lib.ytmpl">
<yatt:confirm x="a" y="b"/><yatt:register/>
END
    ,
    'child2.yatt' => <<'END'
<!yatt:import [ok=confirm]="lib.ytmpl">
<yatt:ok x="A" y="B"/>
END
  );

  it "should import multiple widgets by name", sub {
    my $out = $site->render("child");
    expect($out)->to_match(qr/confirm x=\[a\] y=\[b\]/);
    expect($out)->to_match(qr/register widget/);
  };

  it "should import a widget with rename [ok=confirm]", sub {
    expect($site->render("child2"))->to_match(qr/confirm x=\[A\] y=\[B\]/);
  };
};

describe "page import (public dispatch)", sub {
  my ($docroot, $site) = $make_app->(
    'lib.ytmpl' => <<'END'
<!yatt:page confirm>
confirm page from lib
END
    ,
    'child.yatt' => <<'END'
<!yatt:import [confirm:page]="lib.ytmpl">
child body
END
    ,
    'child2.yatt' => <<'END'
<!yatt:import [ok=confirm:page]="lib.ytmpl">
child2 body
END
  );
  my $test = Plack::Test->create($site->to_app);

  # プロセス起動後、child.yatt が一度もコンパイルされていない状態で
  # いきなり import した page を sigil で呼ぶ (GH-255 バグ A の import 版)。
  it "should dispatch imported page as the very first request", sub {
    my $res = $test->request(GET "/child?~confirm=1");
    expect($res->code)->to_be(200);
    expect($res->content)->to_match(qr/confirm page from lib/);
  };

  it "should dispatch renamed imported page", sub {
    my $res = $test->request(GET "/child2?~ok=1");
    expect($res->code)->to_be(200);
    expect($res->content)->to_match(qr/confirm page from lib/);
  };
};

describe "action import", sub {
  my ($docroot, $site) = $make_app->(
    'lib.ytmpl' => <<'END'
<!yatt:action doit>
print $CON "action doit from lib";
END
    ,
    'child.yatt' => <<'END'
<!yatt:import [doit]="lib.ytmpl">
child body
END
    ,
    'child2.yatt' => <<'END'
<!yatt:import [go=doit:action]="lib.ytmpl">
child2 body
END
  );
  my $test = Plack::Test->create($site->to_app);

  it "should dispatch imported action", sub {
    my $res = $test->request(GET "/child?!doit=1");
    expect($res->code)->to_be(200);
    expect($res->content)->to_match(qr/action doit from lib/);
  };

  it "should dispatch renamed imported action", sub {
    my $res = $test->request(GET "/child2?!go=1");
    expect($res->code)->to_be(200);
    expect($res->content)->to_match(qr/action doit from lib/);
  };
};

describe "entity import", sub {
  my ($docroot, $site) = $make_app->(
    'lib.ytmpl' => <<'END'
<!yatt:entity hex num>
sprintf "%x", $num;
END
    ,
    'child.yatt' => <<'END'
<!yatt:import [hex]="lib.ytmpl">
val=[&yatt:hex(255);]
END
    ,
    'child2.yatt' => <<'END'
<!yatt:import [h=hex:entity]="lib.ytmpl">
val=[&yatt:h(255);]
END
  );

  it "should import an entity (auto detected)", sub {
    expect($site->render("child"))->to_match(qr/val=\[ff\]/);
  };

  it "should import an entity with rename [h=hex:entity]", sub {
    expect($site->render("child2"))->to_match(qr/val=\[ff\]/);
  };
};

describe "argmacro import", sub {
  my ($docroot, $site) = $make_app->(
    'lib.ytmpl' => <<'END'
<!yatt:argmacro pair=[x y] pair>
my ($x, $y) = split /\s*,\s*/, $cgen->node_value($args->{pair});
$result->{x} = $x;
$result->{y} = $y;
END
    ,
    'child.yatt' => <<'END'
<!yatt:import [pair:argmacro]="lib.ytmpl">
<yatt:foo pair="3, 8"/>

<!yatt:widget foo %pair;>
x=&yatt:x; y=&yatt:y;
END
    ,
    'child2.yatt' => <<'END'
<!yatt:import [duo=pair:argmacro]="lib.ytmpl">
<yatt:foo pair="4, 9"/>

<!yatt:widget foo %duo;>
x=&yatt:x; y=&yatt:y;
END
  );

  it "should expand imported argmacro in widget decl", sub {
    expect($site->render("child"))->to_match(qr/x=3 y=8/);
  };

  it "should expand renamed imported argmacro", sub {
    expect($site->render("child2"))->to_match(qr/x=4 y=9/);
  };
};

describe "static binding to definition side", sub {
  my ($docroot, $site) = $make_app->(
    'lib.ytmpl' => <<'END'
<!yatt:widget helper>
lib helper
<!yatt:widget outer>
outer(<yatt:helper/>)
END
    ,
    'child.yatt' => <<'END'
<!yatt:import [outer]="lib.ytmpl">
<yatt:outer/>

<!yatt:widget helper>
CHILD helper
END
  );

  it "should resolve inner references on the definition side", sub {
    my $out = $site->render("child");
    expect($out)->to_match(qr/outer\(\s*lib helper\s*\)/);
    expect($out)->not->to_match(qr/CHILD helper/);
  };
};

describe "editing imported source", sub {
  my ($docroot, $site) = $make_app->(
    'lib.ytmpl' => <<'END'
<!yatt:widget bhead x y>
x=[&yatt:x;] y=[&yatt:y;] v1
END
    ,
    # 呼び出し側は名前付きで渡している。
    # gen_putargs はこれを子のコンパイル時に位置引数へ静的変換する。
    'child.yatt' => <<'END'
<!yatt:import [bhead]="lib.ytmpl">
child: <yatt:bhead x="XX" y="YY"/>
END
  );

  it "should render v1 before edit", sub {
    expect($site->render("child"))->to_match(qr/x=\[XX\] y=\[YY\] v1/);
  };

  it "should reflect body edit of imported widget", sub {
    $rewrite->("$docroot/lib.ytmpl", <<'END');
<!yatt:widget bhead x y>
x=[&yatt:x;] y=[&yatt:y;] v2 EDITED
END
    expect($site->render("child"))->to_match(qr/x=\[XX\] y=\[YY\] v2 EDITED/);
  };

  it "should keep mapping named args after swapping arg decls", sub {
    $rewrite->("$docroot/lib.ytmpl", <<'END');
<!yatt:widget bhead y x>
x=[&yatt:x;] y=[&yatt:y;] v3
END
    # ソースは再コンパイルされるが、子の呼び出し側 product も
    # 再生成されなければ x と y が入れ替わってしまう (GH-255 バグ B の import 版)
    expect($site->render("child"))->to_match(qr/x=\[XX\] y=\[YY\] v3/);
  };
};

describe "on-memory (data) vfs", sub {
  my $yatt = YATT::Lite->new(
    app_ns => "TestImportData",
    vfs => [data => {
      lib => "<!yatt:widget w>\nfrom lib\n",
      child => qq{<!yatt:import [w]="lib">\n<yatt:w/>\n},
    }],
  );

  it "should import widget from on-memory vfs", sub {
    expect($yatt->render('child'))->to_match(qr/from lib/);
  };
};

describe "error cases", sub {

  describe "unknown name", sub {
    my ($docroot, $site) = $make_app->(
      'lib.ytmpl' => "<!yatt:widget confirm>\nconfirm\n",
      'child.yatt' => qq{<!yatt:import [nosuch]="lib.ytmpl">\nbody\n},
    );
    it "should raise No such part error", sub {
      $expect_error->($site, "/child", qr/No such part to import/i);
    };
  };

  describe "kind annotation mismatch", sub {
    my ($docroot, $site) = $make_app->(
      'lib.ytmpl' => "<!yatt:widget confirm>\nconfirm\n",
      'child.yatt' => qq{<!yatt:import [confirm:action]="lib.ytmpl">\nbody\n},
    );
    it "should raise kind mismatch error", sub {
      $expect_error->($site, "/child", qr/kind mismatch/i);
    };
  };

  describe "ambiguous name (widget vs entity)", sub {
    my ($docroot, $site) = $make_app->(
      'lib.ytmpl' => <<'END'
<!yatt:widget dup>
dup widget
<!yatt:entity dup>
"dup entity";
END
      ,
      'child.yatt' => qq{<!yatt:import [dup]="lib.ytmpl">\nbody\n},
    );
    it "should require kind annotation", sub {
      $expect_error->($site, "/child", qr/Ambiguous import/i);
    };
  };

  describe "conflict with local part", sub {
    my ($docroot, $site) = $make_app->(
      'lib.ytmpl' => "<!yatt:widget confirm>\nlib confirm\n",
      'child.yatt' => <<'END'
<!yatt:import [confirm]="lib.ytmpl">
body

<!yatt:widget confirm>
local confirm
END
    );
    it "should raise conflict error", sub {
      $expect_error->($site, "/child", qr/Conflicting part name/i);
    };
  };

  describe "circular import", sub {
    my ($docroot, $site) = $make_app->(
      'a.yatt' => <<'END'
<!yatt:import [w2]="b.ytmpl">
a body

<!yatt:widget w1>
A w1
END
      ,
      'b.ytmpl' => <<'END'
<!yatt:import [w1]="a.yatt">

<!yatt:widget w2>
B w2
END
    );
    it "should raise circular import error", sub {
      $expect_error->($site, "/a", qr/Circular import/i);
    };
  };
};

done_testing();
