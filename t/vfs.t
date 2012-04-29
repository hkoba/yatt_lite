#!/usr/bin/perl -w
use strict;
use warnings FATAL => qw(all);
use FindBin;
sub untaint_any {$_[0] =~ m{(.*)} and $1}
use lib untaint_any("$FindBin::Bin/lib");
use Test::More qw(no_plan);

use Getopt::Long;
GetOptions('q|quiet' => \ (my $quiet))
  or die "Unknown options\n";

sub TestFiles () {'YATT::Lite::TestFiles'}
require_ok(TestFiles);
sub VFS () {'YATT::Lite::VFS'}
require_ok(VFS);

{
  package DummyFacade;
  use base qw(YATT::Lite::Object);
  sub error {
    shift; die @_;
  }
}

my @CF = (ext_private => 'tmpl', ext_public => 'yatt'
	 , facade => DummyFacade->new);

{
  #
  # * data => HASH
  # * base => [[data => HASH] ...]
  #
  my $theme = "(mem) plain";
  my $vfs = VFS->new
    ([data => {foo => 'mytext'}, base => [[data => {'bar' => 'BARRR'}]]]
     , no_auto_create => 1, @CF);
  is $vfs->find_part('foo'), 'mytext', "$theme - foo";
  is $vfs->find_part('bar'), 'BARRR', "$theme - bar";
}

{
  #
  # * VFS->create($kind => $spec)
  # * data => {name => VFS}
  #
  my $theme = "(mem) from nested Dir";
  my $vfs = VFS->new
    ([data => {foo => VFS->create(data => {'bar' => 'BARRR'})}
      , base => [[data => {foo => VFS->create(data => {'baz' => 'ZZZ'})}]]]
     , no_auto_create => 1, @CF);
  is $vfs->find_part('foo', 'bar'), 'BARRR', "$theme - foo bar";
  is $vfs->find_part('foo', 'baz'), 'ZZZ', "$theme - foo baz";
}

