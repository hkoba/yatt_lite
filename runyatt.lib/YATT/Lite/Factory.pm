package YATT::Lite::Factory;
use strict;
use warnings FATAL => qw(all);
use Carp;
use YATT::Lite::Breakpoint;
sub MY () {__PACKAGE__}

use base qw(YATT::Lite::NSBuilder);
use fields qw(
	      cf_tmpl_cache
	      cf_tmpldirs

	      cf_tmpl_encoding cf_output_encoding
	      cf_header_charset
	      cf_debug_cgen

	      cf_only_parse cf_namespace
	      cf_error_handler

	      cf_at_done
);


use YATT::Lite::Entities qw(build_entns);
use YATT::Lite::Util qw(lexpand globref);


sub after_new {
  (my MY $self) = @_;
  $self->{cf_tmpl_cache} ||= {}
}

sub buildns {
  my MY $self = shift;
  my $appns = $self->SUPER::buildns(@_);

  # MyApp が DirHandler を継承していなければ、加える
  unless ($appns->isa(my $default = $self->default_dirhandler)) {
    $self->add_isa($appns, $default);
  }

  # instns には MY を定義しておく。
  my $my = globref($appns, 'MY');
  unless (*{$my}{CODE}) {
    *$my = sub () { $appns };
  }

  # Entity も、呼べるようにしておく。
  my $ent = globref($appns, 'Entity');
  unless (*{$ent}{CODE}) {
    require YATT::Lite::Entities;
    YATT::Lite::Entities->define_Entity(undef, $appns);
  }

  $appns;
}

# This entry is called from cached_in, and creates DirHandler(facade of trans),
# with fresh namespace.
sub load {
  (my MY $self, my MY $sys, my $name) = @_;

  # MyApp を使いたいときは... Runenv->new(basens => 'MyApp') で。
  my $appns = $self->buildns; # MyApp::INST$n を作る. 親は?

  # $appns は DirHandler で Facade だから、 trans ではないことに注意。
  # trans にメンバーを足す場合は、facade にも足して、かつ cf_delegate しておかないとだめ。
  $appns->new($name
	      , vfs => [dir => $name, encoding => $self->{cf_tmpl_encoding}]
	      , package => $appns->rootns_for($appns)
	      , nsbuilder => sub {
		build_entns(TMPL => $appns, $appns->EntNS);
	      }
	      , $self->configparams);
}

sub configparams {
  my MY $self = shift;
  my @base = map { [dir => $_] } lexpand($self->{cf_tmpldirs});

  ((@base ? (base => \@base) : ())
   , $self->cf_delegate
   (qw(output_encoding header_charset debug_cgen tmpl_cache at_done
       namespace only_parse error_handler))
   , die_in_error => ! YATT::Lite::Util::is_debugging());
}

1;
