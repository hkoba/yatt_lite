#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/lib");
use Test::More qw(no_plan);
use YATT::Lite::TestUtil;
use YATT::Lite::Breakpoint ();

use YATT::Lite::Util qw(catch);
require_ok('YATT::Lite');

use YATT::Lite::Util qw(appname list_isa);
sub myapp {join _ => MyTest => appname($0), @_}

my $i = 1;

sub captured {
  my ($obj, $method, @args) = @_;
  open my $fh, ">", \ (my $buf = "") or die $!;
  if (ref $obj eq 'CODE') {
    $obj->($method, $fh, @args);
  } else {
    $obj->$method($fh, @args);
  }
  close $fh;
  $buf;
}

{
  my $theme = "infra";
  is(YATT::Lite->EntNS, "YATT::Lite::EntNS", "[$theme] YL->EntNS");
  is_deeply [list_isa("YATT::Lite::EntNS", 1)]
      , [['YATT::Lite::Entities']]
	, "[$theme] YL EntNS isa tree";
}

{
  my $theme = "[basic]";
  my $yatt = new YATT::Lite
    (app_ns => myapp(++$i)
     , vfs => [data => {foo => <<'END'
<!yatt:args a b>
&yatt:a;(<yatt:bar x=a y=b/>)&yatt:b;



<!yatt:widget bar x y>
<h2>&yatt:x;</h2>
&yatt:y;


END
	       , bar => <<'END'
<!yatt:args x y>
&yatt:x;[<yatt:foo:bar x y/>]&yatt:y;
END
	      }]
     , debug_cgen => $ENV{DEBUG});

  {
    my $SUB = 'foo';
    is "MyTest_lite_${i}"->EntNS, "MyTest_lite_${i}::EntNS"
      , "$theme $SUB->EntNS";
    is_deeply [list_isa("MyTest_lite_${i}::EntNS", 1)]
      , [['YATT::Lite::EntNS', ['YATT::Lite::Entities']]]
	, "$theme $SUB EntNS isa tree";

    ok(my $part = $yatt->find_part('foo', 'bar'), "$theme find_part");
    is_deeply $part->{arg_order}, [qw(x y body)], "$theme arg_order";
    ok(my $tmpl = $yatt->find_file('foo'), "$theme find_file $SUB");
    is my $pkg = $yatt->find_product(perl => $tmpl), "MyTest_lite_${i}::EntNS::$SUB"
      , "$theme find_product $SUB";
    eq_or_diff captured($pkg => render_ => my @param = ("FOO", "BAR"))
      , my $res = <<'END', "$theme $SUB render_";
FOO(<h2>FOO</h2>
BAR
)BAR
END

    eq_or_diff captured($yatt->find_renderer('foo'), @param), $res
      , "$theme $SUB find_renderer foo";
  }

  {
    my $SUB = 'bar';
    ok(my $bar_t = $yatt->find_file('bar'), "$theme find_file $SUB");
    is my $bar_p = $yatt->find_product(perl => $bar_t), "MyTest_lite_${i}::EntNS::$SUB"
      , "$theme find_product $SUB";
    eq_or_diff captured($bar_p => render_ => "FOO", "BAR")
      , <<'END', "$theme $SUB render_";
FOO[<h2>FOO</h2>
BAR
]BAR
END
  }

  {
    my $SUB = 'baz';
    ok(my $baz_t = $yatt->add_to(baz => <<'END'), "$theme add_to $SUB");
<!yatt:args x y z>
<yatt:foo a=x b=z/>
<yatt:foo:bar x y=z/>
<yatt:bar x y="&yatt:x;-&yatt:y;"/>
END
    is my $baz_p = $yatt->find_product(perl => $baz_t), "MyTest_lite_${i}::EntNS::$SUB"
    , "$theme find_product $SUB ";
    eq_or_diff captured($baz_p => render_ => "A", "B", "C")
      , <<'END', "$theme $SUB render_";
A(<h2>A</h2>
C
)C
<h2>A</h2>
C
A[<h2>A</h2>
A-B
]A-B

END
  }

  {
    my $SUB = 'pos';
    ok(my $pos_t = $yatt->add_to(pos => <<'END'), "$theme add_to $SUB");
<!yatt:args>
<yatt:posargs c="foo" "bar" 'baz'/>

<!yatt:widget posargs a b c>
A=&yatt:a;/ B=&yatt:b;/ C=&yatt:c;
END
    is my $pos_p = $yatt->find_product(perl => $pos_t), "MyTest_lite_${i}::EntNS::$SUB"
    , "$theme find_product $SUB ";
    eq_or_diff captured($pos_p => render_ => ())
      , <<'END', "$theme $SUB render_";
A=bar/ B=baz/ C=foo

END

  }

  {
    my $SUB = 'dobody';
    ok(my $pos_t = $yatt->add_to(dobody => <<'END'), "$theme add_to $SUB");
<!yatt:args>
<yatt:dobody "AAA" 'bbb'>
[&yatt:z;|&yatt:w;]
</yatt:dobody>

<!yatt:widget dobody x y body=[code z w]>
{<yatt:body z="a(&yatt:x;)" w="b(&yatt:y;)"/>}
END
    is my $pos_p = $yatt->find_product(perl => $pos_t), "MyTest_lite_${i}::EntNS::$SUB"
      , "$theme find_product $SUB ";
    eq_or_diff captured($pos_p => render_ => ())
      , <<'END', "$theme $SUB render_";
{[a(AAA)|b(bbb)]}

END
  }

  {
    my $SUB = 'elematt';
    ok(my $pos_t = $yatt->add_to($SUB => <<'END'), "$theme add_to $SUB");
<yatt:elematt>
<:yatt:title>TITLE</:yatt:title>
BODY
<:yatt:header/>
HEADER
<:yatt:footer/>
FOOTER
</yatt:elematt>

<!yatt:widget elematt title header footer>
<head>
&yatt:header;
<title>&yatt:title;</title>
</head>
<body>
<h2>&yatt:title;</h2>
<div id=main>
<yatt:body/>
</div>
&yatt:footer;
</body>
END
    is my $pos_p = $yatt->find_product(perl => $pos_t), "MyTest_lite_${i}::EntNS::$SUB"
    , "$theme find_product $SUB ";
    eq_or_diff captured($pos_p => render_ => ())
      , <<'END', "$theme $SUB render_";
<head>

HEADER

<title>TITLE</title>
</head>
<body>
<h2>TITLE</h2>
<div id=main>
BODY</div>

FOOTER

</body>

END

  }

  {
    my $SUB = 'dodelegate';
    ok(my $pos_t = $yatt->add_to(dodelegate => <<'END'), "$theme add_to $SUB");
<!yatt:args foo bar>
<yatt:main x="X&yatt:foo;" y="&yatt:foo;Y" z="Z&yatt:bar;"
  w="&yatt:foo;W&yatt:bar;"/>

<!yatt:widget base1 x y>
[&yatt:x;;&yatt:y;]

<!yatt:widget base2 z w>
(&yatt:z;|&yatt:w;)

<!yatt:widget main base1=[delegate] bar=[delegate:base2] >
<yatt:base1/>
<yatt:bar/>
END
    is my $pos_p = $yatt->find_product(perl => $pos_t), "MyTest_lite_${i}::EntNS::$SUB"
      , "$theme find_product $SUB ";
    eq_or_diff captured($pos_p => render_ => qw(FOO Bar))
      , <<'END', "$theme $SUB render_";
[XFOO;FOOY]
(ZBar|FOOWBar)


END
  }

  {
    my $SUB = 'error';
    ok($yatt->add_to(error => <<'END'), "$theme add_to $SUB");
<!yatt:args error>
<h2>&yatt:error:reason();</h2>
file: &yatt:error{cf_tmpl_file};<br>
line: &yatt:error{cf_tmpl_line};<br>
perl file: &yatt:error{cf_file};<br>
perl line: &yatt:error{cf_line};<br>
END

require_ok("YATT::Lite::Error");

eq_or_diff captured($yatt->find_product(perl => $yatt->find_file('error')) =>
		    render_ => YATT::Lite::Error->new
		    (format => "test error %s"
		     , args => ['foo']
		     , tmpl_file => '(mem)'
		     , tmpl_line => 1
		     , file => 'lite.t'
		     , line => 100))
      , <<'END', "$theme $SUB error page direct.";
<h2>test error foo</h2>
file: (mem)<br>
line: 1<br>
perl file: lite.t<br>
perl line: 100<br>
END

    # 前半 3 行だけ一致すればいい。
    sub lines {
      my ($num, $string) = @_;
      my @lines = split /\n/, $string, $num+1;
      join("\n", map {defined $_ ? $_ : ""} @lines[0 .. $num-1])."\n";
    }

    my $eh = sub {
      my ($type, $err) = @_;
      # $type eq 'error'
      die captured($yatt->find_product(perl => $yatt->find_file($type))
		   , render_ => $err);
    };
    eq_or_diff lines(3, catch {
      cf_let {$yatt} [error_handler => $eh], sub {
	$yatt->add_to(synerr => q{<!yatt:foo>});
      };
    }), <<END, "$theme $SUB syntax error is handled by error page";
<h2>Unknown declarator (&lt;!yatt:foo &gt;)</h2>
file: synerr<br>
line: 1<br>
END

    eq_or_diff lines(3, catch {
      cf_let {$yatt} [error_handler => $eh], sub {
	$yatt->find_product(perl => $yatt->add_to(cgenerr => q{&yatt:foo;}));
      };
    }), <<END, "$theme $SUB cgen error is handled by error page";
<h2>No such variable &#39;foo&#39;</h2>
file: cgenerr<br>
line: 1<br>
END

  }
}

{
  my $theme = "[single string template]";

  my $yatt = new YATT::Lite(app_ns => myapp(++$i)
			    , vfs => [data => <<END, public => 1]
<!yatt:args x y>
<h2>&yatt:x;</h2>
<yatt:bar y/>

<!yatt:widget bar y>
(&yatt:y;)
END
			    , debug_cgen => $ENV{DEBUG});

  eq_or_diff $yatt->render('' => ['A', 'B']), <<END
<h2>A</h2>
(B)

END
    , "$theme find_renderer foo";
}
