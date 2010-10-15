#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/..");

#========================================
use Test::More qw(no_plan);
use Data::Dumper;

my $CLASS = 'YATT::Lite::XHF';

sub parser {
  my $input = shift;
  $CLASS->new(string => $input, @_);
}
sub test_parser ($$;$) {
  my ($result, $struct, $theme) = @_;
  is_deeply $result, $struct
    , join " ", grep {defined} $theme
      , Data::Dumper->new([$struct])->Terse(1)->Indent(0)->Dump;
}
require_ok($CLASS);

{
  test_parser [parser(<<END)->read], [foo => 1, bar => 2, baz => "3\n"]
foo: 1
bar: 
 2
baz:
 3
END
    ;

  test_parser [parser(<<END)->read], ["foo" => 1, "bar/bar" => 2, "baz.html" => 3, "bang-4" => 4]
foo: 1
bar/bar: 2
baz.html: 3
bang-4: 4
END
      ;

  my $parser;
  test_parser [do {$parser = parser(<<END); ([$parser->read], [$parser->read])}], [[foo => 1, bar => "\n2\n", baz => 3], [x => 1, y => 2]]
foo:   1   
bar:
 
 2
baz: 
 3


x: 1
y: 2

END
      ;

  test_parser [parser(<<END)->read], [foo => 1, bar => {x => 2.1, y => 2.2}, baz => 3]
foo: 1
bar{
x: 2.1
y: 2.2
}
baz: 3
END
      ;

  test_parser [parser(<<END)->read], [foo => 1, bar => [2.1, 2.2, 2.3], baz => 3]
foo: 1
bar[
: 2.1
, 2.2
- 2.3
]
baz: 3
END
      ;

  test_parser [parser(<<END)->read], [foo => 1, bar => [2.1, {hoe => "2.1.1\n", moe => "2.1.2"}, 2.3], baz => 3]
foo: 1
bar[
: 2.1
{
hoe:
 2.1.1
moe:   2.1.2
}
: 2.3
]
baz: 3
END
      ;

  test_parser [parser(<<END)->read], [foo => 1, bar => 2, baz => "3\n"]
#foo
#bar
foo: 1
bar: 
 2
# baz (needs space)
baz:
 3
END
      ;

}
