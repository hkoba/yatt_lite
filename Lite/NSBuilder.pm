package YATT::Lite::NSBuilder; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);

use YATT::Lite::Util qw(lexpand);

{
  # bootscript が決まれば、root NS も一つに決まる、としよう。 MyApp 、と。
  # instpkg の系列も決まる、と。 MyApp::INST1, 2, ... だと。
  # XXX: INST を越えて共有される *.ytmpl/ は、 TMPL1, 2, ... と名づけたいが、...
  # それ以下のディレクトリ名・ファイル名はそのまま pkgname に使う。

  # MyApp::INST1::dir::dir::dir::file
  # MyApp::TMPL1::dir::dir::dir::file
  use base qw(YATT::Lite::Object);
  use Carp;
  use YATT::Lite::Util qw(ckeval ckrequire set_inc);
  our %SEEN_NS;
  use fields qw(cf_app_ns app_ns
		cf_default_app default_app
		subns);
  sub _before_after_new {
    (my MY $self) = @_;
    $self->SUPER::_before_after_new;
    if ($self->{cf_app_ns} and $SEEN_NS{$self->{cf_app_ns}}++) {
      confess "app_ns '$self->{cf_app_ns}' is already used!";
    }
    $self->init_default_app;
    $self->init_app_ns;
  }

  sub default_subns {'INST'}
  sub default_app_ns {'MyApp'}
  sub default_default_app {'YATT::Lite'}

  sub init_default_app {
    (my MY $self) = @_;
    $self->{default_app}
      = $self->{cf_default_app} || $self->default_default_app;
    ckrequire($self->{default_app});
  }
  sub init_app_ns {
    (my MY $self) = @_;
    $self->{app_ns} = my $app_ns = $self->{cf_app_ns} // $self->default_app_ns;
    try_require($app_ns);
    unless ($app_ns->isa($self->{default_app})) {
      $self->_eval_use_base($app_ns, $self->{default_app});
    }
  }
  sub try_require {
    my ($app_ns) = @_;
    (my $modfn = $app_ns) =~ s|::|/|g;
    local $@;
    eval qq{require $app_ns};
    unless ($@) {
      # $app_ns.pm is loaded successfully.
    } elsif ($@ =~ m{^Can't locate $modfn}) {
      # $app_ns.pm can be missing.
    } else {
      die $@;
    }
  }
  sub buildns {
    (my MY $self, my ($subns, @base)) = @_;
    $subns ||= $self->default_subns;
    @base = map {ref $_ || $_} @base;
    if (@base) {
      try_require($_) for @base;
      unless (grep {$_->isa($self->{default_app})} @base) {
	croak "None of baseclass inherits $self->{default_app}: @base";
      }
    }
    my $newns = sprintf q{%s::%s%d}, $self->{app_ns}, $subns
      , ++$self->{subns}{$subns};
    $self->_eval_use_base($newns, @base ? @base : $self->{app_ns});
    set_inc($newns, 1);
    $newns;
  }
  sub _eval_use_base {
    (my MY $self, my ($newns, @base)) = @_;
    ckeval($self->lineinfo(1, "$newns.pm") # XXX: ダミーの行情報
	   , "package $newns;\n"
	   , @base ? sprintf(qq{use base qw(%s);\n}, join " ", @base) : ());
  }
  sub lineinfo { shift; sprintf qq{#line %d "%s"\n}, @_}
}

1;
