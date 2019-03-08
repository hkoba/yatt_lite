package YATT::Lite::WebMVC0::Partial::Session2;
sub MY () {__PACKAGE__}
use strict;
use warnings qw(FATAL all NONFATAL misc);
use Carp;

use constant DEBUG => ($ENV{DEBUG_YATT_SESSION2} // 0);
use YATT::Lite::Util qw/dputs
                        lexpand
                       /;

use Plack::Util;

#========================================

# This version of YATT::Lite::WebMVC0::Partial::Session2 directly
# calls *internal* methods of Plack::Middleware::Session.

use Plack::Middleware::Session;
sub default_session_middleware_class {'Plack::Middleware::Session'}

#========================================

use YATT::Lite::PSGIEnv;

use YATT::Lite::Partial
  (requires => [qw/
                    error
		  /]
   , fields => [qw/
                    _session_middleware
                    cf_session_middleware_class
                    cf_session_state
                    cf_session_store
		  /]
   , -Entity, -CON
  );

#========================================

Entity psgix_session => sub {
  my ($this) = @_;
  my Env $env = $CON->env;
  unless ($env->{'psgix.session.options'}) {
    $CON->cget('system')->session_start($CON);
  }
  $env->{'psgix.session'};
};

Entity psgix_session_options => sub {
  my ($this) = @_;
  my Env $env = $CON->env;
  $env->{'psgix.session.options'};
};

Entity psgix_session_exists => sub {
  my ($this) = @_;
  my Env $env = $CON->env;
  defined $env->{'psgix.session.options'}
    and $env->{'psgix.session.options'}{'id'};
};

#----------------------------------------
Entity session_start => sub {
  my ($this, @opts) = @_;
  $CON->cget('system')->session_start($CON, @opts);
  "";
};

Entity session_state_id => sub {
  my ($this) = @_;
  $CON->cget('system')->session_state_extract_id($CON);
};

#----------------------------------------
sub default_session_class {'Plack::Session'}

Entity session => sub {
  my ($this) = @_;
  my Env $env = $CON->env;
  $env->{'plack.session'};
};

{
  foreach my $meth (qw(id get set remove keys expire)) {
    Entity "session_$meth" => sub {
      my $this = shift;
      my Env $env = $CON->env;
      $env->{'plack.session'}->$meth(@_);
    };
  }
}

#========================================

#
# Stolen from the top half of Plack::Middleware::Session->call
#
sub session_start {
  (my MY $self, my ($CON, @opts)) = @_;

  my $mw = $self->{_session_middleware} or do {
    Carp::croak("Session middleware is not initialized!");
  };

  my Env $env = $CON->env;

  my $id = $self->session_state_extract_id($CON);
  my $session; $session = $self->session_store_fetch($CON, $id) if $id;

  if ($id && $session) {
    $env->{'psgix.session'} = $session;
  } else {
    $id = $mw->generate_id($env);
    $env->{'psgix.session'} = {};
  }

  $env->{'psgix.session.options'} = { id => $id, @opts };

  $env->{'plack.session'}
    = Plack::Util::load_class($self->default_session_class)->new($env);
}

sub session_state_extract_id {
  (my MY $self, my $CON) = @_;
  my $mw = $self->{_session_middleware} or do {
    Carp::croak("Session middleware is not initialized!");
  };

  $CON->cookies_in->{$mw->state->session_key};
}

sub session_store_fetch {
  (my MY $self, my ($CON, $id)) = @_;
  my $mw = $self->{_session_middleware} or do {
    Carp::croak("Session middleware is not initialized!");
  };

  $mw->store->fetch($id);
}

#
# Stolen from the bottom half of Plack::Middleware::Session->call
#
sub finalize_response {
  (my MY $self, my ($env, $res)) = @_;

  dputs('START') if DEBUG >= 4;

  $self->maybe::next::method($env, $res);

  my $mw = $self->{_session_middleware};
  my $session = $env->{'psgix.session'};
  my $options = $env->{'psgix.session.options'};

  if (not $session) {
    return;
  }

  if ($options->{expire}) {
    dputs('EXPIRE') if DEBUG >= 4;
    $mw->expire_session($options->{id}, $res, $env);
  } else {
    $mw->change_id($env) if $options->{change_id};
    $mw->commit($env);
    $mw->save_state($options->{id}, $res, $env);
    dputs('SAVED') if DEBUG >= 4;
  }

  dputs('DONE') if DEBUG >= 4;
}

#
# This prepare_app is called very late of inheritance chain.
#
sub prepare_app {
  (my MY $self) = @_;

  dputs('START') if DEBUG >= 3;

  my $mw = $self->{_session_middleware} = do {
    my $class = $self->{cf_session_middleware_class}
      || $self->default_session_middleware_class;

    $class->new({app => sub {[200, [], []]}
                 , ($self->{cf_session_state}
                    ? (state => $self->create_session_backend(state => $self->{cf_session_state})) : ())
                 , ($self->{cf_session_store}
                    ? (store => $self->create_session_backend(store => $self->{cf_session_store})) : ())
               });
  };

  dputs('session_middleware is created') if DEBUG >= 3;

  $mw->prepare_app;

  dputs('after session_middleware->prepare_app') if DEBUG >= 3;

  dputs('begin maybe::next::method') if DEBUG >= 3;

  $self->maybe::next::method;

  dputs('DONE') if DEBUG >= 3;
}

sub default_session_state {'Plack::Session::State::Cookie'}
sub default_session_store {'Plack::Session::Store'}

# From Session::inflate_backend
sub create_session_backend {
  (my MY $self, my ($kind, $spec)) = @_;

  # When $spec is not [$backend => @opts], just return it.
  return $spec if defined $spec and ref $spec ne 'ARRAY';

  my $prefix = $self->can("default_session_$kind")->();

  my ($backend, @args) = lexpand($spec);

  my $class = Plack::Util::load_class($backend, $prefix);

  if (my $sub = $self->can("create_session_${kind}_$backend")) {
    $sub->($self, $class, @args);
  } else {
    $class->new(@args);
  }
}

1;