sub rootname { my $fn = shift; $fn =~ s/\.\w+$//; join "", $fn, @_ }
use FindBin;

my $i;
my $BASE = untaint_any("$FindBin::Bin/".rootname($FindBin::RealScript).".d");
unless (-d $BASE) {
  mkdir $BASE or die "$BASE: $!";
}

$i = 1;
{
  my $dir = TestFiles->new("$BASE/t$i", quiet => $quiet);
  $dir->add('foo.yatt', <<END);
AAA
BBB
! widget bar
barrrr
END

  $dir->add('base.yatt', <<END);
! widget qux
Q
! widget quux
QQ
END

}
{
  #
  # * [dir => $dir]
  # * multipart (file foo contains widget bar)
  #

  my $theme = "[t$i] from dir";
  ok chdir(my $cwd = "$BASE/t". $i), "chdir [t$i]";
  my $root = VFS->new([dir => $cwd], @CF);
  is $root->find_part('foo', ''), "AAA\nBBB\n", "$theme - foo ''";
  is $root->find_part('foo', 'bar'), "barrrr\n", "$theme - foo bar";
}

{
  #
  # * [dir => $dir, base => [[file => $file]]
  #   directory can inherit parts from a file
  #

  my $theme = "[t$i] base file";
  ok chdir(my $cwd = "$BASE/t". $i), "chdir [t$i]";
  my $root = VFS->new([dir => $cwd
			     , base => [[file => "$cwd/base.yatt"]]]
			    , @CF);
  is $root->find_part('qux'), "Q\n", "$theme - qux";
  is $root->find_part('quux'), "QQ\n", "$theme - quux";
}

$i = 2;
{
  my $dir = TestFiles->new("$BASE/t$i", quiet => $quiet);
  $dir->add('foo.yatt', <<END);
! base file=base.yatt
AAA
BBB
! widget bar
barrrr
END

  $dir->add('base.yatt', <<END);
! widget baz
CCC
DDD
! widget qux
EEE
! widget quux
FFF
END

}

{
  my $theme = "[t$i] ! base";
  ok chdir(my $cwd = "$BASE/t". $i), "chdir [t$i]";
  my $root = VFS->new([dir => $cwd], @CF);
  is $root->find_part('foo', ''), "AAA\nBBB\n", "$theme - foo";
  is $root->find_part('foo', 'bar'), "barrrr\n", "$theme - foo bar";
  is $root->find_part('foo', 'baz'), "CCC\nDDD\n", "$theme - baz";
}

sub D {
  require Data::Dumper;
  join " ", Data::Dumper->new([@_])->Terse(1)->Indent(0)->Dump;
}

$i = 3;
{
  my $dir = TestFiles->new("$BASE/t$i", quiet => $quiet);
  $dir->add('foo.yatt', <<END);
! base dir=base.tmpl
AAA
END

  {
    my $base = $dir->mkdir('base.tmpl');

    $dir->add("$base/bar.yatt", <<END);
BBB
! widget qux
EEE
END

    $dir->add("$base/baz.yatt", <<END);
CCC
END
  }
}

{
  my $theme = "[t$i] base dir (in template)";
  ok chdir(my $cwd = "$BASE/t". $i), "chdir [t$i]";
  my $root = VFS->new([dir => $cwd], @CF); my @x;
  is $root->find_part(@x = ('foo', '')), "AAA\n", "$theme - ".D(@x);
  is $root->find_part(@x = ('foo', 'bar', '')), "BBB\n", "$theme - ".D(@x);
  is $root->find_part(@x = ('foo', 'baz', '')), "CCC\n", "$theme - ".D(@x);
}

{
  my $theme = "[t$i] base dir (in VFS new)";
  ok chdir(my $cwd = "$BASE/t". $i), "chdir [t$i]"; my @x;
  my $root = VFS->new([dir => $cwd, base => [[dir => "$cwd/base.tmpl"]]], @CF);
  is $root->find_part(@x = ('bar', '')), "BBB\n", "$theme - ".D(@x);
  is $root->find_part(@x = ('baz', '')), "CCC\n", "$theme - ".D(@x);
}

$i++;
{
  my $dir = TestFiles->new("$BASE/t$i", quiet => $quiet);
  $dir->mkdir('doc');
  $dir->add('doc/foo.yatt', <<END);
AAA
END

  $dir->add('doc/bar.yatt', <<END);
! base dir=quux.tmpl
BBB
! widget quuuuux
EEE
END

  $dir->add($dir->mkdir('qux.tmpl') . "/baz.yatt", <<END);
CCC
END

  $dir->add($dir->mkdir('quux.tmpl') . "/baz.yatt", <<END);
DDD
END
}
{
  my $theme = "[t$i] base dir (in VFS new and !base)";
  ok chdir(my $cwd = "$BASE/t". $i), "chdir [t$i]"; my @x;
  my $root = VFS->new([dir => "$cwd/doc"
			     , base => [[dir => "$cwd/qux.tmpl"]]], @CF);
  is $root->find_part(@x = ('foo', '')), "AAA\n", "$theme - ".D(@x);
  is $root->find_part(@x = ('foo', 'baz', '')), "CCC\n", "$theme - ".D(@x);
  is $root->find_part(@x = ('bar', 'baz', '')), "DDD\n", "$theme - ".D(@x);
  is $root->find_part(@x = ('bar', 'quuuuux')), "EEE\n", "$theme - ".D(@x);
}

$i++;
{
  my $dir = TestFiles->new("$BASE/t$i", quiet => $quiet);
  $dir->add('foo.yatt', <<END);
! base file=base.tmpl
AAA
BBB
! widget bar
CCC
END

  $dir->add((my $foo = $dir->mkdir('foo.tmpl')) . "/bar.yatt", <<END);
DDD
END

  $dir->add("$foo/baz.yatt", <<END);
EEE
END

  $dir->add('qux.yatt', <<END);
FFF
END

  $dir->add("$foo/qux.yatt", <<END);
GGG
END

  $dir->add('base.tmpl', <<END);
! widget hoehoe
HHH
! widget moemoe
III
END

}
{
  my $theme = "[t$i] coexisting foo.yatt and foo.tmpl";
  ok chdir(my $cwd = "$BASE/t". $i), "chdir [t$i]";
  my $root = VFS->new([dir => $cwd], @CF);
  my $foo = $root->find_part('foo');
  is $root->find_part_from($foo, 'bar'), "CCC\n", "$theme bar (template wins)";
  is $root->find_part_from($foo, 'baz'), "EEE\n", "$theme baz (dir is merged)";
  is $root->find_part_from($foo, 'qux'), "FFF\n", "$theme qux (cwd wins)";
  is $root->find_part_from($foo, 'hoehoe'), "HHH\n", "$theme base is merged";
}