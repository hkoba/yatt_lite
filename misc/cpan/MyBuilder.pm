package
  MyBuilder;
use strict;
use warnings FATAL => qw(all);

use File::Find;
use File::Basename ();
use File::Path;

use base qw(Module::Build File::Spec);

#
# To include yatt_dist as_is
#
sub process_yatt_dist_files {
  my ($self) = @_;

  $self->pm_files(\ my %pm_files);
  $self->pod_files(\ my %pod_files);

  foreach my $desc ([pm => \%pm_files], [pod => \%pod_files]) {
    my ($ext, $map) = @$desc;
    my ($src, $dest) = ("Lite.$ext", "lib/YATT/Lite.$ext");
    $map->{$src} = $dest;
    $self->_yatt_dist_ensure_blib_copied($src, $dest);
  }

  # Lite/ should go into blib/lib/YATT/Lite
  find({no_chdir => 1, wanted => sub {
	  return $self->prune if /^\.git|^lib$/;
	  return if -d $_;
	  my $dest;
	  if (/\.pm$/) {
	    $dest = \%pm_files
	  } elsif (/\.pod$/) {
	    $dest = \%pod_files
	  } else {
	    return;
	  }
	  my $d = $dest->{$_} = "lib/YATT/$_";
	  $self->_yatt_dist_ensure_blib_copied($_, $d);
	}}, "Lite");

  # scripts/ and elisp/ also should go into blib/lib/YATT/
  # XXX: This may be changed to blib/lib/YATT/Lite/ or somewhere else.
  find({no_chdir => 1, wanted => sub {
	  return $self->prune if /^\.git|^lib$/;
	  return if -d $_;
	  return unless m{/yatt[^/]*$|\.el$};
	  my $d = $pm_files{$_} = "lib/YATT/$_";
	  $self->_yatt_dist_ensure_blib_copied($_, $d);
	  }}, 'scripts', 'elisp');
}

sub _yatt_dist_ensure_blib_copied {
  my ($self, $from, $dest) = @_;
  my $to = $self->catfile($self->blib, $dest);
  if ($ENV{DEBUG_BUILD}) {
    print STDERR "$from => $to\n";
  } else {
    $self->copy_if_modified(from => $from, to => $to);
  }
}

sub prune {
  $File::Find::prune = 1;
}

#========================================
#
# To remove leading 'v' from dist_version.
#

sub dist_version {
  my ($self) = @_;
  my $ver = $self->SUPER::dist_version
    or die "Can't detect dist_version";
  $ver =~ s/^v//;
  $ver;
}

#========================================
#
# To include symlinks in distdir.
#

sub ACTION_distdir {
  my $self = shift;
  $self->SUPER::ACTION_distdir(@_);
  $self->_do_in_dir
    ($self->dist_dir,
     sub {
       $self->cmd_list_symlink_list
	 (sub {
	    $self->restore_links(File::Basename::dirname(shift))
	  });
     });
}

sub symlink_list {'.symlinks'}

sub cmd_list_symlink_list {
  (my $self, my $cb) = splice @_, 0, 2;
  my $pat = quotemeta(symlink_list());
  find({no_chdir => 1, wanted => sub {
	  return $self->prune if m{/\.git$};
	  return unless m{/$pat$};
	  if ($cb) {
	    $cb->($_);
	  } else {
	    $self->log_verbose(" $_");
	  }
	}}, @_ ? @_ : '.');
}

sub restore_links {
  (my $self, my $dir) = @_;
  my $savefile = "$dir/" . symlink_list();
  $self->log_verbose("# restoring from $savefile\n");
  open my $fh, '<', $savefile;
  while (my $line = <$fh>) {
    chomp($line);
    next if $line =~ /^#/;
    my ($linkto, $placed_fn) = split "\t", $line;
    my $placed_path = "$dir/$placed_fn";
    unless (-l $placed_path) {
      symlink($linkto, $placed_path);
      $self->log_verbose("[created] $linkto\t$placed_fn\n");
    } elsif (my $was = readlink $placed_path) {
      if ($was eq $linkto) {
	$self->log_verbose("[kept] $linkto\t$placed_fn\n");
      } else {
	unlink $placed_path;
	symlink($linkto, $placed_path);
	$self->log_verbose("[updated] $linkto\t$placed_fn\n");
      }
    }
  }
}

#----------------------------------------

sub nonempty {
  defined $_[0] and $_[0] ne '';
}

1;
__END__

# Please ignore below.

sub ng_copy_if_modified {
  my $self = shift;
  my ($from, %args);
  if (@_ >= 4 and @_ % 2 == 0
      and nonempty($from = $args{from})
      and -l $from) {
    my $to_path = do {
      if (nonempty(my $to = $args{to})) {
	$to
      } elsif (nonempty(my $to_dir = $args{to_dir})) {
	$self->catfile($to_dir , $args{flatten}
		       ? File::Basename::basename($from)
		       : $from);
      } else {
	die "No 'to' or 'to_dir' is specified!";
      }
    };

    return if -e $to_path;

    File::Path::mkpath(File::Basename::dirname($to_path), 0, oct(777));

    symlink(readlink($from), $to_path)
      or die "Can't create symlink at $to_path: $!";

  } else {
    # Fallback
    $self->SUPER::copy_if_modified(@_);
  }
}


$build->add_build_element($elem);

$build->process_${element}_files($element);

$build->_find_file_by_...;

$self->copy_if_modified(from => $fn, to => $self->catfile($self->blib, $dest));

    ExtUtils::Install::install(
      $self->install_map, $self->verbose, 0, $self->{args}{uninst}||0
    );

$self->install_map

$self->install_types
 # install_base => installbase_relpaths
 # prefix       => prefix_relpaths
 # else         => install_sets(installdirs)
 # +
 # %{install_path}

 $localdir = catdir($blib, $type);
 $dest = $self->install_destination($type)

 $map{$localdir} = $dest;


_default_install_paths
 =>
  * install_sets
  * install_base_relpaths
  * prefix_relpaths
  


ACTION_code

ACTION_install

