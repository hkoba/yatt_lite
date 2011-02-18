#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/..");

#========================================
use Test::More;
use Test::Differences;
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
: bar
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

     , [<<END, {foo => 'bar', '' => 'baz', bang => undef}]
{
: baz
bang= #null
foo: bar
}
END
    );

plan tests => 2 + 3*grep(defined $_, @tests);

use_ok($LOADER);
use_ok($DUMPER);

sub breakpoint {}

foreach my $data (@tests) {
  unless (defined $data) {
    breakpoint();
    next;
  }

  my ($exp, @data) = @$data;
  my $title = join(", ", Data::Dumper->new(\@data)->Terse(1)->Indent(0)->Dump);
  eq_or_diff my $got = $DUMPER->dump_xhf(@data)."\n", $exp, "dump: $title";
  is_deeply [$LOADER->new(string => $got)->read], \@data, "read: $title";
  is_deeply [$LOADER->new(string => $exp)->read], \@data, "read_exp: $title";
}
