package YATT::Lite::Factory;
use strict;
use warnings FATAL => qw(all);
use Carp;
use YATT::Lite::Breakpoint;
sub MY () {__PACKAGE__}

use 5.010;

use base qw(YATT::Lite::NSBuilder File::Spec);
use fields qw(cf_app_root
	      cf_doc_root
	      cf_allow_missing_dir
	      cf_default_app_base

	      tmpldirs

	      loc2yatt
	      path2yatt

	      cf_binary_config

	      cf_tmpl_encoding cf_output_encoding
	      cf_header_charset
	      cf_debug_cgen

	      cf_only_parse cf_namespace
	      cf_error_handler

	      cf_at_done
);


use YATT::Lite::Util qw(lexpand globref untaint_any ckdo ckrequire dofile_in
			lookup_dir fields_hash);
use YATT::Lite::XHF;

require YATT::Lite;

#========================================
#
#
#

our $yatt_loading;
sub loading { $yatt_loading }

sub find_load_factory_script {
  my ($pack, $dir) = @_;
  my ($found) = $pack->find_factory_script($dir)
    or return;
  $pack->load_factory_script($found);
}

sub load_factory_script {
  my ($pack, $fn) = @_;
  local $yatt_loading = 1;
  ckdo $fn;
}

sub find_factory_script {
  my $pack = shift;
  my $dir = $pack->rel2abs($_[0] // $pack->curdir);
  my @path = $pack->no_upwards($pack->splitdir($dir));
  my $rootdir = $pack->rootdir;
  while (@path and length($dir = $pack->catdir(@path)) > length($rootdir)) {
    if (my ($found) = grep {-r} map {"$dir/$_.psgi"} qw(runyatt app)) {
      return $found;
    }
  } continue { pop @path }
  return;
}

#========================================

sub _after_after_new {
  (my MY $self) = @_;
  $self->SUPER::_after_after_new;

  if (not $self->{cf_allow_missing_dir}
      and $self->{cf_doc_root}
      and not -d $self->{cf_doc_root}) {
    croak "document_root '$self->{cf_doc_root}' is missing!";
  }
  if ($self->{cf_doc_root}) {
    trim_slash($self->{cf_doc_root});
  }
  # XXX: $self->{cf_tmpldirs}

  $self->{tmpldirs} = [];
  if (my $dir = $self->{cf_doc_root}) {
    push @{$self->{tmpldirs}}, $dir;
    $self->get_yatt('/');
  }
}

sub init_app_ns {
  (my MY $self) = @_;
  $self->SUPER::init_app_ns;
  $self->{default_app}->ensure_entns($self->{app_ns});
}

#========================================

# location => yatt

sub get_yatt {
  (my MY $self, my $loc) = @_;
  if (my $yatt = $self->{loc2yatt}{$loc}) {
    return $yatt;
  }
  my $realdir = lookup_dir(trim_slash($loc), $self->{tmpldirs});
  unless ($realdir) {
    $self->error("Can't find template directory for location '%s'", $loc);
  }
  $self->{loc2yatt}{$loc} = $self->load_yatt($realdir);
}

# phys-path => yatt

sub load_yatt {
  (my MY $self, my ($path, $depth)) = @_;
  $path = $self->canonpath($path);
  if (my $yatt = $self->{path2yatt}{$path}) {
    return $yatt;
  }
  if (not $self->{cf_allow_missing_dir} and not -d $path) {
    croak "Can't find '$path'!";
  }
  if (-e (my $cf = untaint_any($path) . "/.htyattconfig.xhf")) {
    _with_loading_file {$self} $cf, sub {
      $self->build_yatt($depth, $path
			, $self->read_file_xhf($cf, binary => $self->{cf_binary_config}));
    };
  } else {
    $self->build_yatt($depth, $path);
  }
}

sub build_yatt {
  (my MY $self, my ($depth, $path, %opts)) = @_;
  trim_slash($path);

  #
  # base package と base vfs object の決定
  #
  my (@basepkg, @basevfs);
  if (my ($base, @mixin) = lexpand(delete $opts{base}
				   || ($depth ? ()
				       : $self->{cf_default_app_base}))) {
    # ::ClassName
    # relativeDir
    # @approotDir
    my ($pkg, $yatt) = $self->find_package_or_yatt($base, $depth);
    push @basepkg, $pkg;
    if ($yatt) {
      # vfs object を直接渡すべきではないか？という考えも
      # あるいは、[facade => $yatt] とか。
      push @basevfs, [dir => $yatt->cget('dir')];
    }

    foreach my $mixin (@mixin) {
      ($pkg, $yatt) = $self->find_package_or_yatt($mixin, $depth);
      if ($pkg->isa('YATT::Lite::Object')) {
	# XXX: warn
      } else {
	push @basepkg, $pkg;
      }
      if ($yatt) {
	push @basevfs, [dir => $yatt->cget('dir')];
      }
    }
  }

  # XXX: あと、reload は？！

  my $app_ns = $self->buildns(INST => @basepkg);

  if (-e (my $rc = "$path/.htyattrc.pl")) {
    dofile_in($app_ns, $rc);
  }

  my @args = (vfs => [dir => $path, encoding => $self->{cf_tmpl_encoding}
		      , @basevfs ? (base => \@basevfs) : ()]
	      , dir => $path
	      , app_ns => $app_ns
	      , $self->configparams_for(fields_hash($app_ns)));

  my $yatt = $self->{path2yatt}{$path} = $app_ns->new(@args, %opts);
  push @{$self->{tmpldirs}}, $path;
  $yatt;
}

sub find_package_or_yatt {
  (my MY $self, my ($basespec, $outer_depth)) = @_;
  if ($basespec =~ /^::/) {
    ckrequire($basespec);
    return $basespec;
  } elsif (-d (my $realpath = $self->app_path($basespec))) {
    my $yatt = $self->load_yatt($realpath, ($outer_depth // 0) +1);
    return(ref $yatt, $yatt);
  } else {
    $self->error("Can't resolve app_path '%s'", $basespec);
  }
}

sub app_path {
  (my MY $self, my $path) = @_;
  if ($path =~ s/^\@//) {
    "$self->{cf_app_root}/$path";
  } else {
    "$self->{cf_doc_root}/$path";
  }
}

#========================================

sub buildns {
  (my MY $self, my ($kind, @base)) = @_;
  my $newns = $self->SUPER::buildns($kind, @base);

  # EntNS を足し、Entity も呼べるようにする。
  $self->{default_app}->define_Entity(undef, $newns, map {$_->EntNS} @base);

  # instns には MY を定義しておく。
  my $my = globref($newns, 'MY');
  unless (*{$my}{CODE}) {
    *$my = sub () { $newns };
  }

  $newns;
}

sub configparams_for {
  (my MY $self, my $hash) = @_;
  # my @base = map { [dir => $_] } lexpand($self->{cf_tmpldirs});
  # (@base ? (base => \@base) : ())
  (
   $self->cf_delegate_known(0, $hash
			      , qw(output_encoding header_charset debug_cgen
				   at_done
				   namespace only_parse error_handler))
   , die_in_error => ! YATT::Lite::Util::is_debugging());
}

# XXX: Should have better interface.
sub error {
  (my MY $self, my ($fmt, @args)) = @_;
  croak sprintf $fmt, @args;
}

sub trim_slash {
  $_[0] =~ s,/*$,,;
  $_[0];
}

1;
