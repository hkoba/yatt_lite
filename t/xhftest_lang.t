#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------
# Language specific overrides of XHF tests: FIELD[lang] and ONLY.

use Test::More;

use YATT::Lite::Test::XHFTest qw(Item);
{
  package MyTest;
  use parent -norequire, qw(YATT::Lite::Test::XHFTest);
  use YATT::Lite::MFields qw(YATT_CONFIG YATT_RC);
}

sub load {
  my ($lang, $src) = @_;
  MyTest->load(string => $src, filename_for_error => 'test.xhf'
               , defined $lang ? (lang => $lang) : ());
}

# Fields of each test item, by language.
sub items {
  my ($lang, $src, @fields) = @_;
  [map {
    my Item $item = $_;
    +{map {defined $item->{$_} ? ($_ => $item->{$_}) : ()} @fields}
  } @{load($lang, $src)->{_tests}}];
}

sub error_like {
  my ($lang, $src, $pattern, $title) = @_;
  local $@;
  eval {load($lang, $src)};
  like $@, $pattern, $title;
}

my @EXPECT = qw(OUT ERROR ERROR_BODY);

{
  my $src = <<'END';
# header (empty)

TITLE: bool
IN: <yatt:foo x/>
OUT: 1
OUT[js]: true

IN: plain
OUT: out
ERROR[js]: ^error in js
ERROR_BODY[go][
- body in go
]

IN: all
OUT: out
ERROR: ^err
OUT[go]: out in go
END

  is load(undef, $src)->{lang}, 'perl', "default lang is perl";

  is_deeply items(perl => $src, @EXPECT)
    , [{OUT => 1}, {OUT => 'out'}, {OUT => 'out', ERROR => '^err'}]
    , "perl: subscripted fields of other languages are ignored";

  is_deeply items(js => $src, @EXPECT)
    , [{OUT => 'true'}, {ERROR => '^error in js'}
       , {OUT => 'out', ERROR => '^err'}]
    , "js: OUT[js] overrides OUT, ERROR[js] replaces OUT as a group";

  is_deeply items(go => $src, @EXPECT)
    , [{OUT => 1}, {ERROR_BODY => ['body in go']}, {OUT => 'out in go'}]
    , "go: expectations are replaced as a group";

  is_deeply [map {$_->ntests} @{load(perl => $src)->{_tests}}], [2, 2, 2]
    , "perl: ntests";
  is_deeply [map {$_->ntests} @{load(js => $src)->{_tests}}], [2, 1, 2]
    , "js: ntests follows resolved expectation";

  is_deeply items(js => $src, qw(TITLE _num))
    , [{TITLE => 'bool'}, {TITLE => 'bool', _num => 1}
       , {TITLE => 'bool', _num => 2}]
    , "js: TITLE is inherited after the resolution";
}

{
  my $src = <<'END';
YATT_CONFIG[
- a
- 1
]
YATT_CONFIG[js][
- a
- 2
]
YATT_RC[go]: sub foo {}

IN: x
OUT: x
END

  is_deeply [map {my $t = load($_, $src); [@$t{qw(YATT_CONFIG YATT_RC)}]}
             qw(perl js go)]
    , [[[a => 1], undef], [[a => 2], undef], [[a => 1], 'sub foo {}']]
    , "header: YATT_CONFIG[lang] and YATT_RC[lang]";
}

{
  my $src = <<'END';
# header (empty)

TITLE: perl only
ONLY: perl
IN: <?perl= 1?>
OUT: 1

TITLE: js and go
ONLY:  js   go
IN: x
OUT: x

TITLE: skip and todo
SKIP[js]: not in js
TODO[go]: not yet
TODO: all
REQUIRE[perl]: No::Such::Module
PERL_MINVER[perl]: 5.010
IN: y
OUT: y
END

  my @fields = qw(ONLY _only_skip SKIP TODO REQUIRE PERL_MINVER _realfile);
  is_deeply items(perl => $src, @fields)
    , [{ONLY => 'perl', _realfile => 'f1.yatt'}
       , {ONLY => 'js go', _only_skip => 'ONLY: js go', _realfile => 'f2.yatt'}
       , {TODO => 'all', REQUIRE => ['No::Such::Module'], PERL_MINVER => '5.010'
          , _realfile => 'f3.yatt'}]
    , "perl: ONLY, SKIP, TODO, REQUIRE, PERL_MINVER";

  is_deeply items(js => $src, @fields)
    , [{ONLY => 'perl', _only_skip => 'ONLY: perl', _realfile => 'f1.yatt'}
       , {ONLY => 'js go', _realfile => 'f2.yatt'}
       , {SKIP => 'not in js', TODO => 'all', _realfile => 'f3.yatt'}]
    , "js: ONLY, SKIP[js]. File numbering is same as perl";

  is_deeply items(go => $src, @fields)
    , [{ONLY => 'perl', _only_skip => 'ONLY: perl', _realfile => 'f1.yatt'}
       , {ONLY => 'js go', _realfile => 'f2.yatt'}
       , {TODO => 'not yet', _realfile => 'f3.yatt'}]
    , "go: TODO[go] overrides TODO";

  is_deeply [map {$_->ntests} @{load(js => $src)->{_tests}}], [2, 2, 2]
    , "Items skipped by ONLY are still counted";
}

