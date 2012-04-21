package YATT::Lite::Factory;
use strict;
use warnings FATAL => qw(all);
use Carp;
use YATT::Lite::Breakpoint;
sub MY () {__PACKAGE__}

use base qw(YATT::Lite::NSBuilder);
use fields qw(cf_document_root
	      cf_tmpldirs
	      path2pkg
	      path2yatt
	      loc2yatt
	      baseclass

	      cf_allow_missing_dir

	      cf_binary_config

	      cf_tmpl_encoding cf_output_encoding
	      cf_header_charset
	      cf_debug_cgen

	      cf_only_parse cf_namespace
	      cf_error_handler

	      cf_at_done
);


use YATT::Lite::Util qw(lexpand globref untaint_any ckdo ckrequire dofile_in);
use YATT::Lite::XHF;

require YATT::Lite;
require File::Spec;

#========================================
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

sub configure_appns {
  (my MY $self, my $appns) = @_;
  $self->{cf_appns} = $appns;
  if (not $self->{cf_allow_missing_dir}
      and $self->{cf_document_root}
      and not -d $self->{cf_document_root}) {
    croak "document_root '$self->{cf_document_root}' is missing!";
  }
  if ($self->{cf_document_root}) {
    trim_slash($self->{cf_document_root});
  }
  # XXX: $self->{cf_tmpldirs}

  $self->{baseclass} = \ my @base;
  foreach my $tmpldir (map {
    File::Spec->canonpath($_)
  } lexpand($self->{cf_tmpldirs})) {
    push @base, ref $self->load_yatt(TMPL => $tmpldir);
  }

  if ($self->{cf_document_root}) {
    $self->{loc2yatt}{'/'}
      = $self->load_yatt(INST => $self->{cf_document_root}, @base);
  }
}

sub init_appns {
  (my MY $self) = @_;
  my $appns = $self->SUPER::init_appns;
  $self->appbase->ensure_entns($self->{cf_appns});
  $appns;
}

#========================================

sub get_pathns {
  (my MY $self, my $path) = @_;
  trim_slash($path);
  $self->{path2pkg}{$path};
}

sub load_yatt {
  (my MY $self, my ($kind, $path, @base)) = @_;
  my @basepkg = map {ref $_ || $_} @base;
  if (not $self->{cf_allow_missing_dir} and not -d $path) {
    croak "$kind '$path' is missing!";
  } elsif (-e (my $cf = untaint_any($path) . "/.htyattconfig.xhf")) {
    _with_loading_file {$self} $cf, sub {
      my %spec = $self->read_file_xhf($cf, binary => $self->{cf_binary_config});
      my $base = delete $spec{baseclass};
      # XXX: @basepkg が既に $base を継承していたら、自動で削るべき
      $self->build_yatt($kind, $path, [@basepkg, lexpand($base)], %spec);
    };
  } else {
    $self->build_yatt($kind, $path, [@basepkg]);
  }
}

sub build_yatt {
  (my MY $self, my ($kind, $path, $base, @opts)) = @_;
  trim_slash($path);
  my $appns = $self->{path2pkg}{$path}
    = $self->buildns($kind => lexpand($base));

  if (-e (my $rc = "$path/.htyattrc.pl")) {
    dofile_in($appns, $rc);
  }

  my @args = (vfs => [dir => $path, encoding => $self->{cf_tmpl_encoding}]
	      , dir => $path
	      , appns => $appns
	      , $self->configparams_for(YATT::Lite::Util::fields_hash($appns)));

  $self->{path2yatt}{$path} = $appns->new(@args, @opts);
}

#========================================

sub buildns {
  (my MY $self, my ($kind, @base)) = @_;
  my $newns = $self->SUPER::buildns($kind, @base);

  # EntNS を足し、Entity も呼べるようにする。
  $self->appbase->define_Entity(undef, $newns, map {$_->EntNS} @base);

  # instns には MY を定義しておく。
  my $my = globref($newns, 'MY');
  unless (*{$my}{CODE}) {
    *$my = sub () { $newns };
  }

  $newns;
}

sub configparams_for {
  (my MY $self, my $hash) = @_;
  my @base = map { [dir => $_] } lexpand($self->{cf_tmpldirs});

  ((@base ? (base => \@base) : ())
   , $self->cf_delegate_known(0, $hash
			      , qw(output_encoding header_charset debug_cgen
				   at_done
				   namespace only_parse error_handler))
   , die_in_error => ! YATT::Lite::Util::is_debugging());
}

sub trim_slash {
  $_[0] =~ s,/*$,,;
  $_[0];
}

1;
