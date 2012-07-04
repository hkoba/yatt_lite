package YATT::Lite::Factory;
use strict;
use warnings FATAL => qw(all);
use Carp;
use YATT::Lite::Breakpoint;
sub MY () {__PACKAGE__}

use 5.010;
use Scalar::Util qw(weaken);

use parent qw(YATT::Lite::NSBuilder File::Spec);
use YATT::Lite::MFields qw/cf_app_root
			   cf_doc_root
			   cf_allow_missing_dir
			   cf_app_base

			   tmpldirs

			   loc2yatt
			   path2yatt

			   cf_binary_config

			   cf_tmpl_encoding cf_output_encoding
			   cf_header_charset
			   cf_debug_cgen

			   cf_only_parse cf_namespace
			  /;


use YATT::Lite::Util::AsBase;
use YATT::Lite::Util qw(lexpand globref untaint_any ckdo ckrequire dofile_in
			lookup_dir fields_hash);
use YATT::Lite::XHF;

use YATT::Lite::ErrorReporter;

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

{
  my %sub2app;
  sub to_app {
    my ($self) = @_;
    $self->prepare_app;
    my $sub = sub { $self->call(@_) };
    $sub2app{$sub} = $self;
    weaken($sub2app{$sub});
    $sub;
  }
  sub load_psgi_script {
    my ($pack, $fn) = @_;
    local $yatt_loading = 1;
    my $sub = ckdo $fn;
    $sub2app{$sub};
  }
  sub prepare_app { return }
}

sub load_factory_script {
  my ($pack, $fn) = @_;
  local $yatt_loading = 1;
  if ($fn =~ /\.psgi$/) {
    $pack->load_psgi_script($fn);
  } else {
    ckdo $fn;
  }
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

sub init_app_ns {
  (my MY $self) = @_;
  $self->SUPER::init_app_ns;
  $self->{default_app}->ensure_entns($self->{app_ns});
}

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
  (my MY $self, my ($path, $cycle)) = @_;
  $path = $self->canonpath($path);
  if (my $yatt = $self->{path2yatt}{$path}) {
    return $yatt;
  }
  $cycle //= {};
  $cycle->{$path} = keys %$cycle;
  if (not $self->{cf_allow_missing_dir} and not -d $path) {
    croak "Can't find '$path'!";
  }
  if (-e (my $cf = untaint_any($path) . "/.htyattconfig.xhf")) {
    _with_loading_file {$self} $cf, sub {
      $self->build_yatt($path, $cycle
			, $self->read_file_xhf($cf, binary => $self->{cf_binary_config}));
    };
  } else {
    $self->build_yatt($path, $cycle);
  }
}

sub build_yatt {
  (my MY $self, my ($path, $cycle, %opts)) = @_;
  trim_slash($path);

  #
  # base package と base vfs object の決定
  #
  my (@basepkg, @basevfs);
  if (my $explicit = delete $opts{base}) {
    $self->_list_base_spec($explicit, 0, $cycle, \@basepkg, \@basevfs);
  } elsif (my $default = $self->{cf_app_base}) {
    $self->_list_base_spec($default, 1, $cycle, \@basepkg, \@basevfs);
  }

  my $app_ns = $self->buildns(INST => @basepkg);

  if (-e (my $rc = "$path/.htyattrc.pl")) {
    # Note: This can do "use fields (...)"
    dofile_in($app_ns, $rc);
  }

  my @args = (vfs => [dir => $path, encoding => $self->{cf_tmpl_encoding}
		      , @basevfs ? (base => \@basevfs) : ()]
	      , dir => $path
	      , app_ns => $app_ns
	      , $self->configparams_for(fields_hash($app_ns)));

  if (my @unk = $app_ns->YATT::Lite::Object::cf_unknowns(%opts)) {
    $self->error("Unknown option for yatt app '%s': '%s'"
		 , $path, join(", ", @unk));
  }

  my $yatt = $self->{path2yatt}{$path} = $app_ns->new(@args, %opts);
  push @{$self->{tmpldirs}}, $path;
  $yatt;
}

sub _list_base_spec {
  (my MY $self, my ($desc, $is_default, $cycle, $basepkg, $basevfs)) = @_;
  my ($base, @mixin) = lexpand($desc)
    or return;

  foreach my $task ([1, $base], [0, @mixin]) {
    my ($primary, @spec) = @$task;
    foreach my $basespec (@spec) {
      my ($pkg, $yatt);
      if ($basespec =~ /^::(.*)/) {
	ckrequire($1);
	$pkg = $1;
      } elsif (-d (my $realpath = $self->app_path($basespec))) {
	if (defined $cycle->{$realpath}) {
	  next if $is_default;
	  $self->error("Template config error! base has cycle!: %s\n"
		       , join("\n  -> ", (sort {$cycle->{$a} <=> $cycle->{$b}}
					  keys %$cycle)
			     , $realpath));
	}
	$yatt = $self->load_yatt($realpath, $cycle);
	$pkg = ref $yatt;
      } else {
	$self->error("Invalid base spec: %s", $basespec);
      }
      if (not $primary and $pkg->isa('YATT::Lite::Object')) {
	# XXX: This will cause inheritance error. But...
      }
      push @$basepkg, $pkg if $primary;
      push @$basevfs, [dir => $yatt->cget('dir')] if $yatt;
    }
  }
}

sub app_path {
  (my MY $self, my $path) = @_;
  return '' unless $path =~ s/^\@//;
  "$self->{cf_app_root}/$path";
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

#----------------------------------------
sub Connection () {'YATT::Lite::Connection'};

sub make_connection {
  (my MY $self, my ($fh, @params)) = @_;
  require YATT::Lite::Connection;
  $self->Connection->create($fh, @params);
}

sub finalize_connection {}

1;
