#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test::More;
use YATT::Lite::Test::TestUtil;

use YATT::Lite::Util qw(catch);
use YATT::Lite::Constants;

use Test::Differences;
use YATT::Lite::XHF::Dumper;
use YATT::Lite::LRXML::AltTree;
sub alt_tree_for {
  my ($string, $tree) = @_;
  YATT::Lite::LRXML::AltTree->new(string => $string)->convert_tree($tree);
}
sub alt_tree_xhf_for {
  YATT::Lite::XHF::Dumper->dump_strict_xhf(alt_tree_for(@_))."\n";
}


my $CLASS = 'YATT::Lite::LRXML';
use_ok($CLASS);

# XXX: Node の内部表現は、本当はまだ固まってない。大幅変更の余地が有る
# ただ、それでも parse 結果もテストしておかないと、余計な心配が増えるので。

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

    # print STDERR alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), "\n"; exit;
    
    eq_or_diff alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), <<'END';
[
-
 FOO
 
{
attlist[
{
kind: TYPE_ATTRIBUTE
path: x
source: x
value= #null
}
{
kind: TYPE_ATTRIBUTE
path: y
source: y
value= #null
}
]
kind: TYPE_ELEMENT
path[
yatt: foo
]
source: <yatt:foo x y>
 bar
 </yatt:foo>
subtree[
-
 
 
- bar
-
 
 
]
}
-
 
 BAZ
-
 
 
]
END

  # XXX: to be removed
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
], "nodetree $name" if 0;
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

    # print STDERR alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), "\n";

    eq_or_diff alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), <<'END';
[
- <h2>
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:x;
subtree[
var: x
]
}
-
 </h2>
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:y;
subtree[
var: y
]
}
-
 
 
]
END

    # XXX: to be removed
    is_deeply $w->{tree}, [
'<h2>', [TYPE_ENTITY, 90, 98, 9, 'yatt', [var => 'x']], '</h2>
', [TYPE_ENTITY, 104, 112, 10, 'yatt', [var => 'y']], '
'], "nodetree $name" if 0;
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

    # print STDERR alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), "\n";exit;

    eq_or_diff alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), <<'END';
[
-
 FOO
 
{
kind: TYPE_COMMENT
path: yatt
source: <!--#yatt 1 -->
value: 1
}
{
kind: TYPE_PI
path[
- yatt
]
source: <?yatt A ?>
value:
  A 
}
-
 
 
{
attlist[
{
kind: TYPE_ATTRIBUTE
path: x
source: x
value= #null
}
{
kind: TYPE_ATTRIBUTE
path: y
source: y
value= #null
}
]
kind: TYPE_ELEMENT
path[
yatt: foo
]
source: <yatt:foo x y>
  <!--#yatt 2 -->
   <yatt:bar x y/>
 <!--#yatt 3 -->
 </yatt:foo>
subtree[
-
 
 
-
 
{
kind: TYPE_COMMENT
path: yatt
source: <!--#yatt 2 -->
value: 2
}
-
   
{
kind: TYPE_ELEMENT
path[
yatt: bar
]
source: <yatt:bar x y/>
value= #null
}
-
 
 
{
kind: TYPE_COMMENT
path: yatt
source: <!--#yatt 3 -->
value: 3
}
]
}
-
 
 BAZ
 
{
kind: TYPE_COMMENT
path: yatt
source: <!--#yatt 4 -->
value: 4
}
{
kind: TYPE_PI
path[
- yatt
]
source: <?yatt B ?>
value:
  B 
}
-
 
 
]
END

    # XXX: to be removed
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
, "nodetree $name" if 0;
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

    # print STDERR alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), "\n";exit;
    eq_or_diff alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), <<'END';
