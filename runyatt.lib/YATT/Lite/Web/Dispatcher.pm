package YATT::Lite::Web::Dispatcher;
use strict;
use warnings FATAL => qw(all);
use Carp;
use YATT::Lite::Breakpoint;
sub MY () {__PACKAGE__}

#========================================
# Dispatcher 層: DirHandler と、その他の外部Action のキャッシュ, InstNS の生成
#========================================

# caller, runtime env の捨象. Toplevel.
# DirHandler の生成, .htyattrc.pl の読み込みとキャッシュに責任を持つ.
use base qw(YATT::Lite::Factory);
use fields qw(DirHandler Action
	      cf_mount
	      cf_is_gateway cf_document_root
	      cf_appdir
	      cf_debug_cgi
	      cf_psgi_static
	    );
# XXX: Should rename: is_gateway => is_online

use YATT::Lite::Util qw(cached_in split_path catch
			lexpand rootname extname untaint_any terse_dump);
use YATT::Lite::Util::CmdLine qw(parse_params);
sub default_dirhandler () {'YATT::Lite::Web::DirHandler'}

use File::Basename;
use YATT::Lite::Web::Connection ();
sub ConnProp () {'YATT::Lite::Web::Connection'}
sub Connection () {'YATT::Lite::Web::Connection'}

#========================================
sub configparams {
  my MY $self = shift;
  ($self->SUPER::configparams
   , is_gateway => $self->is_gateway)
}

#========================================
# PSGI Adaptor
#========================================
{
  sub Env () {"YATT::Lite::Web::Dispatcher::PSGI_ENV"}
  package YATT::Lite::Web::Dispatcher::PSGI_ENV;
  use fields qw(
GATEWAY_INTERFACE
REQUEST_METHOD
SCRIPT_NAME
SCRIPT_FILENAME
DOCUMENT_ROOT

PATH_INFO
PATH_TRANSLATED
REDIRECT_STATUS
REQUEST_URI
DOCUMENT_URI

QUERY_STRING
SERVER_NAME
SERVER_PORT
SERVER_PROTOCOL
HTTP_USER_AGENT
HTTP_REFERER
HTTP_COOKIE
HTTP_FORWARDED
HTTP_HOST
HTTP_PROXY_CONNECTION
HTTP_ACCEPT

psgi.version
psgi.url_scheme
psgi.input
psgi.errors
psgi.multithread
psgi.multiprocess
psgi.run_once
psgi.nonblocking
psgi.streaming
psgix.session
psgix.session.options
psgix.logger
);
}

sub call {
  (my MY $self, my Env $env) = @_;
  my ($path_translated, $document_root) = do {
    if (($env->{REDIRECT_STATUS} // 0) != 200) {
       my $root = $self->{cf_document_root} // $env->{DOCUMENT_ROOT};
       ($root . $env->{PATH_INFO}
       , $root);
     } elsif ($env->{PATH_TRANSLATED}) {
       ($env->{PATH_TRANSLATED}
	, $env->{DOCUMENT_ROOT});
     } elsif (defined $self->{cf_document_root}
	      and $self->{cf_document_root} eq '') {
       my $doc = $env->{DOCUMENT_URI} // $env->{SCRIPT_NAME};
       my $root = $env->{DOCUMENT_ROOT};
       ($root . $doc
       , $root);
     } else {
       die "Unknown request env";
     }
   };

  my ($root, $loc, $file, $trailer)
    = split_path($path_translated, $document_root);
  if (defined $self->{cf_appdir}
      and -e "$self->{cf_appdir}/.htdebug_env") {
    return [200, ["Content-type", "text/plain"]
	    , [(map {join("\t", @$_)."\n"}
		[root => $root], [loc => $loc]
		, [file => $file], [trailer => $trailer]
	       )
	       , (map {"$_\t$env->{$_}\n"} sort keys %$env)
	      ]];
  } elsif ($ENV{DEBUG_YATT}
	   and $env->{'psgi.errors'}) {
    print {$env->{'psgi.errors'}} join("\t", "root=$root", "loc=$loc"
				       , "file=$file", "trailer=$trailer"
				       , "docroot=$self->{cf_document_root}"
				       , "path_info=$env->{PATH_INFO}"
				      ), "\n";
  }

  my $dir = "$root$loc";
  unless (-d $dir) {
    return [404, [], ["Not found: ", $dir]];
  } elsif ($loc =~ m{\.lib(?:/|$)}) {
    return $self->psgi_error(403, "Forbidden library location: $loc");
  }

  # Default index file.
  $file = 'index.yatt' if $file eq '' && -r "$dir/index.yatt";

  if ($file =~ /^\.ht|\.ytmpl$/) {
    # forbidden
    return $self->psgi_error(403, "Forbidden filetype: $file");
  } elsif ($file !~ /\.(yatt|ydo)$/) {
    return $self->psgi_handle_static($env);
  }

  my $dh = $self->get_dirhandler(untaint_any($dir));

  # To support $con->param and other cgi compat methods.
  my $req = Plack::Request->new($env);

  my @params = (cgi => $req, psgi => $env, env => $env
		, dir => $dir
		, file => $file
		, subpath => $trailer
		, system => $self
		, root => $root, location => $loc);

  my $con = $dh->make_connection(undef, @params);

  my $error = catch {
    $dh->handle($dh->trim_ext($file), $con, $file);
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
    return $error;
  } else {
    # system_error. Should be treated by PSGI Server.
    die $error
  }
}

sub to_app {
  (my MY $self) = @_;
  require Plack::Request;
  require Plack::Response;
  $self->init_by_env;
  unless (defined $self->{cf_document_root}) {
    croak "document_root is undef!";
  }
  $self->prepare_app;
  return sub { $self->call(@_) }
}

sub prepare_app { return }

sub psgi_handle_static {
  (my MY $self, my Env $env) = @_;
  my $app = $self->{cf_psgi_static} || do {
    require Plack::App::File;
    Plack::App::File->new(root => $self->{cf_document_root})->to_app;
  };
  $app->($env);
}

sub psgi_error {
  (my MY $self, my ($status, $msg, @rest)) = @_;
  return [$status, ["Content-type", "text/plain", @rest], [$msg]];
}

#========================================

sub dispatch {
  (my MY $self, my $fh, my Env $env) = splice @_, 0, 3;
  # XXX: 本当は make_cgi 自体を廃止したい。
  my @params = $self->make_cgi($env, @_);
  my ($dh, $con) = $self->run_dirhandler($fh, env => $env, @params);
  # $con->commit を呼ぶときに $YATT, $CON が埋まっているようにするため
  $dh->commit($con);
  $con;
}

sub run_dirhandler {
  (my MY $self, my ($fh, %params)) = @_;
  # dirhandler は必ず load することにする。 *.yatt だけでなくて *.ydo でも。
  # 結局は機能集約モジュールが欲しくなるから。
  # そのために、 dirhandler は死重を減らすよう、部分毎に delayed load する

  my $dh = $self->get_dirhandler(untaint_any($params{dir}));
  # XXX: cache のキーは相対パスか、絶対パスか?

  my $con = $dh->make_connection($fh, system => $self, %params);

  $dh->handle($dh->trim_ext($params{file}), $con, $params{file});

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
  (my MY $self, my $fh, my Env $env) = splice @_, 0, 3;
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
      = (Cwd::abs_path(shift), 200)
	if @_;
    $self->dispatch($fh, $env, @_);
  } elsif ($self->is_gateway) {
    if (defined $fh and fileno($fh) >= 0) {
      open STDERR, '>&', $fh or die "can't redirect STDERR: $!";
    }
    eval { $self->dispatch($fh, $env, @_) };
    die "Content-type: text/plain\n\n$@" if $@ and not is_done($@);
  } else {
    $self->dispatch($fh, $env, @_);
  }
}

