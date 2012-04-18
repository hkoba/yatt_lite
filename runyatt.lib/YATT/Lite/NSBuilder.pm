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
  use fields qw(cf_appns
		cf_appbase
		appns_loaded subns);
  sub default_appns {__PACKAGE__}
  sub after_new {
    (my MY $self) = @_;
    $self->{cf_appns} ||= $self->default_appns;
    if ($SEEN_NS{$self->{cf_appns}}++) {
      confess "appns '$self->{cf_appns}' is already used!";
    }
  }
  sub default_subns {'INST'}
  sub default_appbase {'YATT::Lite'}
  sub appbase {
    (my MY $self) = @_;
    $self->{cf_appbase} || $self->default_appbase
  }
  sub buildns {
    (my MY $self, my ($subns, $baseclasslst)) = @_;
    $subns ||= $self->default_subns;
    my @base = lexpand($baseclasslst);
    my $appns = $self->{cf_appns};
    my $newns = sprintf q{%s::%s%d}, $appns, $subns, ++$self->{subns}{$subns};
    unless ($self->{appns_loaded}{$appns}++) {
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
      unless (grep {$appns->isa($_)} @base, $self->appbase) {
	$self->_eval_use_base($appns, @base ? @base : $self->appbase);
      }
    }
    # $self->_eval_use_base($newns, lexpand($baseclasslst || $appns));
    $self->_eval_use_base($newns, @base ? @base : $appns);

    foreach my $base ((@base ? @base : $appns), $self->appbase) {
      unless ($newns->isa($base)) {
	die "BUG: Can't configure isa relation for $newns: $newns should be a subclass of $base; (base=@base)";
      }
    }
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
