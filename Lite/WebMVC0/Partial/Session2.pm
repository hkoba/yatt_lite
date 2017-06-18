package YATT::Lite::WebMVC0::Partial::Session2;
sub MY () {__PACKAGE__}
use strict;
use warnings qw(FATAL all NONFATAL misc);
use Carp;

use constant DEBUG => ($ENV{DEBUG_YATT_SESSION2} // 0);
use YATT::Lite::Util qw/dputs/;

use Plack::Util;

#========================================

# This version of YATT::Lite::WebMVC0::Partial::Session2 directly
# calls *internal* methods of Plack::Middleware::Session.

use Plack::Middleware::Session;
sub default_session_middleware_class {'Plack::Middleware::Session'}

#========================================

use YATT::Lite::PSGIEnv qw/
                            yatt.session
                          /;

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
  $env->{'psgix.session'};
};

Entity psgix_session_options => sub {
  my ($this) = @_;
  my Env $env = $CON->env;
  $env->{'psgix.session.options'};
};

#----------------------------------------
Entity session_start => sub {
  my ($this, @opts) = @_;
  my Env $env = $CON->env;
  $CON->cget('system')->session_start($env, @opts);
  "";
};

#----------------------------------------
sub default_session_class {'Plack::Session'}

Entity session => sub {
  my ($this) = @_;
  my Env $env = $CON->env;
  $env->{'yatt.session'};
};

{
  foreach my $meth (qw(id get set remove keys expire)) {
    Entity "session_$meth" => sub {
      my $this = shift;
      my Env $env = $CON->env;
      $env->{'yatt.session'}->$meth(@_);
    };
  }
}

#========================================

#
# Stolen from the top half of Plack::Middleware::Session->call
#
sub session_start {
  (my MY $self, my ($env, @opts)) = @_;

  my $mw = $self->{_session_middleware} or do {
    Carp::croak("Session middleware is not initialized!");
  };

  my ($id, $session) = $mw->get_session($env);

  if ($id && $session) {
    $env->{'psgix.session'} = $session;
  } else {
    $id = $mw->generate_id($env);
    $env->{'psgix.session'} = {};
  }

  $env->{'psgix.session.options'} = { id => $id, @opts };

  $env->{'yatt.session'}
    = Plack::Util::load_class($self->default_session_class)->new($env);
}

#
# Stolen from the bottom half of Plack::Middleware::Session->call
#
sub finalize_response {
  (my MY $self, my ($env, $res)) = @_;

  $self->maybe::next::method($env, $res);

  my $mw = $self->{_session_middleware};
  my $session = $env->{'psgix.session'};
  my $options = $env->{'psgix.session.options'};

  if ($options->{expire}) {
    $mw->expire_session($options->{id}, $res, $env);
  } else {
    $mw->change_id($env) if $options->{change_id};
    $mw->commit($env);
    $mw->save_state($options->{id}, $res, $env);
  }
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
                    ? (state => $self->{cf_session_state}) : ())
                 , ($self->{cf_session_store}
                    ? (store => $self->{cf_session_store}) : ())
               });
  };

  dputs('session_middleware is created') if DEBUG >= 3;

  $mw->prepare_app;

  dputs('after session_middleware->prepare_app') if DEBUG >= 3;

  dputs('begin maybe::next::method') if DEBUG >= 3;

  $self->maybe::next::method;

  dputs('DONE') if DEBUG >= 3;
}

1;
