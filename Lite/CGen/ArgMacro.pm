package YATT::Lite::CGen::ArgMacro;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use mro 'c3';

sub MY () {'YATT::Lite::CGen::ArgMacro'}

use base qw(YATT::Lite::CGen::Perl);
use YATT::Lite::MFields;

use YATT::Lite::Core qw(ArgMacro Part Template);
use YATT::Lite::Constants;

#
# widget 呼び出しの引数リスト $primary に含まれる argmacro を展開する。
#
#  - in はトリガー。instance 毎に集めて取り除き、on_expand に渡す
#  - refer は取り除かず、$args/$vars で参照させるだけ
#  - out (rename 後の実名) が明示された instance は bypass (展開しない)。
#    同じ instance の in も有ればエラー
#
sub expand_all_argmacro {
  (my $class, my $cgen, my Part $widget, my $primary, my $node) = @_;
  my $triggers = $widget->{_argmacro_trigger_dict};
  my $outputs = $widget->{_argmacro_output_dict} // {};
  my (%found, %firstInput, %bypass, %byName, @rest);
  foreach my $arg (@$primary) {
    my $argName = YATT::Lite::CGen::Perl::argName($arg);
    if (defined $argName and my $spec = $triggers->{$argName}) {
      my ($instName, $formalArgName) = @$spec;
      $found{$instName}{$formalArgName} = $arg;
      $firstInput{$instName} //= $argName;
      next;
    }
    if (defined $argName) {
      $byName{$argName} //= $arg;
      if (my $spec = $outputs->{$argName}) {
        $bypass{$spec->[0]} //= $argName;
      }
    }
    push @rest, $arg;
  }
  return $primary if not %found;

  foreach my $instName (@{$widget->{_argmacro_instance_list}}) {
    next unless $found{$instName} and $bypass{$instName};
    die $cgen->generror(
      qq{argmacro %s is bypassed by explicit output '%s'; input '%s' can\'t be given}
      , $widget->{_argmacro_instance_dict}{$instName}->call_spec
      , $bypass{$instName}, $firstInput{$instName}
    );
  }

  [(map {
    if (my $args = $found{$_}) {

      $class->apply_argmacro($cgen, $widget->{_argmacro_instance_dict}{$_}
                             , $args, $widget, \%byName, $node);

    } else {
      ()
    }
  } @{$widget->{_argmacro_instance_list}}), @rest];
}

sub apply_argmacro {
  (my $class, my $cgen, my ArgMacro $argmacro, my $args
   , my Part $widget, my $byName, my $node) = @_;

  my $vars = $argmacro->{_arg_dict};
  if (my $refer = $argmacro->{refer_names}) {
    $vars = +{%{$vars // {}}};
    foreach my $name (@$refer) {
      $args->{$name} = $byName->{$name} if $byName->{$name};
      $vars->{$name} = $widget->{_arg_dict}{$name};
    }
  }

  my $result = $argmacro->{_on_expand}->($cgen, $args, $vars, $argmacro, $node);
  return if not keys %$result;

  map {
    my $attName = $_->[NODE_PATH];
    my $node = [];
    $node->[NODE_TYPE] = TYPE_ATT_TEXT;
    $node->[NODE_PATH] = $attName;
    $node->[NODE_BODY] = $result->{$argmacro->{resolve_map}{$attName}};
    $node;
  } @{$argmacro->{output_args}}

}

sub generate_on_declare {
  (my MY $self, my ArgMacro $argmacro) = @_;

  my $script = $self->generate_on_expand($argmacro);
  my $code = YATT::Lite::Util::ckeval($script);
  $argmacro->{_on_expand} = $code;

  $self->make_on_declare($argmacro);
}

# Builds the closure which is called for each %macro; in widget declarations.
# This is shared by template-defined and module-defined (YATT::Lite::ArgMacro)
# argmacros.
sub make_on_declare {
  (my $self_or_class, my ArgMacro $argmacro) = @_;

  return sub {
    (my MY $self, my $parser, my Part $part, my $node) = @_;

    my ($toName, $fromName) = do {
      if (not (my $body = $node->[NODE_BODY])) {
        ()
      } elsif (not $body->[2]) {
        ()
      } else {
        my (undef, $macroName, $pathItem) = @$body;
        my (undef, $renameSpec) = @$pathItem;

        my @match = $renameSpec =~ m{^(\w+)=(\w+)}
          or $parser->synerror_at($node->[NODE_LNO],
                                  "Invalid rename spec '%s'", $renameSpec);
        @match;
      }
    };

    my $instName = join(":", $argmacro->{namespace}, $argmacro->{name}
                        , ($toName ? $toName : ()));
    my ArgMacro $instance = $argmacro->clone_with_renamespec($toName, $fromName);
    foreach my $outArg (@{$instance->{output_args}}) {
      my $formalName = $outArg->[NODE_PATH];
      if ($toName) {
        my $actualName = _apply_rename($formalName, $toName, $fromName);
        $instance->{rename_map}{$formalName} = $actualName;
        $instance->{resolve_map}{$actualName} = $formalName;
      } else {
        $instance->{rename_map}{$formalName} = $formalName;
        $instance->{resolve_map}{$formalName} = $formalName;
      }
    }

    if ($part->{_argmacro_instance_dict}{$instName}) {
      $self->synerror_at($node->[NODE_LNO],
                         "Duplicate use of argmacro '%s'", $instName);
    }
    $part->{_argmacro_instance_dict}{$instName} = $instance;
    foreach my $formalName (keys %{$instance->{rename_map}}) {
      $part->{_argmacro_output_dict}{$instance->{rename_map}{$formalName}}
        = [$instName, $formalName];
    }
    push @{$part->{_argmacro_instance_list}}, $instName;

    foreach my $argName (@{$argmacro->{_arg_order}}) {
      my $actualName = _apply_rename($argName, $toName, $fromName);
      $part->{_argmacro_trigger_dict}{$actualName} = [$instName, $argName];
    }

    $parser->add_args(
      $part,
      map {
        my $formalName = $_->[NODE_PATH];
        $_->[NODE_PATH] = $instance->{rename_map}{$formalName};
        $_;
      } @{$instance->{output_args}}
    );

    return $part; # debugging aid
  };
}

sub _apply_rename {
  my ($argName, $toName, $fromName) = @_;
  if (not $toName) {
    $argName
  } elsif (defined $fromName and $argName eq $fromName) {
    $toName
  } else {
    $toName.'_'.$argName;
  }
}

sub generate_on_expand {
  (my MY $self, my ArgMacro $argmacro) = @_;

  my Template $tmpl = $self->{_curtmpl};

  my $cgenType = ref $self;
  my $macroType = ArgMacro;
  my $argsType = "$tmpl->{entns}::args_$argmacro->{name}";
  my $varsType = "$tmpl->{entns}::vars_$argmacro->{name}";
  my $resultType = "$tmpl->{entns}::result_$argmacro->{name}";

  my @output_names = map {
    $_->[NODE_PATH];
  } @{$argmacro->{output_args}};

  require YATT::Lite::ArgMacro;
  YATT::Lite::ArgMacro->define_record_class($resultType, @output_names);
  YATT::Lite::ArgMacro->define_record_class(
    $_, @{$argmacro->{_arg_order} // []}
  ) for $argsType, $varsType;

  my @script;
  push @script, q(use YATT::Lite::Constants; );
  push @script, sprintf(
    q{(my %s $cgen, my %s $args, my %s $vars, my %s $argmacro, my $node) = @_; my %s $result = +{};},
    $cgenType, $argsType, $varsType, $macroType, $resultType
  );

  push @script, @{$argmacro->{_toks}};
  push @script, q(return $result);

  my $script = sprintf(q{use strict; use warnings; sub {%s}}, join "", @script);

  if ($ENV{DEBUG}) {
    print $script, "\n";
  }

  $script;
}

1;
