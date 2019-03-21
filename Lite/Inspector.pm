#!/usr/bin/env perl
package YATT::Lite::Inspector;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base
  , [fields =>
       qw/_SITE _app_root/,
     [dir => doc => "starting directory to search app.psgi upward"],
     [emit_relative_path => doc => "emit \$app_root-relative path"],
     [site_class => doc => "class name for SiteApp (to load app.psgi)", default => "YATT::Lite::WebMVC0::SiteApp"],
     [ignore_symlink => doc => "ignore symlinked templates"],
     [detail => doc => "show argument details"],
   ];

use MOP4Import::Util qw/lexpand/;

use parent qw/File::Spec/;

#----------------------------------------

use Text::Glob;
use Plack::Util;
use File::Basename;

use YATT::Lite;
use YATT::Lite::Factory;
use YATT::Lite::LRXML;
use YATT::Lite::Core qw/Part Widget Template/;
use YATT::Lite::CGen::Perl;

use YATT::Lite::Walker;

#========================================

sub after_after_new {
  (my MY $self) = @_;
  $self->SUPER::after_after_new;

  $self->{_SITE} = do {
    my $class = Plack::Util::load_class($self->{site_class});
    $class->load_factory_offline(dir => $self->{dir})
      or die "Can't find YATT app script!\n";
  };

  $self->{_app_root} = $self->{_SITE}->cget('app_root');
}


#========================================

sub cmd_ctags_symbols {
  (my MY $self, my @args) = @_;
  $self->configure($self->parse_opts(\@args));
  my ($dir) = @args;

  my $cwdOrFileList = $self->list_target_dirs($dir);

  walk(
    factory => $self->{_SITE},
    from => $cwdOrFileList,
    ignore_symlink => $self->{ignore_symlink},
    widget => sub {
      my ($args) = @_;
      my Part $widget = $args->{part};
      my Template $tmpl = $widget->{cf_folder};
      my $path = $tmpl->{cf_path};
      $self->emit_ctags($args->{kind}, $args->{name}, $path, $widget->{cf_startln});
    },
    item => sub {
      my ($args) = @_;
      my $path = $args->{tree}->cget('path');
      my ($kind, $name) = do {
        if (-l $path) {
          (symlink => readlink($path))
        } else {
          (file => $self->clean_path($path));
        }
      };
      $self->emit_ctags($kind => $name, $path, 1);
    },
  );
}

sub clean_path {
  (my MY $self, my $path) = @_;
  if ($self->{emit_relative_path}) {
    $path =~ s,^$self->{_app_root}/*,,;
  }
  $path;
}

#
# Same format with "ctags -x --_xformat=%{input}:%n:1:%K!%N" (I hope).
#
sub emit_ctags {
  (my MY $self, my ($kind, $name, $fileName, $lineNo, $colNo)) = @_;
  # XXX: symbolKind mapping.
  printf "%s:%d:%d:%s!%s\n", $self->clean_path($fileName)
    , $lineNo, $colNo // 1, $kind, $name;
}

sub cmd_list_widgets {
  (my MY $self, my @args) = @_;
  $self->configure($self->parse_opts(\@args));
  my ($widgetNameGlob, $from) = @args;

  my $cwdOrFileList = $self->list_target_dirs($from);

  walk(
    factory => $self->{_SITE},
    from => $cwdOrFileList,
    ignore_symlink => $self->{ignore_symlink},
    ($widgetNameGlob ? (
      (name_match => Text::Glob::glob_to_regex($widgetNameGlob))
    ) : ()),
    widget => sub {
      my ($found) = @_;
      my Part $widget = delete $found->{part};
      my Template $tmpl = $widget->{cf_folder};
      my $path = $tmpl->{cf_path};
      my $args = $self->{detail}
        ? [$self->list_part_args_internal($widget)]
        : $widget->{arg_order};
      my @result = ((map {$_ => $found->{$_}} sort keys %$found)
                      , , args => $args);
      # Emit as an array for readability in normal mode.
      my $result = $self->{detail} ? +{@result} : \@result;
      $self->cli_output($result);
    },
    item => sub {
      my ($args) = @_;
      # print "# ", $args->{tree}->cget('path'), "\n";
    },
  );

  # $yatt->get_trans->list_items
  # $yatt->get_trans->find_file('index')
  # $yatt->get_trans->find_file('index')->list_parts
}

sub list_part_args_internal {
  (my MY $self, my Part $part, my $nameRe) = @_;
  my @result;
  my @fields = YATT::Lite::VarTypes->list_field_names;
  foreach my $argName ($part->{arg_order} ? @{$part->{arg_order}} : ()) {
    next if $nameRe and not $argName =~ $nameRe;
    my $argObj = $part->{arg_dict}{$argName};
    push @result, my $spec = {};
    foreach my $i (0 .. $#fields) {
      my $val = $argObj->[$i];
      $spec->{$fields[$i]} = $val;
    }
  }
  @result;
}

#========================================

sub is_in_template_dir {
  (my MY $self, my $path) = @_;
  foreach my $dir (lexpand($self->{_SITE}->{tmpldirs})) {
    if (length $dir <= length $path
        and substr($dir, 0, length $path) eq $path) {
      return 1;
    }
  }
  return 0;
}

sub list_target_dirs {
  (my MY $self, my $dirSpec) = @_;

  if ($dirSpec) {
    $self->rel2abs($dirSpec)
  } else {
    my $cwd = Cwd::getcwd;
    if ($self->is_in_template_dir($cwd)) {
      $cwd;
    } else {
      $self->{_SITE}->cget('doc_root') // do {
        if (my $dir = $self->{_SITE}->cget('per_role_docroot')) {
          [glob("$dir/[a-z]*")];
        } else {
          Carp::croak "doc_root is empty!"
        }
      }
    }
  }
}

#========================================

MY->run(\@ARGV) unless caller;

1;
