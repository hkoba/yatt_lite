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

	      cf_binary_config

	      cf_tmpl_encoding cf_output_encoding
	      cf_header_charset
	      cf_debug_cgen

	      cf_only_parse cf_namespace
	      cf_error_handler

	      cf_at_done
);


use YATT::Lite::Entities qw(build_entns);
use YATT::Lite::Util qw(lexpand globref untaint_any ckdo);
use YATT::Lite::XHF;

#
#
#

our $yatt_loading;
sub loading { $yatt_loading }

sub load_factory_script {
  my ($pack, $fn) = @_;
  local $yatt_loading = 1;
  ckdo $fn;
}

#========================================

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
  if (-e (my $cf = untaint_any($name) . "/.htyattconfig.xhf")) {
    _with_loading_file {$self} $cf, sub {
      my @spec = $self->read_file_xhf($cf, binary => $self->{cf_binary_config});
      # print STDERR "Factory::load $name (@spec)\n" if $ENV{YATT_DEBUG_LOAD};
      my ($appns, @args) = $self->buildspec($name, \@spec);
      $appns->new($name, @args, @spec);
    };
  } else {
    # print STDERR "Factory::load $name\n" if $ENV{YATT_DEBUG_LOAD};
    my ($appns, @args) = $self->buildspec($name);
    $appns->new($name, @args);
  }
}

sub buildspec {
  (my MY $self, my ($name, $args)) = @_;
  # MyApp を使いたいときは... Runenv->new(basens => 'MyApp') で。
  my $appns = $self->buildns(undef, undef
			     , $self->cutval_from($args, 'baseclass'));
  # MyApp::INST$n を作る. 親は?

  # $appns は DirHandler で Facade だから、 trans ではないことに注意。
  # trans にメンバーを足す場合は、facade にも足して、かつ cf_delegate しておかないとだめ。

  my @args = (vfs => [dir => $name, encoding => $self->{cf_tmpl_encoding}]
	      , package => $appns->rootns_for($appns)
	      , nsbuilder => sub {
		build_entns(TMPL => $appns, $appns->EntNS);
	      }
	      , $self->configparams);

  ($appns, @args);
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

sub cutval_from {
  my ($pack, $list, $key) = @_;
  if ($list) {
    for (my $i = 0; $i < @$list; $i += 2) {
      if (defined $list->[$i] and $list->[$i] eq $key) {
	(undef, my $value) = splice @$list, $i, 2;
	return $value;
      }
    }
  }
  return undef;
}

1;
