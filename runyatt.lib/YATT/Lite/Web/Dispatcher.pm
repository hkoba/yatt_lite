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
	      cf_debug_cgi
	    );
use YATT::Lite::Util qw(cached_in split_path
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

sub dispatch {
  (my MY $self, my $fh) = splice @_, 0, 2;
  my @params = $self->make_cgi(@_);
  my $con = $self->run_dirhandler($fh, @params);
  $con->commit;
  $con;
}

sub run_dirhandler {
  (my MY $self, my ($fh, %params)) = @_;
  # dirhandler は必ず load することにする。 *.yatt だけでなくて *.ydo でも。
  # 結局は機能集約モジュールが欲しくなるから。
  # そのために、 dirhandler は死重を減らすよう、部分毎に delayed load する

  my $dh = $self->get_dirhandler(untaint_any($params{dir}));
  # XXX: cache のキーは相対パスか、絶対パスか?

  my $con = $dh->make_connection($fh, %params);

  $dh->handle($dh->trim_ext($params{file}), $con, $params{file});
}

sub runas {
  (my $this, my $type) = splice @_, 0, 2;
  my MY $self = ref $this ? $this : $this->new;
  my $sub = $self->can("runas_$type")
    or die "\n\nUnknown runas type: $type";
  $sub->($self, @_);
}

sub runas_cgi {
  (my MY $self, my $fh) = splice @_, 0, 2;
  if (-e ".htdebug_env") {
    $self->printenv($fh);
    return;
  }

  $self->init_by_env;

  if (my $gateway = $self->{cf_debug_cgi} || $ENV{DEBUG_CGI}) {
    # デバッガから使うときなど、 gateway モードで動かしつつ
    # catch したくないケースは、 DEBUG_CGI=1 で起動。
    require Cwd;
    local $ENV{GATEWAY_INTERFACE} = $gateway;
    local $ENV{REQUEST_METHOD} //= 'GET';
    local @ENV{qw(PATH_TRANSLATED REDIRECT_STATUS)}
      = (Cwd::abs_path(shift), 200)
	if @_;
    $self->dispatch($fh, @_);
  } elsif ($self->is_gateway) {
    if (defined $fh and fileno($fh) >= 0) {
      open STDERR, '>&', $fh or die "can't redirect STDERR: $!";
    }
    eval { $self->dispatch($fh, @_) };
    die "Content-type: text/plain\n\n$@" if $@ and not is_done($@);
  } else {
    $self->dispatch($fh, @_);
  }
}

sub is_done {
  defined $_[0] and ref $_[0] eq 'SCALAR' and not ref ${$_[0]}
    and ${$_[0]} eq 'DONE';
}

sub runas_fcgi {
  (my MY $self, my $fh) = splice @_, 0, 2;
  require CGI::Fast;
  # In suexec fcgi, $0 will not be absolute path.
  my $progname = $0 if $0 =~ m{^/};
  my ($dir, $age);
  $self->{cf_at_done} = sub {die \"DONE"};
  while (defined (my $cgi = new CGI::Fast)) {
    $self->init_by_env;
    unless (defined $progname) {
      $progname = $ENV{SCRIPT_FILENAME}
	or die "\n\nSCRIPT_FILENAME is empty!\n";
    }
    unless (defined $dir) {
      $dir = dirname($progname);
      $age = -M $progname;
    }

    if (-e "$dir/.htdebug_env") {
      $self->printenv($fh, $cgi);
      next;
    }

    eval { $self->dispatch($fh, $cgi) };
    $self->show_error($fh, $@, $cgi) if $@ and not is_done($@); # 暫定
    last if -e $progname and -M $progname < $age;
  }
}

sub init_by_env {
  (my MY $self) = @_;
  $self->{cf_is_gateway} //= $ENV{GATEWAY_INTERFACE} if $ENV{GATEWAY_INTERFACE};
  $self->{cf_document_root} //= $ENV{DOCUMENT_ROOT} if $ENV{DOCUMENT_ROOT};
  $self;
}

#========================================

sub get_dirhandler {
  (my MY $self, my $dirPath) = @_;
  $self->cached_in($self->{DirHandler} ||= {}, $dirPath, $self);
}

#========================================
# [1] $fh, $cgi を外から渡すケース... そもそも、これを止めるべきなのか? <= CGI::Fast か.
# [2] $fh, $file, []/{}
# [3] $fh, $file, k=v, k=v... のケース

sub make_cgi {
  (my MY $self) = shift;
  my ($cgi, $root, $loc, $file, $trailer);
  if ($self->is_gateway) {
    my $is_cgi_obj = ref $_[0] and $_[0]->can('param');
    $cgi = $is_cgi_obj ? shift : $self->new_cgi(@_);
    my $path;
    if (nonempty($path = $cgi->path_translated)) {
      # ok
    } elsif (nonempty($self->{cf_mount})) {
      $path = $self->{cf_mount} . ($cgi->path_info // '/');
    } else {
      croak "\n\nYATT mount point is not specified.";
    }
    # XXX: /~user_dir の場合は $dir ne $root$loc じゃんか orz...
    return (cgi => $cgi
     , $self->split_path_url($path, $cgi->path_info // '/'
			    , $self->document_dir($cgi))
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
  (my MY $self, my ($fh, $cgi)) = @_;
  print $fh "\n\n";
  foreach my $name (sort keys %ENV) {
    print $fh $name, "\t", map(defined $_ ? $_ : "(undef)", $ENV{$name}), "\n"
      ;
  }

  if (defined $cgi and ref $cgi) {
    print $fh "CGI:\n", terse_dump($cgi), "\n";
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
