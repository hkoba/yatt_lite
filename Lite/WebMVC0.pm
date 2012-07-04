package YATT::Lite::WebMVC0;
use strict;
use warnings FATAL => qw(all);
use Carp;
use YATT::Lite::Breakpoint;
sub MY () {__PACKAGE__}

use 5.010;

#========================================
# Dispatcher 層: Request に応じた DirApp をロードし起動する
#========================================

use parent qw(YATT::Lite::Factory);
use YATT::Lite::MFields qw/cf_noheader
			   cf_is_psgi
			   cf_debug_cgi
			   cf_debug_psgi
			   cf_psgi_static
			   cf_index_name
			   cf_backend

			   cf_session_driver
			   cf_session_config
			 /;

use YATT::Lite::Util qw(cached_in split_path catch
			lookup_path nonempty
			mk_http_status
			default ckrequire
			lexpand rootname extname untaint_any terse_dump);
use YATT::Lite::Util::CmdLine qw(parse_params);
use YATT::Lite::WebMVC0::App ();
sub DirApp () {'YATT::Lite::WebMVC0::App'}
sub default_default_app () {'YATT::Lite::WebMVC0::App'}
sub default_index_name { 'index' }

use File::Basename;

sub after_new {
  (my MY $self) = @_;
  $self->SUPER::after_new();
  $self->{cf_index_name} //= $self->default_index_name;
}

#========================================
# runas($type, $fh, \%ENV, \@ARGV)  ... for CGI/FCGI support.
#========================================

sub runas {
  (my $this, my $type) = splice @_, 0, 2;
  my MY $self = ref $this ? $this : $this->new;
  my $sub = $self->can("runas_$type")
    or die "\n\nUnknown runas type: $type";
  $sub->($self, @_);
}

sub runas_cgi;
sub runas_fcgi;

DESTROY {}
sub AUTOLOAD {
  unless (ref $_[0]) {
    confess "BUG! \$self isn't object!";
  }
  my $subName = our $AUTOLOAD;
  (my $meth = $subName) =~ s/.*:://;
  my ($type) = $meth =~ /^runas_(\w+)$/
    or confess "Unknown method! $meth";
  my $modname = MY . '::' . uc($type);
  ckrequire($modname);
  my $sub = MY->can($meth)
    or confess "Can't load implementation of '$meth'";
  goto &$sub;
}

#========================================

# Dispatcher::get_dirhandler
# -> Util::cached_in
# -> Factory::load
# -> Factory::buildspec

sub get_lochandler {
  (my MY $self, my ($location, $tmpldir)) = @_;
  $self->get_yatt($location) || do {
    $self->{loc2yatt}{$location} = $self->load_yatt("$tmpldir$location");
  };
}

