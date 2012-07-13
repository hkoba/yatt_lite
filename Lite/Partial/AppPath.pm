package YATT::Lite::Partial::AppPath; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw/all/;

use File::Path ();

use YATT::Lite::Partial fields => [qw/cf_app_root/], requires => [qw/error/];

# Note: Do *not* use YATT::Lite. YATT::Lite *uses* this.

sub app_path_is_replaced {
  my MY $self = shift;
  $_[0] =~ s|^\@|$self->{cf_app_root}/|;
}

sub app_path_find_dir {
  (my MY $self, my $path) = @_;
  $self->app_path_is_replaced($path);
  return '' unless -d $path;
  $path;
}

sub app_path_ensure_existing {
  (my MY $self, my ($path, %opts)) = @_;
  if ($self->app_path_is_replaced(my $real = $path)) {
    return $real if -d $real;
    File::Path::make_path($real, \%opts);
    $real;
  } else {
    return $path if -d $path;
    $self->error('Non-existing path out of app_path is prohibited: %s', $path);
  }
}

sub app_path {
  (my MY $self, my $fn) = @_;
  my $path = $self->{cf_app_root};
  $path =~ s|/*$|/$fn|;
  $self->error("Can't find app_path: %s", $path) unless -e $path;
  $path;
}

1;
