package YATT::Lite::VarMaker; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Lite::Object);
use fields qw(type_alias known_types);

use YATT::Lite::VarTypes qw(:type);
use YATT::Lite::Util qw(lexpand default);

# XXX: Should integrated to VarTypes.
sub default_arg_type {'text'}
sub default_type_alias {
  qw(value scalar flag scalar
     expr code);
}

# XXX: Should integrated to VarTypes.
sub known_types {
  qw(text html attr
     list scalar code
     delegate);
}

sub after_new {
  my MY $self = shift;
  $self->SUPER::after_new;
  $self->{type_alias} = { $self->default_type_alias };
  $self->{known_types}{$_} = 1 for $self->known_types;
  $self;
}

# Note: To use mkvar_at(), derived class must implement
# _error() and _tmpl_file_line().
# Currently, YATT::Lite::LRXML and YATT::Lite::CGen.
sub mkvar_at {
  (my MY $self, my ($lineno, $type, $name, @args)) = @_;
  ($type, my @subtype) = ref $type ? lexpand($type) : split /:/, $type || '';
  #
  $type ||= $self->default_arg_type;
  $type = default($self->{type_alias}{$type}, $type);

  unless ($self->{known_types}{$type}) {
    my %opts = ($self->_tmpl_file_line($lineno));
    die $self->_error(\%opts, q|Unknown type '%s' for variable '%s'|
		      , $type, $name);
  }

  # XXX: This behavior should be changed.
  # 未知の型の時は undef を返す。エラー情報が足りないまま raise するよりはマシ。
  # (subclass で override して使うのが良いかも)
  my $sub = $self->can("t_$type")
    or return undef;
  $sub->()->new([$type, @subtype], $name, @args);
}

1;
