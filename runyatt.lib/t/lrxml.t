#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/..");
use Test::More qw(no_plan);
use Test::Differences;

use YATT::Lite::Util qw(catch);
use YATT::Lite::Constants;
sub MY () {__PACKAGE__}

my $CLASS = 'YATT::Lite::LRXML';
use_ok($CLASS);

{
  my $parser = $CLASS->new(all => 1);
  my $tmpl = $CLASS->Template->new;
  $parser->load_string_into($tmpl, my $cp = <<END);
<!yatt:widget bar x y>
FOO
<yatt:foo x y>
bar
</yatt:foo>
BAZ

<!yatt:widget foo x y>
<h2>&yatt:x;</h2>
&yatt:y;
END


  {
    my $name = 'bar';
    is ref (my $w = $tmpl->{Item}{$name}), 'YATT::Lite::Core::Widget'
      , "tmpl Item '$name'";
    eq_or_diff $tmpl->source_region
      ($w->{cf_startpos}, $w->{cf_bodypos})
	, qq{<!yatt:widget bar x y>\n}, "part $name source_range decl";

    eq_or_diff $tmpl->source_substr($w->{cf_bodypos}, $w->{cf_bodylen})
      , q{FOO
<yatt:foo x y>
bar
</yatt:foo>
BAZ

}, "part $name source_range body";

    my $i = -1;
    is $w->{tree}[++$i], "FOO\n", "render_$name node $i";
    is_deeply $tmpl->node_source($w->{tree}[++$i])
      , '<yatt:foo x y>', "render_$name node $i";
    is $w->{tree}[++$i], "\nBAZ", "render_$name node $i"; # XXX \n が嬉しくない

    is_deeply $w->{tree}, [
'FOO
', [TYPE_ELEMENT, 27, 41, 3, [qw(yatt foo)]
, [TYPE_ATTRIBUTE, undef, undef, 3, body => [
'
', 'bar', '
'
]], [[TYPE_ATTRIBUTE, 37, 38, 3, 'x'], [TYPE_ATTRIBUTE, 39, 40, 3, 'y']]
, undef, undef, 42, 45]
, '
BAZ', '
'
], "nodetree $name";
  }

  {
    my $name = 'foo';
    is ref (my $w = $tmpl->{Item}{$name}), 'YATT::Lite::Core::Widget'
      , "tmpl Item '$name'";
    eq_or_diff $tmpl->source_region
      ($w->{cf_startpos}, $w->{cf_bodypos})
	, qq{<!yatt:widget foo x y>\n}, "part $name source_range decl";

    eq_or_diff $tmpl->source_substr($w->{cf_bodypos}, $w->{cf_bodylen})
      , q{<h2>&yatt:x;</h2>
&yatt:y;
}, "part $name source_range body";

    my $i = -1;
    is $w->{tree}[++$i], "<h2>", "render_$name node $i";
    is_deeply $tmpl->node_source($w->{tree}[++$i])
      , '&yatt:x;', "render_$name node $i";
    is $w->{tree}[++$i], "</h2>\n", "render_$name node $i";
    is_deeply $tmpl->node_source($w->{tree}[++$i])
      , '&yatt:y;', "render_$name node $i";

    is_deeply $w->{tree}, [
'<h2>', [TYPE_ENTITY, 90, 98, 9, 'yatt', [var => 'x']], '</h2>
', [TYPE_ENTITY, 104, 112, 10, 'yatt', [var => 'y']], '
'], "nodetree $name";
  }
}

