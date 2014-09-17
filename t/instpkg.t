#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings FATAL => qw(all);
use FindBin; BEGIN { do "$FindBin::Bin/t_lib.pl" }
#----------------------------------------

use YATT::Lite::Util qw(appname list_isa globref catch);
sub myapp {join _ => MyTest => appname($0), @_}

use Test::Kantan;

sub NSBuilder () {'YATT::Lite::NSBuilder'}

describe "NSBuilder", sub {
  it "should be loaded", sub {
    ok {require YATT::Lite::NSBuilder};
  };

  describe "NSBuilder->new(app_ns => 'Foo')", sub {
    my $builder = NSBuilder->new(app_ns => 'Foo');
    sub Foo::bar {'baz'}
    my $pkg;
    it "should return instpkg(Foo::INST#)", sub {
      ok {($pkg = $builder->buildns('INST')) eq 'Foo::INST1'}
    };
    describe "instpkg  (Foo::INST#)", sub {
      it "should inherit app_ns(Foo)", sub {
	ok {$pkg->bar eq "baz"};
      };
    };
  };
  
  describe "Subclassed use of NSBuilder", sub {
    my $WDH = 'YATT::Lite::WebMVC0::DirApp';
    {
      package MyTest_NSB_Web;
      use base qw(YATT::Lite::NSBuilder);
      use YATT::Lite::MFields;
      sub default_default_app {'YATT::Lite::WebMVC0::DirApp'}
      use YATT::Lite::Inc;
    }
    my $NS = 'MyTest_NSB';
    describe "NSB_Subclass->new(app_ns => $NS)", sub {
      my $builder = MyTest_NSB_Web->new(app_ns => $NS);
      my $sub = $builder->buildns('INST');

      it "should inherit $NS and $WDH", sub {
	expect([list_isa($sub, 1)])->to_be([[$NS, [$WDH, list_isa($WDH, 1)]]]);
      };

      it "should load $WDH after buildns", sub {
	ok {$WDH->can('_handle_yatt')};
      };
    };
  };
  ;

  describe "myapp(\$i) tests", sub {
    my $i = 0;
    {
      my $CLS = myapp(++$i);
      describe "myapp(++\$i)", sub {
	it "should return correct pakcage name", sub {
	  ok {$CLS eq 'MyTest_instpkg_1'};
	};

	describe "NSBuilder->new(app_ns => $CLS)", sub {
	  my $builder = NSBuilder->new(app_ns => $CLS);
	  sub MyTest_instpkg_1::bar {'BARRR'}

	  describe "->buildns() result", sub {
	    my $pkg;
	    ok {($pkg = $builder->buildns) eq "${CLS}::INST1"};
	    ok {$pkg->bar eq "BARRR"};
	  };
	  describe "->buildns(TMPL) result", sub {
	    my $pkg2;
	    ok {($pkg2 = $builder->buildns('TMPL')) eq "${CLS}::TMPL1"};
	    ok {$pkg2->bar eq "BARRR"};
	  };
	}
      };
    }
    ;
    describe "INST, inherits a TMPL", sub {
      {
	my $NS = myapp(++$i);
	my $BLD = NSBuilder->new(app_ns => $NS);

	describe "BLD->buildins(INST => [BLD->buildns(TMPL)], fake.yatt)", sub {
	  my $base1 = $BLD->buildns('TMPL');
	  my $sub1 = $BLD->buildns(INST => [$base1]
				   , my $fake_fn =  __FILE__ . "/fake.yatt");

	  it "should inherit TMPL, $NS, YATT::Lite", sub {
	    expect([list_isa($sub1, 1)])
	      ->to_be([[$base1, [$NS, ['YATT::Lite'
				       , list_isa('YATT::Lite', 1)]]]]);
	  };

	  it "should has ->filename()", sub {
	    ok {$sub1->filename eq $fake_fn};
	  };
	};
      }
    };

    describe "INST, inherits only YATT::Lite", sub {
      my $YL = 'MyTest_instpkg_YL';
      {
	package MyTest_instpkg_YL;
	use base qw(YATT::Lite);
	use YATT::Lite::Inc;
      }

      my $NS = myapp(++$i);

      describe "BLD->buildns(INST => [subclass-of-YL], ./fakefn)", sub {
	my $BLD = NSBuilder->new(app_ns => $NS);
	my $sub = $BLD->buildns(INST => [$YL]
				    , my $fake2 = __FILE__ . "/fakefn2");
	it "should inherit subclass-of-YL (only)", sub {
	  expect([list_isa($sub, 1)])
	    ->to_be([[$YL, ['YATT::Lite', list_isa('YATT::Lite', 1)]]]);
	};

	describe "->filename() method(symbol)", sub {
	  my $sym = globref($sub, 'filename');
	  my $code;
	  it "should be defined as CODE", sub {
	    ok {defined ($code = *{$sym}{CODE})};
	  };
	  it "should return correct filename", sub {
	    ok {$code->() eq $fake2};
	  };
	};
      };
    };
    ;
    describe "buildns() error detection", sub {
      my $NS = myapp(++$i);
      my $BLD = NSBuilder->new(app_ns => $NS);
      it "should raise error when baseclass do not inherit YATT::Lite", sub {
	my $unknown = 'MyTest_instpkg_unk';
	expect(catch {$BLD->buildns(INST => [$unknown])})
	  ->to_match(qr/^None of baseclass inherits YATT::Lite: $unknown/);
      };
    };
  };
};

done_testing();
