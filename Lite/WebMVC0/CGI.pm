package YATT::Lite::WebMVC0::CGI;
use strict;
use warnings FATAL => qw/all/;

package YATT::Lite::WebMVC0; use YATT::Lite::WebMVC0;

sub runas_cgi {
  (my MY $self, my $fh, my Env $env, my ($args, %opts)) = @_;
  if (-e ".htdebug_env") {
    $self->printenv($fh, $env);
    return;
  }

  $self->init_by_env($env);

  if ($self->{cf_noheader}) {
    # コマンド行起動時
    require Cwd;
    local $env->{GATEWAY_INTERFACE} = 'CGI/YATT';
    local $env->{REQUEST_METHOD} //= 'GET';
    local @{$env}{qw(PATH_TRANSLATED REDIRECT_STATUS)}
      = (Cwd::abs_path(shift @$args), 200)
	if @_;
    $self->dispatch($fh, $env, $args, \%opts);

  } elsif ($env->{GATEWAY_INTERFACE}) {
    # Normal CGI
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
    # dispatch without catch.
    $self->dispatch($fh, $env, $args, \%opts);
  }
}

#========================================

sub dispatch {
  (my MY $self, my $fh, my Env $env, my ($args, $opts)) = @_;
  # XXX: 本当は make_cgi 自体を廃止したい。
  my @params = $self->make_cgi($env, $args, $opts);

  $self->run_dirhandler($fh, @params);
}

sub run_dirhandler {
  (my MY $self, my ($fh, %params)) = @_;
  # dirhandler は必ず load することにする。 *.yatt だけでなくて *.ydo でも。
  # 結局は機能集約モジュールが欲しくなるから。
  # そのために、 dirhandler は死重を減らすよう、部分毎に delayed load する

  my $dh = $self->get_dirhandler(untaint_any($params{dir}))
    or die "Unknown directory: $params{dir}";
  # XXX: cache のキーは相対パスか、絶対パスか?

  my $con = $self->make_connection($fh, %params);

  $dh->with_system($self
		   , handle => $dh->cut_ext($params{file})
		   , $con, $params{file});

  wantarray ? ($dh, $con) : $con;
}

#========================================
# XXX: $env 渡し中心に変更する. 現状では...
# [1] $fh, $cgi を外から渡すケース... そもそも、これを止めるべき. $env でええやん、と。
# [2] $fh, $file, []/{}
# [3] $fh, $file, k=v, k=v... のケース

sub make_cgi {
  (my MY $self, my Env $env, my ($args, $opts)) = @_;
  my ($cgi, $root, $loc, $file, $trailer);
  unless ($self->{cf_noheader}) {
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

sub init_by_env {
  (my MY $self, my Env $env) = @_;
  $self->{cf_noheader} //= 0 if $env->{GATEWAY_INTERFACE};
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

1;