[
-
 FOO
 
{
kind: TYPE_COMMENT
path: yatt
source: <!--#yatt 1 -->
value: 1
}
{
kind: TYPE_PI
path[
- yatt
]
source: <?yatt A ?>
value:
  A 
}
-
 
 
{
attlist[
{
kind: TYPE_ATTRIBUTE
path: x
source: x
value= #null
}
{
kind: TYPE_ATTRIBUTE
path: y
source: y
value= #null
}
]
kind: TYPE_ELEMENT
path[
yatt: foo
]
source: <yatt:foo x y>
  <!--#yatt 2 -->
   <yatt:bar x y/>
 <!--#yatt 3 -->
 </yatt:foo>
subtree[
-
 
 
-
  
{
kind: TYPE_COMMENT
path: yatt
source: <!--#yatt 2 -->
value: 2
}
-
   
{
kind: TYPE_ELEMENT
path[
yatt: bar
]
source: <yatt:bar x y/>
value= #null
}
-
 
 
{
kind: TYPE_COMMENT
path: yatt
source: <!--#yatt 3 -->
value: 3
}
]
}
-
 
 BAZ
 
{
kind: TYPE_COMMENT
path: yatt
source: <!--#yatt 4 -->
value: 4
}
{
kind: TYPE_PI
path[
- yatt
]
source: <?yatt B ?>
value:
  B 
}
-
 
 
]
END

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
], "nodetree $name" if 0;
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
    # print STDERR alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), "\n";exit;

    eq_or_diff alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), <<'END';
[
-
 <h2>Hello</h2>
 
{
attlist[
{
kind: TYPE_ATT_TEXT
path= #null
source: "not defined &yatt:x;"
subtree[
-
 not defined 
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:x;
subtree[
var: x
]
}
]
}
]
foot[
{
attlist[
{
kind: TYPE_ATT_TEXT
path: if
source: if="&yatt:x; >= 2"
subtree[
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:x;
subtree[
var: x
]
}
-
  >= 2
]
}
]
kind: TYPE_ATT_NESTED
path[
yatt: else
]
source:
 <:yatt:else if="&yatt:x; >= 2"/> world!
 
subtree[
-
  world!
 
]
}
{
kind: TYPE_ATT_NESTED
path[
yatt: else
]
source:
 <:yatt:else/> decades!
 
subtree[
-
  decades!
-
 
 
]
}
]
kind: TYPE_ELEMENT
path[
yatt: if
]
source: <yatt:if "not defined &yatt:x;"> space!
 <:yatt:else if="&yatt:x; >= 2"/> world!
 <:yatt:else/> decades!
 </yatt:if>
subtree[
-
  space!
 
]
}
-
 
 
]
END

    # XXX:
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
'], "[Inline attelem bug] nodetree $name" if 0;
  }
}

{
  my $tmpl = $CLASS->Template->new;
  $CLASS->load_string_into($tmpl, my $cp = <<END, all => 1);
<!yatt:args>
<yatt:foo a='
' b="
" />
<?perl===undef?>
<!yatt:widget foo a b >
END

  my $name = '';
  is ref (my $w = $tmpl->{Item}{$name}), 'YATT::Lite::Core::Widget'
    , "tmpl Item '$name'";

  {
    # print STDERR alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), "\n";exit;

    eq_or_diff alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), <<'END';
[
{
attlist[
{
kind: TYPE_ATT_TEXT
path: a
source: a='
 '
value:
 
 
}
{
kind: TYPE_ATT_TEXT
path: b
source: b="
 "
value:
 
 
}
]
kind: TYPE_ELEMENT
path[
yatt: foo
]
source: <yatt:foo a='
 ' b="
 " />
value= #null
}
-
 
 
{
kind: TYPE_PI
path[
- perl
]
source: <?perl===undef?>
value: ===undef
}
-
 
 
]
END

    is_deeply $w->{tree}
, [[TYPE_ELEMENT, 13, 37, 2, [qw(yatt foo)], undef
   , [[TYPE_ATT_TEXT, 23, 28, 2, 'a', '
'], [TYPE_ATT_TEXT, 29, 34, 3, 'b', '
']]
   , undef, undef, 38]
   , '
', [TYPE_PI, 38, 54, 5, ['perl'], '===undef']
 , '
'
   ]
   , "[long widget call bug] nodetree $name" if 0;
  }
}

{
  my $tmpl = $CLASS->Template->new;
  $CLASS->load_string_into($tmpl, my $cp = <<END, all => 1);
<yatt:foo

--  foo ---

/>
<?perl===undef?>
END

  my $name = '';
  is ref (my $w = $tmpl->{Item}{$name}), 'YATT::Lite::Core::Widget'
    , "tmpl Item '$name'";

  {
    # print STDERR alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), "\n";

    eq_or_diff alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), <<'END';
[
{
kind: TYPE_ELEMENT
path[
yatt: foo
]
source: <yatt:foo
 
 --  foo ---
 
 />
value= #null
}
-
 
 
{
kind: TYPE_PI
path[
- perl
]
source: <?perl===undef?>
value: ===undef
}
-
 
 
]
END

    is_deeply $w->{tree}
, [[TYPE_ELEMENT, 0, 26, 1, [qw(yatt foo)], undef, undef, undef, undef, 27]
, '
', [TYPE_PI, 27, 43, 6, ['perl'], '===undef']
, '
'
], "newline and comment in call." if 0;
}
}

