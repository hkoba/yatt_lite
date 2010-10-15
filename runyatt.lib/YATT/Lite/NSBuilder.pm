package YATT::Lite::NSBuilder; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);

use YATT::Lite::Util qw(lexpand);

{
  # bootscript が決まれば、root NS も一つに決まる、としよう。 MyApp 、と。
  # instpkg の系列も決まる、と。 MyApp::INST1, 2, ... だと。
  # INST を越えて共有される *.ytmpl/ は、 TMPL1, 2, ... と名づける。
  # それ以下のディレクトリ名・ファイル名はそのまま pkgname に使う。

  # MyApp::INST1::dir::dir::dir::file
  # MyApp::TMPL1::dir::dir::dir::file
  use base qw(YATT::Lite::Object);
  use Carp;
  use YATT::Lite::Util qw(ckeval);
  our %SEEN_NS;
  use fields qw(cf_basens basens_loaded subns path2tmplpkg);
  sub default_basens {__PACKAGE__}
  sub after_new {
    (my MY $self) = @_;
    $self->{cf_basens} ||= $self->default_basens;
    if ($SEEN_NS{$self->{cf_basens}}++) {
      confess "basens '$self->{cf_basens}' is already used!";
    }
  }
  sub default_subns {'INST'}
  sub buildns {
    (my MY $self, my ($subns)) = splice @_, 0, 2;
    my $base = @_ ? shift : $self->{cf_basens};
    unless ($self->{basens_loaded}{$base}++) {
      (my $modfn = $base) =~ s|::|/|g;
      local $@;
      eval qq{require $base};
      die $@ unless not $@ or $@ =~ m{^Can't locate $modfn};
      # XXX: エラーにするモードも欲しいのでは？
      # XXX: MyApp が存在しないなら、 add_isa とか、
    }
    $subns ||= $self->default_subns;
    my $newns = sprintf q{%s::%s%d}, $self->{cf_basens}
      , $subns, ++$self->{subns}{$subns};
    $self->add_isa($newns, lexpand($base)) if defined $base;
    $newns;
  }
  sub add_isa {
    (my MY $self, my ($newns, @base)) = @_;
    ckeval($self->lineinfo(1, "$newns.pm") # XXX: ダミーの行情報
	   , "package $newns;\n"
	   , @base ? sprintf(qq{use base qw(%s);\n}, join " ", @base) : ());
  }
  sub lineinfo { shift; sprintf qq{#line %d "%s"\n}, @_}
  sub tmplcache {
    my MY $self = shift;
    $self->{path2tmplpkg} ||= {}
  }
}

1;