sub get_dirhandler {
  (my MY $self, my $dirPath) = @_;
  $dirPath =~ s,/*$,,;
  $self->{path2yatt}{$dirPath} ||= $self->load_yatt($dirPath);
}

#----------------------------------------
# preload_handlers

sub preload_apps {
  (my MY $self, my (@dir)) = @_;
  push @dir, $self->{cf_doc_root} unless @dir;

  my @apps;
  foreach my $dir ($self->find_apps(@dir)) {
    push @apps, my $app = $self->get_dirhandler($dir);
  }
  @apps;
}

sub find_apps {
  (my MY $self, my @dir) = @_;
  require File::Find;
  my @apps;
  my $handler = sub {
    push @apps, $_ if -d;
  };
  File::Find::find({wanted => $handler
		    , no_chdir => 1
		    , follow_skip => 2}
		   , @dir
		  );
  @apps;
}

#========================================
# PSGI Adaptor
#========================================
use YATT::Lite::PSGIEnv;

sub to_app {
  (my MY $self) = @_;
#  XXX: Should check it.
#  unless (defined $self->{cf_app_root}) {
#    croak "app_root is undef!";
#  }
  unless (defined $self->{cf_doc_root}) {
    croak "document_root is undef!";
  }
  return $self->SUPER::to_app;
}

sub prepare_app {
  (my MY $self) = @_;
  $self->{cf_is_psgi} = 1;
  require Plack::Request;
  require Plack::Response;
  my $backend;
  if ($backend = $self->{cf_backend}
      and my $sub = $backend->can('startup')) {
    $sub->($backend, $self, $self->preload_apps);
  }
}

sub call {
  (my MY $self, my Env $env) = @_;

  YATT::Lite::Breakpoint::break_psgi_call();

  if (defined $self->{cf_app_root} and -e "$self->{cf_app_root}/.htdebug_env") {
    return [200
	    , ["Content-type", "text/plain"]
	    , [map {"$_\t$env->{$_}\n"} sort keys %$env]];
  }

  if (my $deny = $self->has_forbidden_path($env->{PATH_INFO})) {
    return $self->psgi_error(403, "Forbidden $deny");
  }

  # XXX: user_dir?
  my ($tmpldir, $loc, $file, $trailer) = my @pi = $self->split_path_info($env);

  if ($self->{cf_debug_psgi}) {
    if (my $errfh = fileno(STDERR) ? \*STDERR : $env->{'psgi.errors'}) {
      print $errfh join("\t", "tmpldir=$tmpldir", "loc=$loc"
			, "file=$file", "trailer=$trailer"
			, "docroot=$self->{cf_doc_root}"
			, terse_dump($env)
		       ), "\n";
    }
  }

  unless (@pi) {
    return [404, [], ["Cannot understand: ", $env->{PATH_INFO}]];
  }

  my $virtdir = "$self->{cf_doc_root}$loc";
  my $realdir = "$tmpldir$loc";
  unless (-d $realdir) {
    return [404, [], ["Not found: ", $virtdir]];
  }

  # Default index file.
  # Note: Files may placed under (one of) tmpldirs instead of docroot.
  if ($file eq '') {
    $file = "$self->{cf_index_name}.yatt";
  } elsif ($file eq $self->{cf_index_name}) {
    $file .= ".yatt";
  }

  if ($file !~ /\.(yatt|ydo)$/) {
    return $self->psgi_handle_static($env);
  }

  my $dh = $self->get_lochandler(map {untaint_any($_)} $loc, $tmpldir) or do {
    return [404, [], ["No such directory: ", $loc]];
  };

  # To support $con->param and other cgi compat methods.
  my $req = Plack::Request->new($env);

  my @params = $self->connection_param($env, [$virtdir, $loc, $file, $trailer]
				       , is_psgi => 1, cgi => $req);

  my $con = $self->make_connection(undef, @params, noheader => 1);

  my $error = catch {
    $dh->with_system($self, handle => $dh->cut_ext($file), $con, $file);
  };
  if (not $error or is_done($error)) {
    # XXX: charset
    my $res = Plack::Response->new(200);
    $res->content_type("text/html"
		       . ($self->{cf_header_charset}
			  ? qq{; charset="$self->{cf_header_charset}"}
			  : ""));
    if (my @h = $con->list_header) {
      $res->headers->header(@h);
    }
    $res->body($con->buffer);
    return $res->finalize;
  } elsif (ref $error eq 'ARRAY') {
    # redirect
    if ($self->{cf_debug_psgi}) {
      if (my $errfh = fileno(STDERR) ? \*STDERR : $env->{'psgi.errors'}) {
	print $errfh "PSGI Tuple: ", terse_dump($error), "\n";
      }
    }
    return $error;
  } else {
    # system_error. Should be treated by PSGI Server.
    die $error
  }
}

sub render {
  (my MY $self, my ($reqrec, $args, @opts)) = @_;

  # [$path_info, $subpage, $action]
  my ($path_info, @rest) = ref $reqrec ? @$reqrec : $reqrec;

  my ($tmpldir, $loc, $file, $trailer)
    = my @pi = lookup_path($path_info
			   , $self->{tmpldirs}
			   , $self->{cf_index_name}, ".yatt");
  unless (@pi) {
    die "No such location: $path_info";
  }

  my $dh = $self->get_lochandler(map {untaint_any($_)} $loc, $tmpldir) or do {
    die "No such directory: $path_info";
  };

  my $virtdir = "$self->{cf_doc_root}$loc";
  my $realdir = "$tmpldir$loc";

  my Env $env = Env->psgi_simple_env;
  $env->{PATH_INFO} = $path_info;
  $env->{REQUEST_URI} = $path_info;

  my @params = $self->connection_param($env, [$virtdir, $loc, $file, $trailer]);

  if (@rest == 2 and defined $rest[-1] and ref $args eq 'HASH') {
    require Hash::MultiValue;
    push @params, hmv => Hash::MultiValue->from_mixed($args);
  }

  my $con = $self->make_connection(undef, @params, noheader => 1);

  $dh->render_into($con, @rest ? [$file, @rest] : $file, $args, @opts);

  $con->buffer;
}

sub psgi_handle_static {
  (my MY $self, my Env $env) = @_;
  my $app = $self->{cf_psgi_static} || do {
    require Plack::App::File;
    Plack::App::File->new(root => $self->{cf_doc_root})->to_app;
  };
  $app->($env);
}

sub psgi_error {
  (my MY $self, my ($status, $msg, @rest)) = @_;
  return [$status, ["Content-type", "text/plain", @rest], [$msg]];
}

sub is_done {
  defined $_[0] and ref $_[0] eq 'SCALAR' and not ref ${$_[0]}
    and ${$_[0]} eq 'DONE';
}

#========================================

sub split_path_info {
  (my MY $self, my Env $env) = @_;

  if (nonempty($env->{PATH_TRANSLATED})
      && $self->is_path_translated_mode($env)) {
    #
    # [1] PATH_TRANSLATED mode.
    #
    # If REDIRECT_STATUS == 200 and PATH_TRANSLATED is not empty,
    # use it as a template path. It must be located under app_root.
    #
    # In this case, PATH_TRANSLATED should be valid physical path
    # + optionally trailing sub path_info.
    #
    # XXX: What should be done when app_root is empty?
    # XXX: Is userdir ok? like /~$USER/dir?
    # XXX: should have cut_depth option.
    #
    split_path($env->{PATH_TRANSLATED}, $self->{cf_app_root});
    # or die.

  } else {
    #
    # [2] Template lookup mode.
    #
    lookup_path($env->{PATH_INFO}
		, $self->{tmpldirs}
		, $self->{cf_index_name}, ".yatt");
    # or die
  }
}

sub has_forbidden_path {
  (my MY $self, my $path) = @_;
  given ($path) {
    when (m{\.lib(?:/|$)}) {
      return ".lib: $path";
    }
    when (m{(?:^|/)\.ht|\.ytmpl$}) {
      # XXX: basename() is just to ease testing.
      return "filetype: " . basename($path);
    }
  }
}

sub is_path_translated_mode {
  (my MY $self, my Env $env) = @_;
  ($env->{REDIRECT_STATUS} // 0) == 200
}

# XXX: kludge! redundant!
sub split_path_url {
  (my MY $self, my ($path_translated, $path_info, $document_root)) = @_;

  my @info = do {
    if ($path_info =~ s{^(/~[^/]+)(?=/)}{}) {
      my $user = $1;
      my ($root, $loc, $file, $trailer)
	= split_path($path_translated
		     , substr($path_translated, 0
			      , length($path_translated) - length($path_info))
		     , 0
		    );
      (dir => "$root$loc", file => $file, subpath => $trailer
       , root => $root, location => "$user$loc");
    } else {
      my ($root, $loc, $file, $trailer)
	= split_path($path_translated, $document_root, 0);
      (dir => "$root$loc", file => $file, subpath => $trailer
       , root => $root, location => $loc);
    }
  };

  if (wantarray) {
    @info
  } else {
    my %info = @info;
    \%info;
  }
}

# どこを起点に split_path するか。UserDir の場合は '' を返す。
sub document_dir {
  (my MY $self, my $cgi) = @_;
  my $path_info = $cgi->path_info;
  if (my ($user) = $path_info =~ m{^/~([^/]+)/}) {
    '';
  } else {
    $self->{cf_doc_root} // '';
  }
}

#========================================

#========================================

sub connection_param {
  (my MY $self, my ($env, $quad, @rest)) = @_;
  my ($virtdir, $loc, $file, $subpath) = @$quad;
  (env => $env
   , dir => $virtdir
   , location => $loc
   , file => $file
   , subpath => $subpath
   , system => $self

   , defined $self->{cf_backend} ? (backend => $self->{cf_backend}) : ()

   # May be overridden.
   , root => $self->{cf_doc_root}  # XXX: is this ok?
   , $self->cf_delegate_defined(qw(is_psgi))

   # override by explict ones
   , @rest
  );
}


#========================================

use YATT::Lite::WebMVC0::Connection;
sub Connection () {'YATT::Lite::WebMVC0::Connection'}
sub ConnProp () {Connection}

sub make_connection {
  (my MY $self, my ($fh, @args)) = @_;
  my @opts = do {
    if ($self->{cf_noheader}) {
      # direct mode.
      ($fh, noheader => 1);
    } else {
      # buffered mode.
      (undef, parent_fh => $fh);
    }
  };
  if (my $enc = $$self{cf_output_encoding}) {
    push @opts, encoding => $enc;
  }
  $self->SUPER::make_connection(@opts, @args);
}

sub finalize_connection {
  my MY $self = shift;
  my ConnProp $prop = (my $glob = shift)->prop;
  $self->session_flush($glob) if $prop->{session};
}

#========================================
# Session support, based on CGI::Session.

#
# This will be called back from $CON->get_session.
#
sub session_load {
  my MY $self = shift;
  my ConnProp $prop = (my $con = shift)->prop;
  my ($brand_new, @with_init) = @_;

  require CGI::Session;
  my $method = $brand_new ? 'new' : 'load';
  my %opts = lexpand($self->{cf_session_config});
  my $sid_key = $opts{name} ||= $self->default_session_sid_key;

  my $expire = delete($opts{expire}) // $self->default_session_expire;
  my ($type, $driver_opts) = lexpand($self->{cf_session_driver});
  my $sess = CGI::Session->$method($type, $con->cookies_in->{$sid_key}
				   , $driver_opts, \%opts);
  unless ($sess) {
    $self->error("Session object is empty!");
  }

  $sess->expire($expire);

  if ($brand_new and $sess->is_new) {
    $con->set_cookie($sess->cookie(-path => $con->location));
  }

  foreach my $spec (@with_init) {
      if (ref $spec eq 'ARRAY') {
	my ($name, @value) = @$spec;
	$sess->param($name, @value > 1 ? \@value : $value[0]);
      } elsif (not ref $spec or ref $spec eq 'Regexp') {
	$spec = qr{^\Q$spec} unless ref $spec;
	foreach my $name ($con->param) {
	  next unless $name =~ $spec;
	  my (@value) = $con->param($name);
	  $sess->param($name, @value > 1 ? \@value : $value[0]);
	}
      } else {
	$self->error("Invalid session initializer: %s"
		     , terse_dump($spec));
      }
  }

  $prop->{session} = $sess;
}

sub session_destroy {
  my MY $self = shift;
  my ConnProp $prop = (my $con = shift)->prop;
  my $sess = delete $prop->{session};

  $sess->delete;
  $sess->flush;

  my $name = $self->{cf_session_config}{name} || $self->default_session_sid_key;
  my @rm = ($name, '', -expires => '-10y', -path => $con->location);
  $con->set_cookie(@rm);
}

sub session_flush {
  my MY $self = shift;
  my ConnProp $prop = (my $glob = shift)->prop;
  my $sess = $prop->{session}
    or return;
  return if $sess->errstr;
  $sess->flush;
  if (my $err = $sess->errstr) {
    local $prop->{session};
    $self->error("Can't flush session: %s", $err);
  }
}

sub configure_use_session {
  (my MY $self, my $value) = @_;
  if ($value) {
    $self->{cf_session_config}
      //= ref $value ? $value : [$self->default_session_config];
    $self->{cf_session_driver} //= [$self->default_session_driver];
  }
}

sub default_session_driver  { ("driver:file" => {}) }
sub default_session_config  { (Directory => '@tmp/sess') }
sub default_session_expire  { '1d' }
sub default_session_sid_key { 'SID' }

#========================================
# misc.
#========================================

sub header_charset {
  (my MY $self) = @_;
  $self->{cf_header_charset} || $self->{cf_output_encoding};
}

YATT::Lite::Breakpoint::break_load_dispatcher();

1;
