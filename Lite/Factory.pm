package YATT::Lite::Factory;
use strict;
use warnings FATAL => qw(all);
use Carp;
use YATT::Lite::Breakpoint;
sub MY () {__PACKAGE__}

use 5.010;
use Scalar::Util qw(weaken);

use parent qw(YATT::Lite::NSBuilder File::Spec);
use File::Path ();

use YATT::Lite::MFields qw/cf_doc_root
			   cf_allow_missing_dir
			   cf_app_base
			   cf_site_prefix

			   tmpldirs

			   loc2yatt
			   path2yatt

			   tmpl_cache

			   cf_binary_config

			   cf_tmpl_encoding cf_output_encoding
			   cf_header_charset
			   cf_debug_cgen

			   cf_only_parse cf_namespace
			   cf_offline
			  /;


use YATT::Lite::Util::AsBase;
use YATT::Lite::Util qw/lexpand globref untaint_any ckrequire dofile_in
			lookup_dir fields_hash
			secure_text_plain
		       /;
use YATT::Lite::XHF;

use YATT::Lite::Partial::ErrorReporter;
use YATT::Lite::Partial::AppPath;

use YATT::Lite qw/Entity *SYS *YATT *CON/;

#========================================
#
#
#

our $yatt_loading;
sub loading { $yatt_loading }

sub find_load_factory_script {
  my ($pack, %opts) = @_;
  my ($found) = $pack->find_factory_script(delete $opts{dir})
    or return;
  my $self = $pack->load_factory_script($found);
  $self->configure(%opts);
  $self;
}

sub load_factory_offline {
  shift->find_load_factory_script(offline => 1, @_);
}

sub configure_offline {
  (my MY $self, my $value) = @_;
  $self->{cf_offline} = $value;
  if ($self->{cf_offline}) {
    $self->configure(error_handler => sub {
		       my ($type, $err) = @_;
		       die $err;
		     })
  }
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
    my $sub = $pack->sandbox_dofile($fn);
    $sub2app{$sub};
  }
  sub prepare_app { return }

  our $load_count;
  sub sandbox_dofile {
    my ($pack, $file) = @_;
    my $sandbox = sprintf "%s::Sandbox::S%d", __PACKAGE__, ++$load_count;
    my @__result__;
    if (wantarray) {
      @__result__ = dofile_in($sandbox, $file);
    } else {
      $__result__[0] = dofile_in($sandbox, $file);
    }
    my $sym = globref($sandbox, 'filename');
    unless (*{$sym}{CODE}) {
      *$sym = sub {$file};
    }
    wantarray ? @__result__ : $__result__[0];
  }
}

sub load_factory_script {
  my ($pack, $fn) = @_;
  local $yatt_loading = 1;
  if ($fn =~ /\.psgi$/) {
    $pack->load_psgi_script($fn);
  } else {
    $pack->sandbox_dofile($fn);
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

  $self->{cf_site_prefix} //= "";

  $self->{tmpldirs} = [];
  if (my $dir = $self->{cf_doc_root}) {
    push @{$self->{tmpldirs}}, $dir;
    $self->get_yatt('/');
  }
}

#========================================

# location => yatt (dirhandler, dirapp)

sub get_yatt {
  (my MY $self, my $loc) = @_;
  if (my $yatt = $self->{loc2yatt}{$loc}) {
    return $yatt;
  }
#  print STDERR Carp::longmess("get_yatt for $loc"
#			      , YATT::Lite::Util::terse_dump($self->{tmpldirs}));
  my ($realdir, $basedir) = lookup_dir(trim_slash($loc), $self->{tmpldirs});
  unless ($realdir) {
    $self->error("Can't find template directory for location '%s'", $loc);
  }
  $self->{loc2yatt}{$loc} = $self->load_yatt($realdir, $basedir);
}

# phys-path => yatt

sub load_yatt {
  (my MY $self, my ($path, $basedir, $cycle)) = @_;
  $path = $self->rel2abs($path, $self->{cf_app_root});
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
      $self->build_yatt($path, $basedir, $cycle
			, $self->read_file_xhf($cf, binary => $self->{cf_binary_config}));
    };
  } else {
    $self->build_yatt($path, $basedir, $cycle);
  }
}

