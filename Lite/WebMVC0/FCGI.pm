package YATT::Lite::WebMVC0::FCGI;
use strict;
use warnings FATAL => qw/all/;

package YATT::Lite::WebMVC0; use YATT::Lite::WebMVC0;

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

1;