{
  my $tmpl = $CLASS->Template->new;
  $CLASS->load_string_into($tmpl, my $cp = <<END, all => 1);
<yatt:foo>
<yatt:bar>
&yatt:x;
</yatt:bar>
</yatt:foo>

<!yatt:widget foo>
<yatt:body/>
<!yatt:widget bar body = [code x=html]>
<yatt:body/>
END

  my $name = '';
  is ref (my $w = $tmpl->{Item}{$name}), 'YATT::Lite::Core::Widget'
    , "tmpl Item '$name'";

  # print STDERR alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), "\n";

  eq_or_diff alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), <<'END';
[
{
kind: TYPE_ELEMENT
path[
yatt: foo
]
source: <yatt:foo>
 <yatt:bar>
 &yatt:x;
 </yatt:bar>
 </yatt:foo>
subtree[
-
 
 
{
kind: TYPE_ELEMENT
path[
yatt: bar
]
source: <yatt:bar>
 &yatt:x;
 </yatt:bar>
subtree[
-
 
 
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:x;
subtree[
var: x
]
}
- 
-
 
 
]
}
- 
-
 
 
]
}
-
 
 
]
END

  is_deeply $w->{tree}
, [[TYPE_ELEMENT, 0, 10, 1, [qw(yatt foo)]
    , [TYPE_ATTRIBUTE, undef, undef, 1, body => ['
', [TYPE_ELEMENT, 11, 21, 2, [qw(yatt bar)]
      , [TYPE_ATTRIBUTE, undef, undef, 2, body => ['
', [TYPE_ENTITY, 22, 30, 3, yatt => [qw(var x)]], '', '
']]
      , undef, undef, undef, 22, 30], '', '
']]
    , undef, undef, undef, 11, 42], '
'
], "var in nested body." if 0;
}

{
  my $tmpl = $CLASS->Template->new;
  $CLASS->load_string_into($tmpl, my $cp = <<END, all => 1);
<yatt:my [code:code src:source]>
  <h2>&yatt:x;</h2>
  &yatt:y;
</yatt:my>
END

  my $name = '';
  is ref (my $w = $tmpl->{Item}{$name}), 'YATT::Lite::Core::Widget'
    , "tmpl Item '$name'";

  #print STDERR alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), "\n";exit;

  eq_or_diff alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), <<'END';
[
{
attlist[
{
kind: TYPE_ATT_NESTED
path= #null
source: [code:code src:source]
subtree[
{
kind: TYPE_ATTRIBUTE
path[
code: code
]
source: code:code
value= #null
}
{
kind: TYPE_ATTRIBUTE
path[
src: source
]
source: src:source
value= #null
}
]
}
]
kind: TYPE_ELEMENT
path[
yatt: my
]
source: <yatt:my [code:code src:source]>
   <h2>&yatt:x;</h2>
   &yatt:y;
 </yatt:my>
subtree[
-
 
 
-
   <h2>
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:x;
subtree[
var: x
]
}
-
 </h2>
 
-
   
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:y;
subtree[
var: y
]
}
- 
-
 
 
]
}
-
 
 
]
END

  # print "# ", YATT::Lite::Util::terse_dump($w->{tree}), "\n";
  is_deeply $w->{tree}
    , [[5,0,32,1
        , ['yatt','my']
        , [6,undef,undef,1,'body'
           , ['
','  <h2>'
              , [3,39,47,2,'yatt',['var','x']],'</h2>
','  '
              , [3,55,63,3,'yatt',['var','y']],'','
']]
        , [[9,9,31,1,undef
            ,[6,10,19,1,['code','code']]
            ,[6,20,30,1,['src','source']]
          ]]
        , undef,undef,33,63]
       ,'
'] if 0;

}

if (1) {
  my $tmpl = $CLASS->Template->new;
  $CLASS->load_string_into($tmpl, my $cp = <<END, all => 1);
<h2>&yatt[[;Hello &yatt:world;!&yatt]];</h2>

<p>&yatt#num[[;
  &yatt:n; file removed from directory &yatt:dir;
&yatt||;
  &yatt:n; files removed from directory &yatt:dir;
&yatt]];</p>
END

  my $name = '';
  is ref (my $w = $tmpl->{Item}{$name}), 'YATT::Lite::Core::Widget'
    , "tmpl Item '$name'";

  # print STDERR alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), "\n";

  eq_or_diff alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), <<'END';
