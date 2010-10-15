package YATT::Lite::VarMaker; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Lite::Object);
use fields qw(type_alias);

use YATT::Lite::VarTypes qw(:type);
use YATT::Lite::Util qw(lexpand default);

sub default_arg_type {'text'}
sub default_type_alias {
  qw(value scalar flag scalar
     expr code);
}

sub after_new {
  my MY $self = shift;
  $self->SUPER::after_new;
  $self->{type_alias} = { $self->default_type_alias };
  $self;
}

sub mkvar {
  (my MY $self, my ($type, @args)) = @_;
  ($type, my @subtype) = ref $type ? lexpand($type) : split /:/, $type || '';
  #
  $type ||= $self->default_arg_type;
  $type = default($self->{type_alias}{$type}, $type);

  # 未知の型の時は undef を返す。エラー情報が足りないまま raise するよりはマシ。
  # (subclass で override して使うのが良いかも)
  my $sub = $self->can("t_$type")
    or return undef;
  $sub->()->new([$type, @subtype], @args);
}

1;
