package YATT::Lite::Partial::AppPath; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw/all/;

use File::Path ();

use YATT::Lite::Partial fields => [qw/cf_app_root/]
  , requires => [qw/error rel2abs/];

# Note: Do *not* use YATT::Lite. YATT::Lite *uses* this.

sub app_path_is_replaced {
  my MY $self = shift;
  $_[0] =~ s|^\@|$self->{cf_app_root}/|;
}

sub app_path_find_dir_in {
  (my MY $self, my ($in, $path)) = @_;
  $self->app_path_is_replaced($path);
  $path = $self->app_path_normalize($path, $in);
  -d $path ? $path : '';
}

sub app_path_normalize {
  (my MY $self, my ($path, $base)) = @_;
  my $normalized = $path =~ m{^/} ? $path : $self->rel2abs($path, $base);
  1 while $normalized =~ s{/[^/\.]+/\.\.(?:/|$)}{/};
  # XXX: Should not point outside of $app_root.
  $normalized;
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
