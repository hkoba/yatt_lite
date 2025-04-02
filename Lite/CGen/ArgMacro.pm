package YATT::Lite::CGen::ArgMacro;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use mro 'c3';

sub MY () {'YATT::Lite::CGen::ArgMacro'}

use base qw(YATT::Lite::CGen::Perl);
use YATT::Lite::MFields;

use YATT::Lite::Core qw(ArgMacro Part Template);
use YATT::Lite::Constants;

sub expand_all_argmacro {
  my ($class, $cgen, $primary, $triggers, $macroList, $macroDict) = @_;
  my (%found, @rest);
  foreach my $arg (@$primary) {
    my $argName = YATT::Lite::CGen::Perl::argName($arg);
    if (my $instName = $triggers->{$argName}) {
      $found{$instName}{$argName} = $arg;
    } else {
      push @rest, $arg;
    }
  }
  return $primary if not %found;

  [(map {
    if (my $args = $found{$_}) {

      $class->apply_argmacro($cgen, $macroDict->{$_}, $args);

    } else {
      ()
    }
  } @$macroList), @rest];
}

sub apply_argmacro {
  (my $class, my $cgen, my ArgMacro $argmacro, my $args) = @_;

  my $result = $argmacro->{on_expand}->($cgen, $args, $argmacro);
  return if not keys %$result;

  map {
    my $attName = $_->[NODE_PATH];
    my $node = [];
    $node->[NODE_TYPE] = TYPE_ATT_TEXT;
    $node->[NODE_PATH] = $attName;
    $node->[NODE_BODY] = $result->{$attName};
    $node;
  } @{$argmacro->{cf_output_args}}

}

sub generate_on_declare {
  (my MY $self, my ArgMacro $argmacro) = @_;

  my $script = $self->generate_on_expand($argmacro);
  my $code = YATT::Lite::Util::ckeval($script);
  $argmacro->{on_expand} = $code;

  return sub {
    (my MY $self, my $parser, my Part $part, my $node) = @_;

    my $instName = join(":", $argmacro->{cf_namespace}, $argmacro->{cf_name});
    # XXX: %yatt:macro(name=arg); の引数も入れるべき

    # XXX: 重複登録のエラー処理
    $part->{argmacro_instance_dict}{$instName} = $argmacro;
    push @{$part->{argmacro_instance_list}}, $instName;

    # XXX: trigger の rename 処理
    foreach my $argName (@{$argmacro->{arg_order}}) {
      $part->{argmacro_trigger_dict}{$argName} = $instName;
    }

    $parser->add_args($part, @{$argmacro->{cf_output_args}});
  };
}

sub generate_on_expand {
  (my MY $self, my ArgMacro $argmacro) = @_;

  my Template $tmpl = $self->{curtmpl};

  my $cgenType = ref $self;
  my $macroType = ArgMacro;
  my $argsType = "$tmpl->{cf_entns}::args_$argmacro->{cf_name}";
  my $resultType = "$tmpl->{cf_entns}::result_$argmacro->{cf_name}";

  my @output_names = map {
    $_->[NODE_PATH];
  } @{$argmacro->{cf_output_args}};

  my @script;
  push @script, q(use YATT::Lite::Constants; );
  push @script, sprintf(
    qq{{package %s; use fields qw(%s)}},
    $resultType,
    join(" ", @output_names),
  );
  push @script, sprintf(
    qq{{package %s; use fields qw(%s)}},
    $argsType,
    join(" ", @{$argmacro->{arg_order} // []}),
  );
  push @script, sprintf(
    q{(my %s $cgen, my %s $args, my %s $argmacro) = @_; my %s $result = +{};},
    $cgenType, $argsType, $macroType, $resultType
  );

  push @script, @{$argmacro->{toks}};
  push @script, q(return $result);

  my $script = sprintf(q{use strict; use warnings; sub {%s}}, join "", @script);

  if ($ENV{DEBUG}) {
    print $script, "\n";
  }

  $script;
}

1;
