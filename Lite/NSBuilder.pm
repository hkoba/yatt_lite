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
  use YATT::Lite::Util qw(ckeval ckrequire set_inc);
  our %SEEN_NS;
  use fields qw(cf_appns appns
		cf_appbase appbase
		subns);
  sub default_appns {__PACKAGE__}
  sub after_new {
    (my MY $self) = @_;
    if ($self->{cf_appns} and $SEEN_NS{$self->{cf_appns}}++) {
      confess "appns '$self->{cf_appns}' is already used!";
    }
  }
  sub default_subns {'INST'}
  sub default_appbase {'YATT::Lite'}
  sub appbase {
    (my MY $self) = @_;
    $self->{appbase} ||= $self->init_appbase
  }
  sub init_appbase {
    (my MY $self) = @_;
    my $appbase = $self->{cf_appbase} || $self->default_appbase;
    ckrequire($appbase);
    $appbase;
  }
  sub appns {
    (my MY $self) = @_;
    $self->{appns} ||= $self->init_appns
  }
  sub init_appns {
    (my MY $self) = @_;
    my $appns = $self->{cf_appns};
    try_require($appns);
    my $appbase = $self->appbase;
    unless ($appns->isa($appbase)) {
      $self->_eval_use_base($appns, $appbase);
    }
    $appns;
  }
  sub try_require {
    my ($appns) = @_;
    (my $modfn = $appns) =~ s|::|/|g;
    local $@;
    eval qq{require $appns};
    unless ($@) {
      # $appns.pm is loaded successfully.
    } elsif ($@ =~ m{^Can't locate $modfn}) {
      # $appns.pm can be missing.
    } else {
      die $@;
    }
  }
  sub buildns {
    (my MY $self, my ($subns, @base)) = @_;
    $subns ||= $self->default_subns;
    @base = map {ref $_ || $_} @base;
    my $appbase = $self->appbase;
    if (@base) {
      try_require($_) for @base;
      unless (grep {$_->isa($appbase)} @base) {
	croak "None of baseclass inherits $appbase: @base";
      }
    }
    my $appns = $self->appns;
    my $newns = sprintf q{%s::%s%d}, $appns, $subns, ++$self->{subns}{$subns};
    $self->_eval_use_base($newns, @base ? @base : $appns);
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
