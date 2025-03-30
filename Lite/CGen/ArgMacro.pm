package YATT::Lite::CGen::ArgMacro;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use mro 'c3';

sub MY () {'YATT::Lite::CGen::ArgMacro'}

use base qw(YATT::Lite::CGen::Perl);
use YATT::Lite::MFields;

use YATT::Lite::Core qw(ArgMacro Part);
sub generate_on_declare {
  (my MY $self, my ArgMacro $argmacro) = @_;

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
  };
}

1;
