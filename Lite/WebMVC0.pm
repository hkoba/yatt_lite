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
use YATT::Lite::MFields qw/cf_is_gateway
			   cf_is_psgi
			   cf_debug_cgi
			   cf_debug_psgi
			   cf_psgi_static
			   cf_index_name
			   cf_backend
			 /;

# XXX: Should rename is_gateway to: is_online, is_http or (inverted) noheader.

use YATT::Lite::Util qw(cached_in split_path catch
			lookup_path
			mk_http_status
			default
			lexpand rootname extname untaint_any terse_dump);
use YATT::Lite::Util::CmdLine qw(parse_params);
use YATT::Lite::WebMVC0::App qw/*SYS/; # Adds Entity, *CON, *YATT, *SYS
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
sub configparams_for {
  (my MY $self, my $hash) = splice @_, 0, 2;
  ($self->SUPER::configparams_for($hash, @_)
   , is_gateway => $self->is_gateway)
}

#========================================
# PSGI Adaptor
#========================================
use YATT::Lite::PSGIEnv;

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

  my $con = $self->make_connection_for($dh, undef, @params);

  my $error = catch {
    $dh->handle($dh->cut_ext($file), $con, $file);
    $con->flush;
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

  my $con = $self->make_connection_for($dh, undef, @params);

  $dh->render_into($con, @rest ? [$file, @rest] : $file, $args, @opts);

  $con->flush;
  $con->buffer;
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

#========================================

use YATT::Lite::WebMVC0::Connection;
sub Connection () {'YATT::Lite::WebMVC0::Connection'}
sub ConnProp () {Connection}

sub make_connection_for {
  (my MY $self, my DirApp $dh, my ($fh, @args)) = @_;
  my @opts = do {
    if ($self->is_gateway) {
      # buffered mode.
      (undef
       , parent_fh => $fh
       , charset => ($$dh{cf_header_charset}
		     || $$dh{cf_output_encoding}
		     || $$self{cf_header_charset}
		     || $$self{cf_output_encoding})
       , header => sub {
	 my ($con) = shift;
	 # die "\n\nconnection->{cf_header} is called\n";
	 $con->mkheader(200, $con->list_baked_cookie);
       });
    } else {
      # direct mode.
      $fh
    }
  };
  if (my $enc = $$dh{cf_output_encoding} || $$self{cf_output_encoding}) {
    push @opts, encoding => $enc;
  }
  $self->make_connection(@opts, @args);
}

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
   , is_gateway => $self->is_gateway

   # override by explict ones
   , @rest
  );
}

#========================================

sub dispatch {
  (my MY $self, my $fh, my Env $env, my ($args, $opts)) = @_;
  # XXX: 本当は make_cgi 自体を廃止したい。
  my @params = $self->make_cgi($env, $args, $opts);
#  {
#    my %params = @params;
#    $self->dump_pairs($fh
#		      , params => [$params{cgi}->param]
#		      , qstr => $env->{QUERY_STRING}
#		      , cgi => $params{cgi}
#		     ); return;
#  }

  my ($dh, $con) = $self->run_dirhandler($fh, @params);
  # $con->commit を呼ぶときに $YATT, $CON が埋まっているようにするため
  $dh->commit($con);
  $con;
}

sub run_dirhandler {
  (my MY $self, my ($fh, %params)) = @_;
  # dirhandler は必ず load することにする。 *.yatt だけでなくて *.ydo でも。
  # 結局は機能集約モジュールが欲しくなるから。
  # そのために、 dirhandler は死重を減らすよう、部分毎に delayed load する

  my $dh = $self->get_dirhandler(untaint_any($params{dir}))
    or die "Unknown directory: $params{dir}";
  # XXX: cache のキーは相対パスか、絶対パスか?

  my $con = $self->make_connection_for($dh, $fh, %params);

  $dh->handle($dh->cut_ext($params{file}), $con, $params{file});

  wantarray ? ($dh, $con) : $con;
}

sub runas {
  (my $this, my $type) = splice @_, 0, 2;
  my MY $self = ref $this ? $this : $this->new;
  my $sub = $self->can("runas_$type")
    or die "\n\nUnknown runas type: $type";
  $sub->($self, @_);
}

sub runas_cgi {
  (my MY $self, my $fh, my Env $env, my ($args, %opts)) = @_;
  if (-e ".htdebug_env") {
    $self->printenv($fh, $env);
    return;
  }

  $self->init_by_env($env);

  unless ($env->{GATEWAY_INTERFACE}) {
    # コマンド行起動時
    require Cwd;
    local $env->{GATEWAY_INTERFACE} = $self->{cf_is_gateway} = 'CGI/YATT';
    local $env->{REQUEST_METHOD} //= 'GET';
    local @{$env}{qw(PATH_TRANSLATED REDIRECT_STATUS)}
      = (Cwd::abs_path(shift @$args), 200)
	if @_;
    $self->dispatch($fh, $env, $args, \%opts);
  } elsif ($self->is_gateway) {
    if (defined $fh and fileno($fh) >= 0) {
      open STDERR, '>&', $fh or die "can't redirect STDERR: $!";
    }
    eval { $self->dispatch($fh, $env, $args, \%opts) };
    if (not $@ or is_done($@)) {
      # NOP
    } elsif (ref $@ eq 'ARRAY') {
      # Non local exit with PSGI response triplet.
      $self->cgi_response($fh, $env, @{$@});

    } else {
      # Unknown error.
      $self->show_error($fh, $@, $env);
    }
  } else {
    $self->dispatch($fh, $env, $args, \%opts);
  }
}

sub is_done {
  defined $_[0] and ref $_[0] eq 'SCALAR' and not ref ${$_[0]}
    and ${$_[0]} eq 'DONE';
}

########################################
#
# FastCGI support, based on PSGI mode.
#
########################################

# runas_fcgi() is basically designed for Apache's dynamic fastcgi.
# If you want psgi.multiprocess, use psgi mode directly.

sub runas_fcgi {
  (my MY $self, my $fhset, my Env $init_env, my ($args, %opts)) = @_;
  # $fhset is either stdout or [\*STDIN, \*STDOUT, \*STDERR].
  # $init_env is just discarded.
  # $args = \@ARGV
  # %opts is fcgi specific options.

  local $self->{cf_is_psgi} = 1;

  # In suexec fcgi, $0 will not be absolute path.
  my $progname = $0 if $0 =~ m{^/};

  my ($stdin, $stdout, $stderr) = ref $fhset eq 'ARRAY' ? @$fhset
    : (\*STDIN, $fhset, $opts{isolate_stderr} ? \*STDERR : $fhset);

  require FCGI;
  my $sock = 0;
  my %env;
  my $request = FCGI::Request
    ($stdin, $stdout, $stderr
     , \%env, $sock, $opts{nointr} ? 0 :&FCGI::FAIL_ACCEPT_ON_INTR);

  my ($dir, $age);
  local $self->{cf_at_done} = sub {die \"DONE"};
  while ($request->Accept >= 0) {
    my Env $env = $self->psgi_fcgi_newenv(\%env, $stdin, $stderr);
    $self->init_by_env($env);
    unless (defined $progname) {
      $progname = $env->{SCRIPT_FILENAME}
	or die "\n\nSCRIPT_FILENAME is empty!\n";
    }
    unless (defined $dir) {
      $dir = dirname($progname);
      $age = -M $progname;
    }

    if (-e "$dir/.htdebug_env") {
      $self->printenv($stdout, $env);
      next;
    }

    # 出力の基本動作は streaming.
    eval { $self->dispatch($stdout, $env) };

    # 正常時は全て出力が済んだ後に制御が戻ってくる。
    if (not $@ or is_done($@)) {
      # NOP
    } elsif (ref $@ eq 'ARRAY') {
      # Non local exit with PSGI response triplet.
      $self->cgi_response($stdout, $env, @{$@});

    } else {
      # Unknown error.
      $self->show_error($stdout, $@, $env);
    }

    last if -e $progname and -M $progname < $age;
  }
}

# Extracted and modified from Plack::Handler::FCGI.

sub psgi_fcgi_newenv {
  (my MY $self, my Env $init_env, my ($stdin, $stderr)) = @_;
  require Plack::Util;
  require Plack::Request;
  my Env $env = +{ %$init_env };
  $env->{'psgi.version'} = [1,1];
  $env->{'psgi.url_scheme'}
    = ($init_env->{HTTPS}||'off') =~ /^(?:on|1)$/i ? 'https' : 'http';
  $env->{'psgi.input'}        = $stdin  || *STDIN;
  $env->{'psgi.errors'}       = $stderr || *STDERR;
  $env->{'psgi.multithread'}  = &Plack::Util::FALSE;
  $env->{'psgi.multiprocess'} = &Plack::Util::FALSE; # XXX:
  $env->{'psgi.run_once'}     = &Plack::Util::FALSE;
  $env->{'psgi.streaming'}    = &Plack::Util::FALSE; # XXX: Todo.
  $env->{'psgi.nonblocking'}  = &Plack::Util::FALSE;
  # delete $env->{HTTP_CONTENT_TYPE};
  # delete $env->{HTTP_CONTENT_LENGTH};
  $env;
}

sub cgi_response {
  (my MY $self, my ($fh, $env, $code, $headers, $body)) = @_;
  my $header = mk_http_status($code);
  while (my ($k, $v) = splice @$headers, 0, 2) {
    $header .= "$k: $v\015\012";
  }
  $header .= "\015\012";

  print {*$fh} $header;
  print {*$fh} @$body;
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

#========================================
# XXX: $env 渡し中心に変更する. 現状では...
# [1] $fh, $cgi を外から渡すケース... そもそも、これを止めるべき. $env でええやん、と。
# [2] $fh, $file, []/{}
# [3] $fh, $file, k=v, k=v... のケース

sub make_cgi {
  (my MY $self, my Env $env, my ($args, $opts)) = @_;
  my ($cgi, $root, $loc, $file, $trailer);
  if ($self->is_gateway) {
    $cgi = do {
      if ($self->{cf_is_psgi}) {
	require Plack::Request;
	Plack::Request->new($env);
      } elsif (ref $args and UNIVERSAL::can($args, 'param')) {
	$args;
      } else {
	$self->new_cgi(@$args);
      }
    };

    ($root, $loc, $file, $trailer) = my @pi = $self->split_path_info($env);

    # XXX: /~user_dir の場合は $dir ne $root$loc じゃんか orz...

  } else {
    my $path = shift @$args;
    unless (defined $path) {
      die "Usage: $0 tmplfile args...\n";
    }
    unless ($path =~ m{^/}) {
      unless (-e $path) {
	 die "No such file: $path\n";
      }
      # XXX: $path が相対パスだったら?この時点で abs 変換よね？
      require Cwd;		# でも、これで 10ms 遅くなるのよね。
      $path = Cwd::abs_path($path) // die "No such file: $path\n";
    }
    # XXX: widget 直接呼び出しは？ cgi じゃなしに、直接パラメータ渡しは？ =>
    ($root, $loc, $file, $trailer) = split_path($path, $self->{cf_app_root});
    $cgi = $self->new_cgi(@$args);
  }

  $self->connection_param($env, ["$root$loc", $loc, $file, $trailer]
			  , cgi => $cgi, root => $root, is_psgi => 0);
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

#----------------------------------------

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
sub init_by_env {
  (my MY $self, my Env $env) = @_;
  $self->{cf_is_gateway} //= $env->{GATEWAY_INTERFACE} if $env->{GATEWAY_INTERFACE};
  $self->{cf_doc_root} //= $env->{DOCUMENT_ROOT} if $env->{DOCUMENT_ROOT};
  $self;
}

sub new_cgi {
  my MY $self = shift;
  my (@params) = do {
    unless (@_) {
      ()
    } elsif (@_ > 1 or defined $_[0] and not ref $_[0]) {
      $self->parse_params(\@_, {})
    } elsif (not defined $_[0]) {
      ();
    } elsif (ref $_[0] eq 'ARRAY') {
      my %hash = @{$_[0]};
      \%hash;
    } else {
      $_[0];
    }
  };
  require CGI; CGI->new(@params);
  # shift; require CGI::Simple; CGI::Simple->new(@_);
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

sub nonempty { defined $_[0] && $_[0] ne '' }

# XXX: $cgi で制御できた方が嬉しい? それとも Runenv 自体の特性と考える？
# XXX: 名前が不適切。
sub is_gateway {
  my MY $self = shift;
  $self->{cf_debug_cgi} // $self->{cf_is_gateway};
}

sub printenv {
  (my MY $self, my ($fh, $env)) = @_;
  $self->dump_pairs($fh, map {$_ => $env->{$_}} sort keys %$env);
}

sub dump_pairs {
  (my MY $self, my ($fh)) = splice @_, 0, 2;
  print $fh "\n\n";
  while (my ($name, $value) = splice @_, 0, 2) {
    print $fh $name, "\t", terse_dump($value), "\n";
  }
}

sub show_error {
  (my MY $self, my ($fh, $error, $cgi)) = @_;
  # XXX: Is text/plain secure?
  print $fh "Content-type: text/plain\n\n$@";
}

sub NIMPL { croak "\n\nNot yet implemented" }

YATT::Lite::Breakpoint::break_load_dispatcher();

1;

__END__


runas_cgi/runas_fcgi            call($env)

dispatch

make_cgi

run_dirhandler

get_dirhandler                  get_dirhandler

$d->make_connection             $d->make_connection

$d->handle                      $d->handle


$c->commit
$c->flush
$c->DONE