{
  my $tmpl = $CLASS->Template->new;
  $CLASS->load_string_into($tmpl, my $cp = <<END, all => 1);
<!yatt:args x=list y="scalar?0">
FOO
<!--#yatt 1 -->
<?yatt A ?>
<yatt:foo x y>
 <!--#yatt 2 -->
  <yatt:bar x y/>
<!--#yatt 3 -->
</yatt:foo>
BAZ
<!--#yatt 4 -->
<?yatt B ?>


<!yatt:widget foo x=list y="scalar?0">
FOO
<!--#yatt 1 -->
<?yatt A ?>
<yatt:foo x y>
 <!--#yatt 2 -->
  <yatt:bar x y/>
<!--#yatt 3 -->
</yatt:foo>
BAZ
<!--#yatt 4 -->
<?yatt B ?>
END

  {
    my $name = '';
    is ref (my $w = $tmpl->{Item}{$name}), 'YATT::Lite::Core::Widget'
      , "tmpl Item '$name'";
    eq_or_diff $tmpl->source_region
      ($w->{cf_startpos}, $w->{cf_bodypos})
	, qq{<!yatt:args x=list y="scalar?0">\n}, "part $name source_range decl";

    eq_or_diff $tmpl->source_substr($w->{cf_bodypos}, $w->{cf_bodylen})
      , q{FOO
<!--#yatt 1 -->
<?yatt A ?>
<yatt:foo x y>
 <!--#yatt 2 -->
  <yatt:bar x y/>
<!--#yatt 3 -->
</yatt:foo>
BAZ
<!--#yatt 4 -->
<?yatt B ?>


}, "part $name source_range body";

    my @test
      = ([2, q|<?yatt A ?>|]
	 , [4, q|<yatt:foo x y>|]
	 , [7, q|<?yatt B ?>|]
	);

    foreach my $test (@test) {
      my ($i, $want) = @$test;
      is $tmpl->node_source($w->{tree}[$i]), $want
	, "render_$name node $i ($want)";
    }

    is_deeply $w->{tree}, [
'FOO
', [TYPE_COMMENT, 37, 53, 3, yatt => 1, ' 1 ']
, [TYPE_PI, 53, 64, 4, ['yatt'], ' A ']
, '
', [TYPE_ELEMENT, 65, 79, 5, [qw(yatt foo)]
, [TYPE_ATTRIBUTE, undef, undef, 7, body => [
'
', ' ', [TYPE_COMMENT, 81, 97, 6, yatt => 1, ' 2 '], '  '
, [TYPE_ELEMENT, 99, 114, 7, [qw(yatt bar)], undef
, [[TYPE_ATTRIBUTE, 109, 110, 7, 'x'],[TYPE_ATTRIBUTE, 111, 112, 7, 'y']]
, undef, undef, 115
], '
', [TYPE_COMMENT, 115, 131, 8, yatt => 1, ' 3 ']
]]
, [[TYPE_ATTRIBUTE, 75, 76, 5, 'x'], [TYPE_ATTRIBUTE, 77, 78, 5, 'y']]
, undef, undef, 80, 130]
, '
BAZ
'
, [TYPE_COMMENT, 147, 163, 11, yatt => 1, ' 4 ']
, [TYPE_PI,      163, 174, 12, ['yatt'], ' B ']
, '
'
]
, "nodetree $name";
  }

  {
    my $name = 'foo';
    is ref (my $w = $tmpl->{Item}{$name}), 'YATT::Lite::Core::Widget'
      , "tmpl Item '$name'";
    eq_or_diff $tmpl->source_region
      ($w->{cf_startpos}, $w->{cf_bodypos})
	, qq{<!yatt:widget foo x=list y="scalar?0">\n}, "part $name source_range decl";

    eq_or_diff $tmpl->source_substr($w->{cf_bodypos}, $w->{cf_bodylen})
      , q{FOO
<!--#yatt 1 -->
<?yatt A ?>
<yatt:foo x y>
 <!--#yatt 2 -->
  <yatt:bar x y/>
<!--#yatt 3 -->
</yatt:foo>
BAZ
<!--#yatt 4 -->
<?yatt B ?>
}, "part $name source_range body";

    my @test
      = ([2, q|<?yatt A ?>|]
	 , [4, q|<yatt:foo x y>|]
	 , [7, q|<?yatt B ?>|]
	);

    foreach my $test (@test) {
      my ($i, $want) = @$test;
      is $tmpl->node_source($w->{tree}[$i]), $want
	, "render_$name node $i ($want)";
    }

    is_deeply $w->{tree}, [
'FOO
', [TYPE_COMMENT, 220, 236, 17, yatt => 1, ' 1 ']
, [TYPE_PI, 236, 247, 18, ['yatt'], ' A ']
, '
', [TYPE_ELEMENT, 248, 262, 19, [qw(yatt foo)]
, [TYPE_ATTRIBUTE, undef, undef, 21, body => [
'
', ' ', [TYPE_COMMENT, 264, 280, 20, yatt => 1, ' 2 ']
, '  ', [TYPE_ELEMENT, 282, 297, 21, [qw(yatt bar)], undef
, [[TYPE_ATTRIBUTE, 292, 293, 21, 'x'], [TYPE_ATTRIBUTE, 294, 295, 21, 'y']]
, undef, undef, 298]
, '
', [TYPE_COMMENT, 298, 314, 22, yatt => 1, ' 3 ']
]]
, [[TYPE_ATTRIBUTE, 258, 259, 19, 'x']
, [TYPE_ATTRIBUTE, 260, 261, 19, 'y']]
, undef, undef, 263, 313
]
, '
BAZ
', [TYPE_COMMENT, 330, 346, 25, 'yatt', 1, ' 4 ']
, [TYPE_PI, 346, 357, 26, ['yatt'], ' B ']
, '
'
], "nodetree $name";
  }
}

{
  my $tmpl = $CLASS->Template->new;
  $CLASS->load_string_into($tmpl, my $cp = <<END, all => 1);
<!yatt:args x>
<h2>Hello</h2>
<yatt:if "not defined &yatt:x;"> space!
<:yatt:else if="&yatt:x; >= 2"/> world!
<:yatt:else/> decades!
</yatt:if>
END

  my $name = '';
  is ref (my $w = $tmpl->{Item}{$name}), 'YATT::Lite::Core::Widget'
    , "tmpl Item '$name'";

  {
    is_deeply $w->{tree}
, ['<h2>Hello</h2>
', [TYPE_ELEMENT, 30, 62, 3, [qw(yatt if)]
    #------:body
    , [TYPE_ATTRIBUTE, undef, undef, 3, body => [" space!\n"]]
    #------:attlist
    , [[TYPE_ATT_TEXT, 39, 61, 3, undef
	, ['not defined '
	   , [TYPE_ENTITY, 73, 20, 3, yatt => [qw(var x)]]
	  ]]]
    #------:head
    , undef
    #------:foot
    , [[TYPE_ATT_NESTED, 70, 102, 4, [qw(yatt else)]
	, [" world!\n"]
	, [[TYPE_ATT_TEXT, 82, 100, 4
	    , if => [[TYPE_ENTITY, 100, 8, 4, yatt => [qw(var x)]], ' >= 2']]]
	, undef, undef, 102]
       ,  [TYPE_ATT_NESTED, 110, 123, 5, [qw(yatt else)]
	   , [' decades!', "\n"]
	   , undef, undef, undef, 123]]
    #-----:info
    , 62, 132
   ]
   , '
'], "[Inline attelem bug] nodetree $name";
  }
}
