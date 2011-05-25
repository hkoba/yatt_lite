package YATT::Lite::Entities;
use strict;
use warnings FATAL => qw(all);
use Carp;

# XXX: 残念ながら、要整理。

use YATT::Lite::Util;

sub default_export { qw(Entity *YATT) }

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

sub add_base_to {
  my ($pkg, $base) = @_;
  my $isa = globref($pkg, 'ISA');
  if (*{$isa}{ARRAY} and @{*{$isa}{ARRAY}}
      and ${*{$isa}{ARRAY}}[0] ne $base) {
    die "Inheritance confliction on $pkg: old=${*{$isa}{ARRAY}}[0] new=$base";
  }
  *$isa = [] unless *{$isa}{ARRAY};
  @{*{$isa}{ARRAY}} = $base;
  $pkg;
}

#########################################

sub define_MY {
  my ($myPack, $opts, $callpack) = @_;
  my $my = globref($callpack, 'MY');
  unless (*{$my}{CODE}) {
    *$my = sub () { $callpack };
  }
}

# use YATT::Lite::Entities qw(Entity); で呼ばれ、
# $callpack に Entity 登録関数を加える.
sub define_Entity {
  my ($myPack, $opts, $callpack) = @_;

  # Entity を追加する先は、 $callpack が Object 系か、 memberless Pkg 系かによる
  # Object 系の場合は、 ::EntNS を作ってそちらに加える。
  # XXX: この判断ロジック自体を public API にするべきではないか？
  my $is_objclass = UNIVERSAL::isa($callpack, 'YATT::Lite::Object');
  my $destns = $is_objclass ? build_entns(EntNS => $callpack) : $callpack;

  # 既にあるなら何もしない。... バグの温床にならないことを祈る。
  my $ent = globref($callpack, 'Entity');
  unless (*{$ent}{CODE}) {
    *$ent = sub {
      my ($name, $sub) = @_;
      *{globref($destns, "entity_$name")} = $sub;
    };
  }

  if ($is_objclass) {
    *{globref($destns, 'YATT')} = *YATT;
  }
}

sub coalesce_const (&@) {
  my ($filter, $const) = splice @_, 0, 2;
  local $_;
  foreach my $item (@_) {
    next unless defined $item;
    next unless my $sub = $item->can($const);
    $_ = $sub->();
    next unless $filter->();
    return $_;
  }
}

# ${outerns}::EntNS を作り、(YATT::Lite::Entities へ至る)継承関係を設定する。
# $outerns に EntNS constant を追加する。
# XXX: 複数回呼んでも大丈夫か?
sub build_entns {
  my ($suffix, $outerns, $base) = @_;
  my $newns = join "::", $outerns, $suffix;
  my $basens = (coalesce_const {$_ ne $newns} EntNS => $outerns)
    || $base || __PACKAGE__;
  add_base_to($newns, $basens) unless UNIVERSAL::isa($newns, $basens);
  set_inc($newns, 1);
  # EntNS を足すのは最後にしないと、再帰継承に陥る
  my $sym = globref($outerns, 'EntNS');
  unless (*{$sym}{CODE}) {
    # print STDERR "# adding ${outerns}::EntNS = $newns\n";
    *$sym = sub () { $newns };
  }
  $newns
}

# 少しでも無駄な stat() を減らすため。もっとも、 ROOT ぐらいしか呼んでないから、大勢に影響せず。
sub set_inc {
  my ($pkg, $val) = @_;
  $pkg =~ s|::|/|g;
  $INC{$pkg.'.pm'} = $val || 1;
  # $INC{$pkg.'.pmc'} = $val || 1;
  $_[1];
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
sub entity_default {
  my $this = shift;
  foreach my $str (@_) {
    return $str if defined $str and $str ne '';
  }
  '';
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

sub entity_render {
  my ($this, $method) = splice @_, 0, 2;
  my $sub = $this->can("render_$method")
    or die "No such method: $method";
  require YATT::Lite::Util;
  my $con = $this->YATT->CON;
  my $enc = $con->cget('encoding') if UNIVERSAL::can($con, 'cget');
  my $layer = ":encoding($enc)" if $enc;
  $sub->($this, YATT::Lite::Util::ostream(my $buffer, $layer), @_);
  if ($enc) {
    \ Encode::decode($enc, $buffer);
  } else {
    \ $buffer;
  }
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

use YATT::Lite::Breakpoint ();
YATT::Lite::Breakpoint::break_load_entns();

1;
