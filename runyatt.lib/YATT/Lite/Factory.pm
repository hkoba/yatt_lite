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


use YATT::Lite::Util qw(lexpand globref untaint_any ckdo ckrequire);
use YATT::Lite::XHF;

require YATT::Lite;

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
sub after_new {
  (my MY $self) = @_;
  unless ($self->{cf_appns}) {
    croak "appns is empty!";
  }
  if (not $self->{cf_allow_missing_dir}
      and $self->{cf_document_root}
      and not -d $self->{cf_document_root}) {
    croak "document_root '$self->{cf_document_root}' is missing!";
  }
  my $appbase = $self->default_appbase;
  ckrequire($appbase);

  my $entns = $appbase->ensure_entns($self->{cf_appns});

  $self->{baseclass} = \ my @base;
  foreach my $tmpldir (map {
    File::Spec->canonpath($_)
  } lexpand($self->{cf_tmpldirs})) {
    push @base, ref $self->load_yatt(TMPL => $tmpldir, $appbase);
  }

  @base = $appbase unless @base;

  if ($self->{cf_document_root}) {
    $self->load_yatt(INST => $self->{cf_document_root}, @base);
  }
}

#========================================

sub get_pathns {
  (my MY $self, my $path) = @_;
  $path =~ s,/*$,/,;
  $self->{path2pkg}{$path};
}

sub load_yatt {
  (my MY $self, my ($kind, $path, @base)) = @_;
  if (not $self->{cf_allow_missing_dir} and not -d $path) {
    croak "$kind '$path' is missing!";
  } elsif (-e (my $cf = untaint_any($path) . "/.htyattconfig.xhf")) {
    _with_loading_file {$self} $cf, sub {
      my %spec = $self->read_file_xhf($cf, binary => $self->{cf_binary_config});
      my $base = delete $spec{baseclass};
      $self->build_yatt($kind, $path, [@base, lexpand($base)], %spec);
    };
  } else {
    $self->build_yatt($kind, $path, [@base]);
  }
}

sub build_yatt {
  (my MY $self, my ($kind, $path, $base, @opts)) = @_;
  $path =~ s,/*$,/,;
  my $appns = $self->{path2pkg}{$path} = $self->buildns($kind => $base);

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
  (my MY $self, my ($kind, $baseclasslst)) = @_;
  my $appns = $self->SUPER::buildns($kind, $baseclasslst);

  my $appbase = $self->default_appbase;
  unless ($appns->isa($appbase)) {
    $self->add_isa($appns, $appbase);
  }

  # EntNS を足し、Entity も呼べるようにする。
  # $appbase->ensure_entns($appns);
  $appbase->define_Entity(undef, $appns
			  , map {$_->EntNS} lexpand($baseclasslst));

  # instns には MY を定義しておく。
  my $my = globref($appns, 'MY');
  unless (*{$my}{CODE}) {
    *$my = sub () { $appns };
  }

  $appns;
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

1;