sub build_yatt {
  (my MY $self, my ($path, $basedir, $cycle, %opts)) = @_;
  trim_slash($path);

  my $app_name = $self->app_name_for($path, $basedir);

  #
  # base package と base vfs object の決定
  #
  my (@basepkg, @basevfs);
  if (my $explicit = delete $opts{base}) {
    $self->_list_base_spec_in($path,$explicit, 0, $cycle, \@basepkg, \@basevfs);
  } elsif (my $default = $self->{cf_app_base}) {
    $self->_list_base_spec_in($path, $default, 1, $cycle, \@basepkg, \@basevfs);
  }

  my $app_ns = $self->buildns(INST => \@basepkg, $path);

  if (-e (my $rc = "$path/.htyattrc.pl")) {
    # Note: This can do "use fields (...)"
    dofile_in($app_ns, $rc);
  }

  my @args = (vfs => [dir => $path, encoding => $self->{cf_tmpl_encoding}
		      , @basevfs ? (base => \@basevfs) : ()]
	      , dir => $path
	      , app_ns => $app_ns
	      , app_name => $app_name
	      , factory => $self

	      # XXX: Design flaw! Use of tmpl_cache will cause problem.
	      # because VFS->create for base do not respect Factory->get_yatt.
	      # To solve this, I should redesign all Factory/VFS related stuffs.
	      # , tmpl_cache => $self->{tmpl_cache} //= {}

	      , $self->configparams_for(fields_hash($app_ns)));

  if (my @unk = $app_ns->YATT::Lite::Object::cf_unknowns(%opts)) {
    $self->error("Unknown option for yatt app '%s': '%s'"
		 , $path, join(", ", @unk));
  }

  $self->{path2yatt}{$path} = $app_ns->new(@args, %opts);
}

sub _list_base_spec_in {
  (my MY $self, my ($in, $desc, $is_default, $cycle, $basepkg, $basevfs)) = @_;
  my ($base, @mixin) = lexpand($desc)
    or return;

  foreach my $task ([1, $base], [0, @mixin]) {
    my ($primary, @spec) = @$task;
    foreach my $basespec (@spec) {
      my ($pkg, $yatt);
      if ($basespec =~ /^::(.*)/) {
	ckrequire($1);
	$pkg = $1;
      } elsif (my $realpath = $self->app_path_find_dir_in($in, $basespec)) {
	if (defined $cycle->{$realpath}) {
	  next if $is_default;
	  $self->error("Template config error! base has cycle!: %s\n"
		       , join("\n  -> ", (sort {$cycle->{$a} <=> $cycle->{$b}}
					  keys %$cycle)
			     , $realpath));
	}
	$yatt = $self->load_yatt($realpath, undef, $cycle);
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

#========================================

sub buildns {
  (my MY $self, my ($kind, $baselist, $path)) = @_;
  my $newns = $self->SUPER::buildns($kind, $baselist, $path);

  # EntNS を足し、Entity も呼べるようにする。
  $self->{default_app}->define_Entity(undef, $newns
				      , map {$_->EntNS} @$baselist);

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
			      , qw(output_encoding header_charset
				   tmpl_encoding
				   debug_cgen
				   at_done app_root
				   namespace only_parse))
   , (exists $hash->{cf_error_handler}
      ? (error_handler => \ $self->{cf_error_handler}) : ())
   , die_in_error => ! YATT::Lite::Util::is_debugging());
}

# XXX: Should have better interface.
sub error {
  (my MY $self, my ($fmt, @args)) = @_;
  croak sprintf $fmt, @args;
}

#========================================

sub app_name_for {
  (my MY $self, my ($path, $basedir)) = @_;
  ensure_slash($path);
  if ($basedir) {
    ensure_slash($basedir = $self->rel2abs($basedir));
    $self->_extract_app_name($path, $basedir)
      // $self->error("Can't extract app_name path=%s, base=%s"
		      , $path, $basedir);
  } else {
    foreach my $tmpldir (lexpand($self->{tmpldirs})) {
      ensure_slash(my $cp = $tmpldir);
      if (defined(my $app_name = $self->_extract_app_name($path, $cp))) {
	# Can be empty string.
	return $app_name;
      }
    }
    return '';
  }
}

sub _extract_app_name {
  (my MY $self, my ($path, $basedir)) = @_;
  my ($bs, $name) = unpack('A'.length($basedir).'A*', $path);
  return undef unless $bs eq $basedir;
  $name =~ s{/+$}{};
  $name;
}

sub trim_slash {
  $_[0] =~ s,/*$,,;
  $_[0];
}

sub ensure_slash {
  unless (defined $_[0] and $_[0] ne '') {
    $_[0] = '/';
  } else {
    $_[0] =~ s{^/?(.*?)/?$}{/$1/}; # Both of start/end must be '/'.
  }
}

#========================================
sub Connection () {'YATT::Lite::Connection'};

sub make_connection {
  (my MY $self, my ($fh, @params)) = @_;
  require YATT::Lite::Connection;
  $self->Connection->create($fh, @params);
}

sub finalize_connection {}

#========================================
#
# Hook for subclassing
#
sub run_dirhandler {
  (my MY $self, my ($dh, $con, $file)) = @_;
  local ($SYS, $YATT, $CON) = ($self, $dh, $con);
  $self->before_dirhandler($dh, $con, $file);
  $self->invoke_dirhandler($dh, $con
			   , handle => $dh->cut_ext($file), $con, $file);
  $self->after_dirhandler($dh, $con, $file);
}

sub before_dirhandler {}
sub after_dirhandler {}

sub invoke_dirhandler {
  (my MY $self, my ($dh, $con, $method, @args)) = @_;
  $dh->with_system($self, $method, @args);
}

#========================================
{
  Entity site_prefix => sub {
    my MY $self = $SYS;
    $self->{cf_site_prefix};
  };
}


1;
