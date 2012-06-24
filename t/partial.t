#!/usr/bin/env perl
# -*- mode: perl; coding: utf-8 -*-
#----------------------------------------
use strict;
use warnings FATAL => qw(all);
sub MY () {__PACKAGE__}
use base qw(File::Spec);
use File::Basename;

use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
my $libdir;
BEGIN {
  unless (grep {$_ eq 'YATT'} MY->splitdir($FindBin::Bin)) {
    die "Can't find YATT in runtime path: $FindBin::Bin\n";
  }
  $libdir = dirname(dirname(untaint_any($FindBin::Bin)));
}
use lib $libdir;
#----------------------------------------

use Test::More qw(no_plan);

sub eval_ok {
  my ($text, $title) = @_;
  local $@ = '';
  eval $text;
  is $@, '', $title;
}

sub error_like {
  my ($text, $pattern, $title) = @_;
  local $@ = '';
  eval "use strict; $text";
  like $@, $pattern, $title;
}

{
  eval_ok(q{
    package T1; use YATT::Lite::Inc;
    use YATT::Lite::MFields
       (qw/cf_foo1 cf_foo2 cf_foo3/);
  }, 'class T1');

  my $dummy = %T1::FIELDS;

  is_deeply [sort keys %T1::FIELDS]
    , [qw/cf_foo1 cf_foo2 cf_foo3/]
      , "t1 fields";

  error_like q{my T1 $t1; defined $t1->{cf_foo}}
    , qr/^No such class field "cf_foo" in variable \$t1 of type T1/
      , "field name error T1->cf_foo is detected";

  eval_ok q{my T1 $t1; defined $t1->{cf_foo1}}
    , "correct field name should not raise error";

  eval_ok(q{
    package T2; use YATT::Lite::Inc;
    use fields (qw/cf_bar1 cf_bar2/);
  }, "class T2");

  eval_ok(q{
    package T3; use YATT::Lite::Inc;
    use parent qw/T1 T2/;
    use YATT::Lite::MFields;
  }, "class T3");


  $dummy = %T3::FIELDS;
  is_deeply [sort keys %T3::FIELDS]
    , [qw/cf_bar1 cf_bar2 cf_foo1 cf_foo2 cf_foo3/]
      , "t3 fields";


  error_like q{my T3 $t; defined $t->{cf_foo}}
    , qr/^No such class field "cf_foo" in variable \$t of type T3/
      , "field name error T3->cf_foo is detected";

  eval_ok q{my T3 $t; defined $t->{cf_foo1}}
    , "correct field name should not raise error";

}

{
  eval_ok(q{
    package U1; use YATT::Lite::Inc;
    use YATT::Lite::MFields sub {
      my ($meta) = @_;
      $meta->has(name => is => 'ro', doc => "Name of the user");
      $meta->has(age => is => 'rw', doc => "Age of the user");
      $meta->has($_) for qw/weight height/;
    };
  }, 'class U1');

  my $dummy = %U1::FIELDS;

  is_deeply [sort keys %U1::FIELDS]
    , [qw/age height name weight/]
      , "U1 fields";

  error_like q{my U1 $t; defined $t->{ageee}}
    , qr/^No such class field "ageee" in variable \$t of type U1/
      , "field name error U1->ageee is detected";

  eval_ok q{my U1 $t; defined $t->{age}}
    , "correct field name should not raise error";

}

{
  eval_ok(q{
    package t3_Foo; use YATT::Lite::Inc; sub MY () {__PACKAGE__}
    use YATT::Lite::Partial
      fields => [qw/foo1 foo2/];
  }, "partial t3_Foo");

  my $dummy = %t3_Foo::FIELDS;
  is_deeply [sort keys %t3_Foo::FIELDS]
    , [qw/foo1 foo2/]
      , "partial t3_Foo fields";

  eval_ok(q{
    package t3_Bar; use YATT::Lite::Inc; sub MY () {__PACKAGE__}
    use YATT::Lite::Partial;
    use YATT::Lite::MFields
      qw/barx bary barz/;
  }, "partial t3_Bar");

  $dummy = %t3_Bar::FIELDS;
  is_deeply [sort keys %t3_Bar::FIELDS]
    , [qw/barx bary barz/]
      , "partial t3_Bar fields";

  eval_ok(q{
    package t3_App1; use YATT::Lite::Inc; sub MY () {__PACKAGE__}
    use YATT::Lite::Object -as_base;
    use t3_Foo;
    use t3_Bar;
    sub m1 {
      (my MY $x) = @_;
      join "", $x->{foo1}, $x->{foo2}, $x->{barx}, $x->{bary}, $x->{barz};
    }
    1;
  }, "partital t3_App1");

  $dummy = %t3_App1::FIELDS;
  is_deeply [sort keys %t3_App1::FIELDS]
    , [qw/barx bary barz foo1 foo2/]
      , "partial t3_App1 fields";


  error_like(q{
    package t3_App2; use YATT::Lite::Inc; sub MY () {__PACKAGE__}
    use YATT::Lite::Object -as_base;
    use t3_Foo;
    use t3_Bar;
    sub m1 {
      (my MY $self) = @_;
      $self->{ng};
    }
    1;
  }
	     , qr/^No such class field "ng" in variable \$self of type t3_App2/
	     , "partital t3_App2 field error is detected at compile time.");
}

# XXX 継承
{
  eval_ok(q{
    package t4_Foo; use YATT::Lite::Inc; sub MY () {__PACKAGE__}
    use YATT::Lite::Partial
      (fields => [qw/foo3 foo4/], parents => ['t3_Foo']);
  }, "partial t4_Foo");

  my $dummy = %t4_Foo::FIELDS;
  is_deeply [sort keys %t4_Foo::FIELDS]
    , [qw/foo1 foo2 foo3 foo4/]
      , "partial t4_Foo fields";

  eval_ok(q{
    package t4_Bar; use YATT::Lite::Inc; sub MY () {__PACKAGE__}
    use YATT::Lite::Partial
      (fields => [qw/bara barb/], parents => ['t3_Bar']);
  }, "partial t4_Bar");

  $dummy = %t4_Bar::FIELDS;
  is_deeply [sort keys %t4_Bar::FIELDS]
    , [qw/bara barb barx bary barz/]
      , "partial t4_Bar fields";

  eval_ok(q{
    package t4_App1; use YATT::Lite::Inc; sub MY () {__PACKAGE__}
    use base qw/YATT::Lite::Object/;
    use t4_Foo;
    use t4_Bar;
    sub m1 {
      (my MY $x) = @_;
      join "", $x->{foo1}, $x->{foo2}, $x->{barx}, $x->{bary}, $x->{barz};
    }
    1;
  }, "partital t4_App1");

  is_deeply \@t4_App1::ISA
    , [qw/YATT::Lite::Object t4_Foo t4_Bar/]
      , "'use PartialMod' adds ISA";

  $dummy = %t4_App1::FIELDS;
  is_deeply [sort keys %t4_App1::FIELDS]
    , [qw/bara barb barx bary barz foo1 foo2 foo3 foo4/]
      , "partial t4_App1 fields";


  error_like(q{
    package t4_App2; use YATT::Lite::Inc; sub MY () {__PACKAGE__}
    use base qw/YATT::Lite::Object/;
    use t4_Foo;
    use t4_Bar;
    sub m1 {
      (my MY $self) = @_;
      $self->{ng};
    }
    1;
  }
	     , qr/^No such class field "ng" in variable \$self of type t4_App2/
	     , "partital t4_App2 field error is detected at compile time.");

}
