#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/lib");
use Test::More;
use YATT::Lite::Test::TestUtil;

use YATT::Lite ();
use YATT::Lite::Util qw(catch terse_dump);

my $parser;
sub is_entpath (@) {
  my ($in, $expect) = @_;
  local $_ = $in;
  my @entpath = eval {$parser->_parse_entpath};
  if ($@) {
    Test::More::fail "$in\n $@";
  } else {
    is(terse_dump(@entpath)
       , terse_dump(defined $expect ? @$expect : $expect)
       , $in);
  }
}

my @test; sub add {push @test, [@_]} sub break {push @test, undef}
{
  add q{:foo;}
    , [[var => 'foo']];

  add q{:foo:bar;}
    , [[var => 'foo'], [prop => 'bar']];

  add q{:foo:bar();}
    , [[var => 'foo'], [invoke => 'bar']];

  add q{:foo:bar():baz;}
    , [[var => 'foo'], [invoke => 'bar'], [prop => 'baz']];

  add q{:foo();}
    , [[call => foo =>]];

  add q{:fn(tt,:foo:bar);}
    , [[call => fn => [text => 'tt'], [[var => 'foo'], [prop => 'bar']]]];

  add q{:foo(,);}
    , [[call => foo => [text => '']]];

  add q{:foo(,,);}
    , [[call => foo => [text => ''], [text => '']]];

  add q{:foo(bar);}
    , [[call => foo => [text => 'bar']]];

  add q{:foo(bar,);}
    , [[call => foo => [text => 'bar']]];

  add q{:foo(bar,,);}
    , [[call => foo => [text => 'bar'], [text => '']]];

  add q{:foo():bar();}
    , [[call => foo =>], [invoke => bar =>]];

  add q{:foo(bar,:baz(),,);}
    , [[call => foo => [text => 'bar'], [call => 'baz']
       , [text => '']]];

  add q{:x{foo}{:y};}
    , [[var => 'x'], [href => [text => 'foo']]
       , [href => [var => 'y']]];

  # break;
  add q{:foo({key:val});}
    , [[call => foo => , [hash => [text => 'key'], [text => 'val']]]];

  add q{:foo(bar,{key:val,k2:v2},,);}
    , [[call => foo => [text => 'bar']
	, [hash => [text => 'key'], [text => 'val']
	   , [text => 'k2'], [text => 'v2']]
	, [text => '']]];

  add q{:foo(bar,{key:val,k2,:v2:path},,);}
    , [[call => foo => [text => 'bar']
	, [hash => [text => 'key'], [text => 'val']
	   , [text => 'k2'], [[var => 'v2'],[prop => 'path']]]
	, [text => '']]];

  add q{:yaml(config):title;}
    , [[call => yaml => [text => 'config']]
       , [prop  => 'title']
      ];

  add q{:foo(:config,title);}
    , [[call => foo => [var => 'config'], [text => 'title']]];

  add q{:foo[3][8];}
    , [[var => 'foo'], [aref => [expr => '3']], [aref => [expr => '8']]];

  add q{:x[0][:y][1];}
    , [[var => 'x']
       , [aref => [expr => '0']]
       , [aref => [var => 'y']]
       , [aref => [expr => '1']]];

  add q{:x[:y[0][:z]][1];}
    , [[var => 'x']
       , [aref =>
	  [[var => 'y']
	   , [aref => [expr => '0']]
	   , [aref => [var => 'z']]]]
       , [aref => [expr => '1']]];

  add q{:foo([3][8]);}
    , [[call => foo =>
	[[array => [text => '3']]
	 , [aref => [expr => '8']]]]];

  add q{:foo([3,5][7]);}
    , [[call => foo =>
	[[array => [text => '3'], [text => '5']]
	 , [aref => [expr => '7']]]]];

  add q{:foo([3][8],,[5][4],,);}
    , [[call => foo =>
	[[array => [text => '3']]
	 , [aref => [expr => '8']]]
	, [text => '']
	, [[array => [text => '5']]
	   , [aref => [expr => '4']]]
	, [text => '']
       ]];

  #----------------------------------------

  add q{:where({user:hkoba,status:[assigned,:status,pending]});}
    , [[call => 'where'
	, [hash => [text => 'user'], [text => 'hkoba']
	   , [text => 'status'], [array => [text => 'assigned']
				  , [var  => 'status']
				  , [text => 'pending']]]]];

  add q{:where({user:hkoba,status:{!=,:status}});}
    , [[call => 'where'
	, [hash => [text => 'user'], [text => 'hkoba']
	   , [text => 'status'], [hash => [text => '!=']
				  , [var => 'status']]]]];

  add q{:where({user:hkoba,status:{!=,[assigned,in-progress,pending]}});}
    , [[call => 'where'
	, [hash => [text => 'user'], [text => 'hkoba']
	   , [text => 'status'], [hash => [text => '!=']
				  , [array => [text => 'assigned']
				     , [text => 'in-progress']
				     , [text => 'pending']]]]]];

  add q{:where({user:hkoba,status:{!=,completed,-not_like:pending%}});}
    , [[call => 'where'
	, [hash => [text => 'user'], [text => 'hkoba']
	   , [text => 'status']
	   , [hash => [text => '!='], [text => 'completed']
	      , [text => -not_like], [text => 'pending%']]]]];

  add q{:where({priority:{<,2},workers:{>=,100}});}
    , [[call => 'where'
	, ['hash'
	   , [text => 'priority'], [hash => [text => '<'],  [text => '2']]
	   , [text => 'workers'],[hash => [text => '>='], [text => '100']]]]];

  #----------------------------------------

  add q{:schema:resultset(Artist):all();}
    , [[var => 'schema']
       , [invoke => resultset => [text => 'Artist']]
       , [invoke => 'all']];

  add q{:schema:resultset(Artist):search({name:{like:John%}});}
    , [[var => 'schema']
       , [invoke => resultset => [text => 'Artist']]
       , [invoke => 'search'
	  , [hash => [text => 'name']
	     , [hash => [text => 'like']
		, [text => 'John%']]]]
	 ];

  add q{:john_rs:search_related(cds):all();}
    , [[var => 'john_rs']
       , [invoke => search_related => [text => 'cds']]
       , [invoke => 'all']];

  add q{:first_john:cds(=undef,{order_by:title});}
    , [[var => 'first_john']
       , [invoke => 'cds'
	  , [expr => 'undef']
	  , [hash => [text => 'order_by']
	     , [text => 'title']]]];

  add q{:schema:resultset(CD):search({year:2000},{prefetch:artist});}
    , [[var => 'schema']
       , [invoke => resultset => [text => 'CD']]
       , [invoke => 'search'
	  , [hash => [text => 'year'], [text => '2000']]
	  , [hash => [text => 'prefetch'], [text => 'artist']]]];

  add q{:cd:artist():name();}
    , [[var => 'cd']
       , [invoke => 'artist']
       , [invoke => 'name']];

  #----------------------------------------

  add q{:foo(bar):baz():bang;}
    , [[call => foo => [text => 'bar']]
       , [invoke => 'baz']
       , [prop  => 'bang']
      ];

  add q{:foo(:bar:baz(:bang()),hoe,:moe);}
    , [[call => 'foo'
	, [[var => 'bar'], [invoke => 'baz', [call => 'bang']]]
	, [text => 'hoe']
	, [var  => 'moe']]];

  add q{:foo(bar(,)baz(),bang);}
    , [[call => 'foo'
	, [text => 'bar(,)baz()']
	, [text => 'bang']]];


  add q{:foo(=$i*($j+$k),,=$x[8]{y}:z):hoe;}
    , [[call => 'foo'
	, [expr => '$i*($j+$k)']
	, [text => '']
	, [expr => '$x[8]{y}:z']]
      , [prop => 'hoe']];

  add q{:foo(bar${q}baz);}
    , [[call => 'foo'
	, [text => 'bar${q}baz']]];

  add q{:foo(bar,baz,[3]);}
    , [[call => 'foo'
	, [text => 'bar']
	, [text => 'baz']
	, [array => [text => '3']]]];

  add q{:if(=$$list[0]*$$list[1]==24,yes,no);}
    , [[call => 'if'
	, [expr => '$$list[0]*$$list[1]==24']
	, [text => 'yes']
	, [text => 'no']]];

  add q{:if(=($$list[0]+$$list[1])==11,yes,no);}
    , [[call => 'if'
	, [expr => '($$list[0]+$$list[1])==11']
	, [text => 'yes']
	, [text => 'no']]];

  add q{:if(=($x+$y)==$z,baz);}
    , [[call => 'if'
	, [expr => '($x+$y)==$z']
	, [text => 'baz']]];
    
  add q{:foo(=@bar);}
    , [[call => 'foo'
	, [expr => '@bar']]];

  my $chrs = q{|,@,$,-,+,*,/,<,>,!}; # XXX: % is ng for sprintf...
  add qq{:foo($chrs);}
    , [[call => 'foo'
	, map {[text => $_]} split /,/, $chrs]];

  add q{:dispatch_one(for_,1,:atts{for},:atts,:lexpand(:list));}
    , [[call => 'dispatch_one'
	, [text => 'for_']
	, [text => '1']
	, [[var => 'atts'], [href => [text => 'for']]]
	, [var => 'atts']
	, [call => 'lexpand'
	   , [var => 'list']]]];
}

my $class = 'YATT::Lite::LRXML';

plan tests => 2 + grep {defined} @test;

require_ok($class);
ok($parser = $class->new, "new $class");

foreach my $test (@test) {
  unless (defined $test) {
    YATT::breakpoint();
  } else {
    is_entpath @$test;
  }
}