{
  my $head = "# header\n\nTITLE: t\n";

  error_like perl => "${head}IN: x\nOUT: x\nOUT[ruby]: y\n"
    , qr/^Unknown language 'ruby' in XHF test field 'OUT\[ruby\]' at test\.xhf line 6/
    , "unknown language in subscript";

  error_like perl => "${head}IN: x\nIN[js]: y\nOUT: x\n"
    , qr/^XHF test item field 'IN' can't have language subscript: 'IN\[js\]' at test\.xhf line 5/
    , "IN[js] is an error";

  foreach my $name (qw(PARAM FILE TITLE WIDGET ONLY YATT_CONFIG)) {
    error_like js => "${head}IN: x\nOUT: x\n${name}[perl]: y\n"
      , qr/^XHF test item field '$name' can't have language subscript: '$name\[perl\]' at test\.xhf line 6/
      , "${name}[perl] in item is an error (even for other language)";
  }

  error_like perl => "encoding[js]: utf8\n\nIN: x\nOUT: x\n"
    , qr/^XHF test header field 'encoding' can't have language subscript: 'encoding\[js\]' at test\.xhf line 1/
    , "encoding[js] in header is an error";

  error_like perl => "${head}IN: x\nOUT[]: x\n"
    , qr/^Unknown language '' in XHF test field 'OUT\[\]' at test\.xhf line 5/
    , "empty subscript";

  error_like perl => "${head}IN: x\nOUT[js][go]: x\n"
    , qr/^Invalid subscript in XHF test field 'OUT\[js\]\[go\]' at test\.xhf line 5/
    , "multiple subscripts";

  error_like perl => "${head}IN: x\nOUT: x\nONLY: perl javascript\n"
    , qr/^Unknown language 'javascript' in ONLY at test\.xhf line 6/
    , "unknown language in ONLY";

  error_like perl => "${head}IN: x\nOUT: x\nONLY:\n"
    , qr/^Empty ONLY in XHF test at test\.xhf line 6/
    , "empty ONLY";

  error_like perl => "${head}IN: x\nOUT[js]: x\nOUT:\n a\n b\nOUT[js]: y\n"
    , qr/^Duplicate XHF test field 'OUT\[js\]' at test\.xhf line 9/
    , "duplicate subscripted field";

  error_like ruby => "${head}IN: x\nOUT: x\n"
    , qr/^Unknown language 'ruby' in lang option/
    , "unknown lang option";

  error_like perl => "${head}IN: x\nOUT: x\nOUT: y\n"
    , qr/^Duplicate XHF test field 'OUT' at test\.xhf line 6/
    , "duplicate plain field";

  error_like perl => "${head}IN: x\nOUT: x\n\nTITLE: a\nIN: y\n \nTITLE: b\nIN: z\n"
    , qr/^Duplicate XHF test field 'TITLE' at test\.xhf line 10/
    , "broken paragraph separator is found as duplicate";

  error_like perl => "encoding: utf8\nencoding: utf8\n\nIN: x\nOUT: x\n"
    , qr/^Duplicate XHF test field 'encoding' at test\.xhf line 2/
    , "duplicate header field";
}

{
  # Fields of multiple values: TAG and REQUIRE.
  my $src = <<'END';
# header (empty)

TAG: entity
TAG: var
REQUIRE: A
REQUIRE[
- B
- C
]
REQUIRE[js]: X
REQUIRE[js]: Y
IN: x
OUT: x

TAG: single
IN: y
OUT: y
END

  is_deeply items(perl => $src, qw(TAG REQUIRE))
    , [{TAG => [qw(entity var)], REQUIRE => [qw(A B C)]}, {TAG => ['single']}]
    , "perl: duplicate TAG and REQUIRE are multiple values (always arrays)";

  is_deeply items(js => $src, qw(TAG REQUIRE))
    , [{TAG => [qw(entity var)], REQUIRE => [qw(X Y)]}, {TAG => ['single']}]
    , "js: REQUIRE[js] replaces whole values";
}

done_testing();
