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
use base qw(YATT::Lite::NSBuilder);
use fields qw(DirHandler Action
	      cf_tmpl_encoding cf_output_encoding cf_debug_cgen
	      cf_only_parse cf_namespace cf_tmpldirs
	      cf_debug_cgi
	      cf_tmpl_cache
	      cf_mount
	      cf_error_handler

	      cf_at_done

	      cf_is_gateway cf_document_root
	    );
use YATT::Lite::Util qw(cached_in split_path untaint_any globref
			lexpand rootname extname);
use YATT::Lite::Util::CmdLine qw(parse_params);
use YATT::Lite::Entities qw(build_entns);
sub default_dirhandler () {'YATT::Lite::Web::DirHandler'}

use File::Basename;
use YATT::Lite::Web::Connection ();
sub ConnProp () {'YATT::Lite::Web::Connection'}
sub Connection () {'YATT::Lite::Web::Connection'}

#========================================

sub after_new {
  (my MY $self) = @_;
  $self->{cf_tmpl_cache} ||= {}
}

sub dispatch {
  (my MY $self, my $fh) = splice @_, 0, 2;
  my ($con, @path) = $self->make_connection($fh, @_);
  $self->run_dirhandler($con, @path);
  $con->commit;
  $con;
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
  # init...
  my $progname = $0;
  my $dir = dirname($progname);
  my $age = -M $progname;
  $self->{cf_at_done} = sub {die \"DONE"};
  while (defined (my $cgi = new CGI::Fast)) {
    $self->init_by_env;

    if (-e "$dir/.htdebug_env") {
      $self->printenv($fh);
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

  # MyApp を使いたいときは... Runenv->new(basens => 'MyApp') で。
  my $appns = $self->buildns; # MyApp::INST$n を作る. 親は?

  my @base = map { [dir => $_] } lexpand($self->{cf_tmpldirs});

  # $appns は DirHandler で Facade だから、 trans ではないことに注意。
  # trans にメンバーを足す場合は、facade にも足して、かつ cf_delegate しておかないとだめ。
  $appns->new($name
	      , vfs => [dir => $name, encoding => $self->{cf_tmpl_encoding}]
	      , package => $appns->rootns_for($appns)
	      , nsbuilder => sub {
		  build_entns(TMPL => $appns, $appns->EntNS);
	      }
	      , (@base ? (base => \@base) : ())
	      , is_gateway => $self->is_gateway
	      , $self->cf_delegate
	      (qw(output_encoding debug_cgen tmpl_cache at_done
		  namespace only_parse error_handler))
	      , die_in_error => ! YATT::Lite::Util::is_debugging());
}

#========================================
# [1] $fh, $cgi を外から渡すケース... そもそも、これを止めるべきなのか? <= CGI::Fast か.
# [2] $fh, $file, []/{}
# [3] $fh, $file, k=v, k=v... のケース

sub make_connection {
  (my MY $self, my ($fh)) = splice @_, 0, 2;
  my ($cgi, $dir, $file, $trailer);
  if ($self->is_gateway) {
    my $is_cgi_obj = ref $_[0] and $_[0]->can('param');
    $cgi = $is_cgi_obj ? shift
      : $self->new_cgi(@_ ? $self->parse_params(\@_, {}) : ());
    my $path;
    if (nonempty($path = $cgi->path_translated)) {
      # ok
    } elsif (nonempty($self->{cf_mount})) {
      $path = $self->{cf_mount} . ($cgi->path_info // '/');
    } else {
      croak "\n\nYATT mount point is not specified.";
    }
    ($dir, $file, $trailer) = split_path($path, $self->document_dir($cgi));
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
    ($dir, $file, $trailer) = split_path($path);
    $cgi = $self->new_cgi(@_ == 1 && ref $_[0] ? $_[0]
			  : $self->parse_params(\@_, {}));
  }

  my $con = $self->ConnProp->new
    (do {
      if ($self->is_gateway) {
	# buffered mode.
	(undef, parent_fh => $fh, header => sub {
	   my ($con) = shift;
	   my $o = (my ConnProp $prop = $con->prop)->{session} || $cgi;
	   $o->header($con->list_header
		      , -charset => $$self{cf_output_encoding});
	 });
      } else {
	# direct mode.
	$fh
      }
    }, cgi => $cgi, file => $file, trailing_path => $trailer);

  wantarray ? ($con, $dir, $file) : $con;
}

# XXX: @rest に関して迷いが残っている。
sub run_dirhandler {
  (my MY $self, my ($con, $dir, $file, @rest)) = @_;

  # dirhandler は必ず load することにする。 *.yatt だけでなくて *.ydo でも。
  # 結局は機能集約モジュールが欲しくなるから。
  # そのために、 dirhandler は死重を減らすよう、部分毎に delayed load する

  my $dh = $self->get_dirhandler($dir);
  # XXX: cache のキーは相対パスか、絶対パスか?

  $dh->handle($dh->trim_ext($file), $con, $file, @rest);

  # XXX: Too much?
  # $con->commit;
}

#========================================

sub new_cgi {
  shift; require CGI; CGI->new(@_);
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
  (my MY $self, my ($fh)) = @_;
  print $fh "\n\n";
  foreach my $name (sort keys %ENV) {
    print $fh $name, "\t", map(defined $_ ? $_ : "(undef)", $ENV{$name}), "\n"
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
