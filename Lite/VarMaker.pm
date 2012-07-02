package YATT::Lite::VarMaker; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Lite::Object);
use fields qw/type_alias/;

use YATT::Lite::VarTypes qw(:type);
use YATT::Lite::Util qw(lexpand default);

# XXX: Should integrated to VarTypes.
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

# Note: To use mkvar_at(), derived class must implement
# _error() and _tmpl_file_line().
# Currently, YATT::Lite::LRXML and YATT::Lite::CGen uses this.
sub mkvar_at {
  (my MY $self, my ($lineno, $type, $name, @args)) = @_;
  ($type, my @subtype) = ref $type ? lexpand($type) : split /:/, $type || '';
  #
  $type ||= $self->default_arg_type;
  $type = default($self->{type_alias}{$type}, $type);

  my $sub = $self->can("t_$type") or do {
    my %opts = ($self->_tmpl_file_line($lineno));
    die $self->_error(\%opts, q|Unknown type '%s' for variable '%s'|
		      , $type, $name);
  };

  $sub->()->new([$type, @subtype], $name, @args);
}

1;