sub is_done {
  defined $_[0] and ref $_[0] eq 'SCALAR' and not ref ${$_[0]}
    and ${$_[0]} eq 'DONE';
}

sub runas_fcgi {
  (my MY $self, my $fh, my Env $env) = splice @_, 0, 3;
  require CGI::Fast;
  # In suexec fcgi, $0 will not be absolute path.
  my $progname = $0 if $0 =~ m{^/};
  my ($dir, $age);
  $self->{cf_at_done} = sub {die \"DONE"};
  while (defined (my $cgi = new CGI::Fast)) {
    # XXX: reset env! use  FCGI::Accept!
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
      $self->printenv($fh, $env);
      next;
    }

    eval { $self->dispatch($fh, $cgi) };
    $self->show_error($fh, $@, $cgi) if $@ and not is_done($@); # 暫定
    last if -e $progname and -M $progname < $age;
  }
}

sub init_by_env {
  (my MY $self, my Env $env) = @_;
  $self->{cf_is_gateway} //= $env->{GATEWAY_INTERFACE} if $env->{GATEWAY_INTERFACE};
  $self->{cf_document_root} //= $env->{DOCUMENT_ROOT} if $env->{DOCUMENT_ROOT};
  $self;
}

#========================================

sub get_dirhandler {
  (my MY $self, my $dirPath) = @_;
  $self->cached_in($self->{DirHandler} ||= {}, $dirPath, $self);
}

#========================================
# XXX: $env 渡し中心に変更する. 現状では...
# [1] $fh, $cgi を外から渡すケース... そもそも、これを止めるべき. $env でええやん、と。
# [2] $fh, $file, []/{}
# [3] $fh, $file, k=v, k=v... のケース

sub make_cgi {
  (my MY $self, my Env $env) = splice @_, 0, 2;
  my ($cgi, $root, $loc, $file, $trailer);
  if ($self->is_gateway) {
    my $is_cgi_obj = ref $_[0] and $_[0]->can('param');
    $cgi = $is_cgi_obj ? shift : $self->new_cgi(@_);
    my ($path_translated, $document_root) = do {
      if ($env->{PATH_TRANSLATED} && ($env->{REDIRECT_STATUS} // 0) == 200) {
	($env->{PATH_TRANSLATED}
	 , '');
      } else {
	my $root = $self->{cf_mount}
	  // $env->{DOCUMENT_ROOT} // $self->{cf_document_root} // '';
	($root . ($env->{PATH_INFO} // '/')
	 , $root);
      }
    };

    # XXX: /~user_dir の場合は $dir ne $root$loc じゃんか orz...
    return (cgi => $cgi
	    , $self->split_path_url($path_translated
				    , $env->{PATH_INFO} // '/'
				    , $document_root)
	    , is_gateway => $self->is_gateway);

  } else {
    my $path = shift;
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
    ($root, $loc, $file, $trailer) = split_path($path);
    $cgi = $self->new_cgi(@_);
  }

  (cgi => $cgi, dir => "$root$loc", file => $file, subpath => $trailer
   , root => $root, location => $loc
   , is_gateway => $self->is_gateway);
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
		    );
      (dir => "$root$loc", file => $file, subpath => $trailer
       , root => $root, location => "$user$loc");
    } else {
      my ($root, $loc, $file, $trailer)
	= split_path($path_translated, $document_root);
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

#========================================

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
    $self->{cf_document_root} // '';
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
  print $fh "\n\n";
  foreach my $name (sort keys %$env) {
    print $fh $name, "\t", map(defined $_ ? $_ : "(undef)", $env->{$name}), "\n"
      ;
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