[
- <h2>
{
kind: TYPE_LCMSG
path[
- yatt
]
source: &yatt[[;Hello &yatt:world;!&yatt]];
subtree[
-
 Hello 
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:world;
subtree[
var: world
]
}
- !
]
}
-
 </h2>
 
-
 
 
- <p>
{
kind: TYPE_LCMSG
path[
yatt: num
]
source: &yatt#num[[;
   &yatt:n; file removed from directory &yatt:dir;
 &yatt||;
   &yatt:n; files removed from directory &yatt:dir;
 &yatt]];
subtree[
-
 
 
-
   
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:n;
subtree[
var: n
]
}
-
  file removed from directory 
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:dir;
subtree[
var: dir
]
}
-
 
 
]
}
- </p>
-
 
 
]
END


  is_deeply $w->{tree}
, ['<h2>'
   , [TYPE_LCMSG, 4, 39, 1, [qw(yatt)]
      , [["Hello "
	 , [TYPE_ENTITY, 18, 30, 1, yatt => [qw/var world/]]
	 , "!"
	]]]
   , "</h2>\n"
   , "\n"
   , "<p>"
   , [TYPE_LCMSG, 49, 180, 3, [qw(yatt num)]
      , [["\n", "  "
	  , [TYPE_ENTITY, 64, 72, 4, yatt => [qw/var n/]]
	  , " file removed from directory "
	  , [TYPE_ENTITY, 101, 111, 4, yatt => [qw/var dir/]]
	  , "\n"
	 ]
	 , ["\n", "  "
	  , [TYPE_ENTITY, 123, 131, 6, yatt => [qw/var n/]]
	  , " files removed from directory "
	  , [TYPE_ENTITY, 161, 171, 6, yatt => [qw/var dir/]]
	  , "\n"
	 ]
	]
     ]
   , "</p>"
   , "\n"
], "Embeded l10n message." if 0;
}

{
  my $tmpl = $CLASS->Template->new;
  $CLASS->load_string_into($tmpl, my $cp = <<END, all => 1);
<yatt:my [x y :::z]="1..8" />
x=&yatt:x;
y=&yatt:y;
z=&yatt:z;
END

  my $name = '';
  is ref (my $w = $tmpl->{Item}{$name}), 'YATT::Lite::Core::Widget'
    , "tmpl Item '$name'";

  # print STDERR alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), "\n";

  eq_or_diff alt_tree_xhf_for($tmpl->{cf_string}, $w->{tree}), <<'END';
[
{
attlist[
{
kind: TYPE_ATT_TEXT
path[
{
kind: TYPE_ATTRIBUTE
path: x
source: x
value= #null
}
{
kind: TYPE_ATTRIBUTE
path: y
source: y
value= #null
}
{
kind: TYPE_ATTRIBUTE
path[
- 
- 
- 
- z
]
source: :::z
 x=
value= #null
}
]
source: [x y :::z]="1..8"
value: 1..8
}
]
kind: TYPE_ELEMENT
path[
yatt: my
]
source: <yatt:my [x y :::z]="1..8" />
value= #null
}
-
 
 
- x=
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:x;
subtree[
var: x
]
}
-
 
 
- y=
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:y;
subtree[
var: y
]
}
-
 
 
- z=
{
kind: TYPE_ENTITY
path: yatt
source: &yatt:z;
subtree[
var: z
]
}
-
 
 
]
END

  is_deeply $w->{tree}
    , [[5,0,29,1
        , ['yatt','my']
        , undef
        , [[[8,18,26,1
           , [[6,10,11,1,'x']
              , [6,12,13,1,'y']
              , [6,14,18,1, ['','','','z']]]
           , '1..8']]]
        ,undef,undef,30]
       , "\n"
       , 'x=',[3,32,40,2,'yatt',['var','x']],"\n"
       , 'y=',[3,43,51,3,'yatt',['var','y']],"\n"
       , 'z=',[3,54,62,4,'yatt',['var','z']],"\n"] if 0;

}

# (- (region-end) (region-beginning))
#
done_testing();
