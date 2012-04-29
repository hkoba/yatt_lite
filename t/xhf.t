#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/lib");

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
sub read_times {
  my ($num, $input, @opts) = @_;
  my $parser = parser($input, @opts);
  my @result;
  while ($num-- > 0) {
    push @result, [$parser->read];
  }
  \@result;
}
require_ok($CLASS);

{
  test_parser [parser(<<END)->read]
foo: 1
bar: 2
baz: 3
END
    , [foo => 1, bar => 2, baz => 3];

  test_parser [parser(<<END)->read]
- foo
- bar
= #undef
- baz
END
    , [qw(foo bar), undef, 'baz'];

  test_parser [parser(<<END)->read]
# -*- mode: xhf; coding: utf-8 -*-
foo: after comment
bar: 2
baz: before next chunk.
qux= #null

next: not read.
END
    , [foo => "after comment", bar => 2, baz => "before next chunk."
      , qux => undef];

  test_parser [parser(<<END)->read]
foo: 1
bar: 
 2
baz:
 3
END
    , [foo => 1, bar => 2, baz => "3\n"];

  test_parser [parser(<<END)->read]
foo: 1
bar/bar: 2
baz.html: 3
bang-4: 4
END
    , ["foo" => 1, "bar/bar" => 2, "baz.html" => 3, "bang-4" => 4];

  test_parser read_times(2, <<END)
foo:   1   
bar:
 
 2
baz: 
 3


x: 1
y: 2

END
    , [[foo => 1, bar => "\n2\n", baz => 3], [x => 1, y => 2]];

  test_parser [parser(<<END)->read]
foo: 1
bar{
x: 2.1
y: 2.2
}
baz: 3
END
    , [foo => 1, bar => {x => 2.1, y => 2.2}, baz => 3];

  test_parser [parser(<<END)->read]
{
foo: 1
bar: 2
}
END
    , [{foo => 1, bar => 2}];

  test_parser [parser(<<END)->read]
{
foo: 1
bar: 2
: 3
- ba z
= #null
}
{
- 
= #null
}
[
= #null
- baz
- bang
]
END
    , [{foo => 1, bar => 2, '' => 3, 'ba z' => undef}
       , {'' => undef}
       , [undef, 'baz', 'bang']];

  test_parser [parser(<<END)->read]
{
- foo bar
- baz
qux: quux
}
END
    , [{"foo bar" => "baz", qux => "quux"}];


  test_parser [parser(<<END)->read]
foo: 1
bar[
: 2.1
, 2.2
- 2.3
]
baz: 3
END
    , [foo => 1, bar => [2.1, 2.2, 2.3], baz => 3];

  test_parser [parser(<<END)->read]
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
    , [foo => 1
       , bar => [2.1, {hoe => "2.1.1\n", moe => "2.1.2"}, 2.3]
       , baz => 3];

  test_parser [parser(<<END)->read]
#foo
#bar
foo: 1
bar: 
 2
# baz (needs space)
baz:
 3
END
    , [foo => 1, bar => 2, baz => "3\n"];

}