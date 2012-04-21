package YATT::Lite::Entities;
use strict;
use warnings FATAL => qw(all);
use Carp;

# XXX: 残念ながら、要整理。

use YATT::Lite::Util;

sub default_export { qw(*YATT) }

#========================================
# Facade を template に見せるための, グローバル変数.
our $YATT;
sub symbol_YATT { return *YATT }
sub YATT { $YATT }
#========================================

sub import {
  my ($pack, @opts) = @_;
  @opts = $pack->default_export unless @opts;
  my $callpack = caller;
  my (%opts, @task);
  foreach my $exp (@opts) {
    if (my $sub = $pack->can("define_$exp")) {
      push @task, $sub;
    } elsif ($exp =~ /^-(\w+)$/) {
      $sub = $pack->can("declare_$1")
	or croak "Unknown declarator: $1";
      $sub->($pack, \%opts, $callpack);
    } elsif ($exp =~ /^\*(\w+)$/) {
      $sub = $pack->can("symbol_$1")
	or croak "Can't export symbol $1";
      my $val = $sub->();
      unless (defined $val) {
	croak "Undefined symbol in export spec: $exp";
      }
      *{globref($callpack, $1)} = $val;
    } elsif ($sub = $pack->can($exp)) {
      *{globref($callpack, $exp)} = $sub;
    } else {
      croak "Unknown export spec: $exp";
    }
  }
  foreach my $sub (@task) {
    $sub->($pack, \%opts, $callpack);
  }
}

# use 時に関数を生成したい場合、 define_ZZZ を定義すること。
# サブクラスで新たな symbol を export したい場合、 symbol_ZZZ を定義すること

sub declare_as_base {
  my ($myPack, $opts, $callpack) = @_;
  ckeval(<<END);
package $callpack; use base qw($myPack);
END
}

#########################################

sub define_MY {
  my ($myPack, $opts, $callpack) = @_;
  my $my = globref($callpack, 'MY');
  unless (*{$my}{CODE}) {
    *$my = sub () { $callpack };
  }
}

#========================================
# 組み込み Entity
# Entity 呼び出し時の第一引数は, packageName (つまり文字列) になる。

sub entity_breakpoint {
  require YATT::Lite::Breakpoint;
  &YATT::Lite::Breakpoint::breakpoint();
}

sub entity_concat {
  my $this = shift;
  join '', @_;
}

# coalesce
*entity_coalesce = *entity_default; *entity_coalesce = *entity_default;
sub entity_default {
  my $this = shift;
  foreach my $str (@_) {
    return $str if defined $str and $str ne '';
  }
  '';
}

*entity_lsize = *entity_llength; *entity_lsize = *entity_llength;
sub entity_llength {
  my ($this, $list) = @_;
  return undef unless defined $list and ref $list eq 'ARRAY';
  scalar @$list;
}

sub entity_join {
  my ($this, $sep) = splice @_, 0, 2;
  join $sep, grep {defined $_ && $_ ne ''} @_;
}

sub entity_format {
  my ($this, $format) = (shift, shift);
  sprintf $format, @_;
}

sub entity_HTML {
  my $this = shift;
  \ join "", grep {defined $_} @_;
}

sub entity_dump {
  shift;
  require YATT::Lite::Util;
  YATT::Lite::Util::terse_dump(@_);
}

sub entity_can_render {
  my ($this, $widget) = @_;
  $this->can("render_$widget");
}

sub entity_uc { shift; uc($_[0]) }
sub entity_ucfirst { shift; ucfirst($_[0]) }
sub entity_lc { shift; lc($_[0]) }
sub entity_lcfirst { shift; lcfirst($_[0]) }

sub entity_strftime {
  my ($this, $fmt, $sec, $is_uts) = @_;
  $sec //= time;
  require POSIX;
  POSIX::strftime($fmt, $is_uts ? gmtime($sec) : localtime($sec));
}

sub entity_mkhash {
  my ($this, @list) = @_;
  my %hash;
  $hash{$_} = 1 for @list;
  \%hash;
}

use YATT::Lite::Breakpoint ();
YATT::Lite::Breakpoint::break_load_entns();

1;
