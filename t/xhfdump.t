#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}
use base qw(File::Spec);
use File::Basename;
use FindBin;
my $libdir;
BEGIN {
  unless (grep {$_ eq 'YATT'} MY->splitdir($FindBin::Bin)) {
    die "Can't find YATT in runtime path: $FindBin::Bin\n";
  }
  $libdir = dirname(dirname($FindBin::Bin));
}
use lib $libdir;
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
