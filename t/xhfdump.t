#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings qw(FATAL all NONFATAL misc);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use Test::More;
use YATT::Lite::Test::TestUtil;
use Data::Dumper;

my $LOADER = 'YATT::Lite::XHF';
my $DUMPER = 'YATT::Lite::XHF::Dumper';

# undef
# 空文字列
# 空白入り文字列

# 入れ子
# 先頭/末尾の、空白/空行

my @tests
  = ([<<END, undef]
= #null
END
     , [<<END, 'foo']
- foo
END
     #
     , [<<END, '' => 'bar']
- 
- bar
END
     , [<<END, undef, 'bar']
= #null
- bar
END
     , [<<END, foo => undef]
foo= #null
END
     , [<<END, '', undef]
- 
= #null
END
     , [<<END, undef, undef]
= #null
= #null
END
     #
     , [<<END, foo => 'bar', baz => 'qux']
foo: bar
baz: qux
END

     , undef
     , [<<END, foo => "bar\nbaz\n"]
foo:
 bar
 baz
END

     , [<<END, foo => "bar\n\n", baz => "qux\n\n\n"]
foo:
 bar
 
baz:
 qux
 
 
END

     , [<<END, "foo bar" => 'baz']
- foo bar
- baz
END

     , [<<END, [qw(foo bar baz)]]
[
- foo
- bar
- baz
]
END

     , [<<END, [foo => undef, 'bar'], baz => undef]
[
- foo
= #null
- bar
]
baz= #null
END
     , [<<END, foo => {bar => 'baz', hoe => 1}, bar => [1..3]]
foo{
bar: baz
hoe: 1
}
bar[
- 1
- 2
- 3
]
END

     , [<<END, [bar => 1, baz => 2], [1..3], [1..3, [4..7]]]
[
bar: 1
baz: 2
]
[
- 1
- 2
- 3
]
[
1: 2
3[
4: 5
6: 7
]
]
END

     , [<<END, {foo => 'bar', '' => 'baz', bang => undef}]
{
- 
- baz
bang= #null
foo: bar
}
END
    );

my @dumponly =
  (
   [<<END, foo => [bless([foo => 1, bar => 2], "ARRAY"), "baz"]]
foo[
[
foo: 1
bar: 2
]
- baz
]
END

  );

my @no_trailing_nl = (
  [<<END, [foo => "bar\n"]]
foo:
 bar
 
END
);

plan tests => 2 + 3*grep(defined $_, @tests) + @dumponly + @no_trailing_nl;

use_ok($LOADER);
use_ok($DUMPER);

sub breakpoint {}

my $T = 0;
foreach my $data (@tests) {
  unless (defined $data) {
    breakpoint();
    next;
  }

  ++$T;

  my ($exp, @data) = @$data;
  my $title = join(", ", Data::Dumper->new(\@data)->Terse(1)->Indent(0)->Dump);
  eq_or_diff my $got = $DUMPER->dump_xhf(@data)."\n", $exp, "<T$T> dump: $title";
  is_deeply [$LOADER->new(string => $got)->read], \@data, "<T$T> read: $title";
  is_deeply [$LOADER->new(string => $exp)->read], \@data, "<T$T> read_exp: $title";
}

my $D = 0;
foreach my $data (@dumponly) {
  ++$D;
  my ($exp, @data) = @$data;
  my $title = join(", ", Data::Dumper->new(\@data)->Terse(1)->Indent(0)->Dump);
  eq_or_diff my $got = $DUMPER->dump_xhf(@data)."\n", $exp, "<D$D> dump: $title";
}

{
  my $O = 0;
  my $test = sub {
    my ($exp, $data) = @_;
    my $title = join(", ", Data::Dumper->new($data)->Terse(1)->Indent(0)->Dump);
    ++$O;
    eq_or_diff $DUMPER->dump_strict_xhf(@$data)."\n", $exp, "<O$O> dump: $title";
  };

  foreach my $t (@no_trailing_nl) {
    $test->(@$t);
  }
}

{
  package ARRAY;
  use overload qw("" stringify);
  sub stringify {
    "faked_string";
  }
}

done_testing();
