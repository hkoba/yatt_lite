package YATT::Lite::WebMVC0::Entities;
use strict;
use warnings FATAL => qw/all/;

use YATT::Lite::Entities -as_base, qw/*SYS *CON/;
use 5.010; no if $] >= 5.017011, warnings => "experimental";


use YATT::Lite::WebMVC0::SiteApp ();
sub SiteApp () {'YATT::Lite::WebMVC0::SiteApp'}
use YATT::Lite::PSGIEnv;

sub entity_is_debug_allowed_ip {
  my ($this, $remote_addr) = @_;
  my SiteApp $self = $SYS;

  $remote_addr //= do {
    my Env $env = $CON->env;
    $env->{HTTP_X_REAL_IP}
      // $env->{HTTP_X_CLIENT_IP}
	// $env->{HTTP_X_FORWARDED_FOR}
	  // $env->{REMOTE_ADDR};
  };

  unless (defined $remote_addr and $remote_addr ne '') {
    return 0;
  }

  grep {$remote_addr ~~ $_} lexpand($self->{cf_debug_allowed_ip}
				    // ['127.0.0.1']);
};


1;
