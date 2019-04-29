#!/usr/bin/env perl
package YATT::Lite::Inspector;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use File::AddInc;
use MOP4Import::Base::CLI_JSON -as_base
  , [fields =>
       qw/_SITE _app_root _file_line_cache/,
     [dir => doc => "starting directory to search app.psgi upward"],
     [emit_absolute_path => doc => "emit absolute path instead of \$app_root-relative"],
     [site_class => doc => "class name for SiteApp (to load app.psgi)", default => "YATT::Lite::WebMVC0::SiteApp"],
     [ignore_symlink => doc => "ignore symlinked templates"],
     [detail => doc => "show argument details"],
     [line_base => default => 1],
   ];

use MOP4Import::Util qw/lexpand symtab terse_dump/;

use MOP4Import::Types
  Zipper => [[fields => qw/array index path/]]
  , SymbolInfo => [[fields => qw/kind symbol filename range/]]
  ;

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

use YATT::Lite::LRXML::AltTree qw/column_of_source_pos AltNode/;

use YATT::Lite::Walker qw/walk walk_vfs_folders/;

use YATT::Lite::LanguageServer::Protocol qw/Position Range MarkupContent/;

#========================================

sub after_configure_default {
  (my MY $self) = @_;
  $self->SUPER::after_configure_default;

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
  if (not $self->{emit_absolute_path}) {
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

#========================================

sub alttree {
  (my MY $self, my ($tmpl, $tree)) = @_;
  [YATT::Lite::LRXML::AltTree->new(
    string => $tmpl->cget('string'),
    with_source => 0,
  )
   ->convert_tree($tree)];
}

sub describe_symbol {
  (my MY $self, my SymbolInfo $sym, my Zipper $cursor) = @_;
  my $resolver = $self->can("describe_symbol_of_$sym->{kind}")
    or return;
  $resolver->($self, $sym, $cursor);
}

sub describe_symbol_of_ELEMENT {
  (my MY $self, my SymbolInfo $sym, my Zipper $cursor) = @_;

  my AltNode $node = $cursor->{array}[$cursor->{index}];
  # assert($node);

  my Position $pos = $self->range_start($sym->{range});

  my $wname = join(":", lexpand($node->{path}));

  # XXX: yatt:if, yatt:foreach, ... macro
  # XXX: calllable_vars like <yatt:body/>

  my Part $widget = $self->lookup_widget_from(
    $node->{path}, $sym->{filename}, $pos->{line}
  ) or return;

  my MarkupContent $md = +{};
  $md->{kind} = 'markdown';
  $md->{value} = <<END;
(widget) <$wname
@{[map {"  $_=".$widget->{arg_dict}{$_}->type->[0]."\n"} @{$widget->{arg_order}}]}
/>
END

  $md;
}

sub lookup_widget_from {
  (my MY $self, my ($wpath, $fileName, $line)) = @_;

  (my Part $part, my Template $tmpl, my $core)
    = $self->find_part_of_file_line($fileName, $line)
    or return;

  $core->build_cgen_of('perl')
    ->with_template($tmpl, lookup_widget => lexpand($wpath));
}

sub locate_symbol_at_file_position {
  (my MY $self, my ($fileName, $line, $column)) = @_;
  $line //= 0;
  $column //= 0;

  my Zipper $cursor = $self->locate_node_at_file_position(
    $fileName, $line, $column
  ) or return;

  my AltNode $node = $cursor->{array}[$cursor->{index}]
    or return;

  my SymbolInfo $info = {};
  $info->{kind} = $node->{kind};
  $info->{range} = $node->{symbol_range};
  $info->{filename} = $fileName;

  wantarray ? ($info, $cursor) : $info;
}

sub locate_node_at_file_position {
  (my MY $self, my ($fileName, $line, $column)) = @_;
  $line //= 0;
  $column //= 0;

  my $treeSpec = $self->dump_tokens_at_file_position($fileName, $line, $column)
    or return;

  my Position $pos;
  $pos->{line} = $line;
  $pos->{character} = $column;

  my ($kind, $path, $range, $tree) = @$treeSpec;
  unless ($self->is_in_range($range, $pos)) {
    Carp::croak "BUG: Not in range! range=".terse_dump($range)." line=$line col=$column";
  }

  # <!yatt:action>, <!yatt:entity>...
  return if $kind eq 'body_string';

  $self->locate_node($tree, $pos);
}

sub node_path_of_zipper {
  (my MY $self, my Zipper $cursor) = @_;
  my @trail;
  my Zipper $cur = $cursor;
  while ($cur) {
    push @trail, do {
      if (my AltNode $node = $cur->{array}[$cur->{index}]) {
        $self->minimize_altnode($node);
      } else {
        [map {$self->minimize_altnode($_)} @{$cur->{array}}];
      }
    };
    $cur = $cur->{path};
  }

  @trail;
}

sub minimize_altnode {
  (my MY $self, my AltNode $node) = @_;
  my AltNode $min = {};
  $min->{kind} = $node->{kind};
  $min->{path} = $node->{path};
  $min->{tree_range} = $node->{tree_range};
  $min;
}

sub locate_node {
  (my MY $self, my $tree, my Position $pos, my Zipper $parent) = @_;

  my Zipper $current = +{};
  $current->{path} = $parent;
  $current->{array} = $tree;
  my $ix = $current->{index} = $self->lsearch_node_pos($pos, $tree);

  if (my AltNode $node = $tree->[$ix]) {

    if ($node->{symbol_range}
        and $self->is_in_range($node->{symbol_range}, $pos)) {
      return $current;
    }

    if ($node->{subtree}) {
      return $self->locate_node($node->{subtree}, $pos, $current);
    }
  }

  $current;
}

sub lsearch_node_pos {
  (my MY $self, my Position $pos, my $tree) = @_;
  my $i = 0;
  foreach my AltNode $node (@$tree) {
    if ($self->compare_position($self->range_end($node->{tree_range}), $pos) > 0) {
      return $i;
    }
  } continue {
    $i++;
  }
  # Point outside of the tree.
  return scalar @$tree;
}

sub range_start { (my MY $self, my Range $range) = @_; $range->{start}; }
sub range_end { (my MY $self, my Range $range) = @_; $range->{end}; }

sub is_in_range {
  (my MY $self, my Range $range, my Position $pos) = @_;
  $self->compare_position($range->{start}, $pos) <= 0
    && $self->compare_position($range->{end}, $pos) >= 0;
}

sub compare_position {
  (my MY $self, my Position $leftPos, my Position $rightPos) = @_;
  $leftPos->{line} <=> $rightPos->{line}
    || $leftPos->{character} <=> $rightPos->{character};
}

sub dump_tokens_at_file_position {
  (my MY $self, my ($fileName, $line, $column)) = @_;
  $line //= 0;

  (my Part $part, my Template $tmpl, my $core)
    = $self->find_part_of_file_line($fileName, $line)
    or return;

  unless ($line < $tmpl->{cf_nlines} - 1) {
    # warn?
    return;
  }

  # my $yatt = $self->find_yatt_for_template($fileName);
  $core->ensure_parsed($part);

  my $declkind = defined $part->{declkind}
    ? [split /:/, $part->{declkind}] : [];

  if ($line < $part->{cf_bodyln} - 1) {
    # At declaration
    [decllist => $declkind
     , $self->part_decl_range($tmpl, $part)
     , $self->alttree($tmpl, $part->{decllist})];
  } elsif (UNIVERSAL::isa($part, 'YATT::Lite::Core::Widget')) {
    # At body of widget, page, args...
    my Widget $widget = $part;
    [body => $declkind
     , $self->part_body_range($tmpl, $part)
     , $self->alttree($tmpl, $widget->{tree})];
  } else {
    # At body of action, entity, ...
    # XXX: TODO extract tokens for host language.
    [body_string => $declkind
     , $self->part_body_range($tmpl, $part)
     , $part->{toks}];
  }
}

sub part_decl_range {
  (my MY $self, my Template $tmpl, my Part $part) = @_;
  my Range $range;
  $range->{start} = do {
    my Position $p;
    $p->{character} = 0;
    $p->{line} = $part->{cf_startln} - 1;
    $p;
  };
  $range->{end} = do {
    my Position $p;
    $p->{character} = 0;
    $p->{line} = $part->{cf_bodyln} - 1;
    $p;
  };
  $range;
}

sub part_body_range {
  (my MY $self, my Template $tmpl, my Part $part) = @_;
  my Range $range;
  $range->{start} = do {
    my Position $p;
    $p->{character} = 0;
    $p->{line} = $part->{cf_bodyln} - 1;
    $p;
  };
  $range->{end} = do {
    my Position $p;
    $p->{character} = 0;
    $p->{line} = $part->{cf_endln} - 1;
    $p;
  };
  $range;
}

sub find_part_of_file_line {
  (my MY $self, my ($fileName, $line)) = @_;
  $line //= 0;
  my ($tmpl, $core) = $self->find_template($fileName);
  my Part $prev;
  foreach my Part $part ($tmpl->list_parts) {
    last if $line < $part->{cf_startln} - 1;
    $prev = $part;
  }

  wantarray ? ($prev, $tmpl, $core) : $prev;
}

sub find_template {
  (my MY $self, my $fileName) = @_;
  my ($fn, $dir) = File::Basename::fileparse($fileName);
  my $yatt = $self->find_yatt_for_template($fileName);
  my $core = $yatt->get_trans;
  my $tmpl = $core->find_file($fn);
  # XXX: force refresh?
  wantarray ? ($tmpl, $core) : $tmpl;
}

sub find_yatt_for_template {
  (my MY $self, my $fileName) = @_;
  my ($fn, $dir) = File::Basename::fileparse($fileName);
  $self->{_SITE}->load_yatt($dir);
}

#========================================

#*cmd_list_entitiy = *cmd_list_entities;*cmd_list_entitiy = *cmd_list_entities;

sub cmd_show_file_line {
  (my MY $self, my @desc) = @_;
  $self->cli_output($self->show_file_line(@desc));
  ();
}
sub show_file_line {
  (my MY $self, my @desc) = @_;
  my ($file, $line) = do {
    if (@desc == 1 and ref $desc[0] eq 'HASH') {
      @{$desc[0]}{'file', 'line'}
    } else {
      @desc;
    }
  };

  my $lines = $self->{_file_line_cache}{$file} //= do {
    open my $fh, "<:utf8", $file or Carp::croak "Can't open $file: $!";
    chomp(my @lines = <$fh>);
    \@lines;
  };

  unless (defined $line) {
    Carp::croak "line is undef!";
  }

  [@desc, $lines->[$line - $self->{line_base}]];
}

sub cmd_list_entities {
  (my MY $self, my @args) = @_;
  $self->configure($self->parse_opts(\@args));
  my $widgetNameGlob = shift @args;

  require Sub::Identify;

  my %opts = @args == 1 ? %{$args[0]} : @args;

  my $searchFrom = delete $opts{from};
  if (%opts) {
    Carp::croak "Unknown options: ". join(", ", sort keys %opts);
  }

  my $cwdOrFileList = $self->list_target_dirs($searchFrom);

  my $emit_entities_in_entns; $emit_entities_in_entns = sub {
    my ($entns, $path) = @_;
    my $symtab = symtab($entns);
    foreach my $meth (sort grep {/^entity_/ and *{$symtab->{$_}}{CODE}}
                        keys %$symtab) {
      my ($file, $line) = Sub::Identify::get_code_location(*{$symtab->{$meth}}{CODE});
      $meth =~ s/^entity_//;
      my @result = (name => $meth, entns => $entns
                      , file => $file // $path, line => $line);
      $self->cli_output(
        $self->{detail} ? +{@result} : \@result
      );
    }
  };

  my %seen;
  my @superNS;
  walk_vfs_folders(
    factory => $self->{_SITE},
    from => $cwdOrFileList,
    ignore_symlink => $self->{ignore_symlink},
    dir => sub {
      my ($dir, $yatt) = @_;
      my $entns = $yatt->EntNS;
      return if $seen{$entns};
      push @superNS, grep {not $seen{$_}++} $dir->get_linear_isa_of_entns;
    },
    file => sub {
      my ($tmpl, $yatt) = @_;
      my $entns = $tmpl->cget('entns');
      foreach my $part ($tmpl->list_parts(YATT::Lite::Core->Entity)) {
        my @result = (name => $part->cget('name'), file => $tmpl->cget('path')
                        , line => $part->cget('startln'), entns => $entns);
        $self->cli_output(
          $self->{detail} ? +{@result} : \@result
        );
      }
      push @superNS, grep {not $seen{$_}++} $tmpl->get_linear_isa_of_entns;
    },
  );

  foreach my $superNS (@superNS) {
    my $path = YATT::Lite::Util::try_invoke($superNS, 'filename');
    $emit_entities_in_entns->($superNS, $path);
  }
}

sub cmd_list_vfs_folders {
  (my MY $self, my @args) = @_;
  $self->configure($self->parse_opts(\@args));
  my $widgetNameGlob = shift @args;

  my %opts = @args == 1 ? %{$args[0]} : @args;

  my $searchFrom = delete $opts{from};
  if (%opts) {
    Carp::croak "Unknown options: ". join(", ", sort keys %opts);
  }

  my $cwdOrFileList = $self->list_target_dirs($searchFrom);

  walk_vfs_folders(
    factory => $self->{_SITE},
    from => $cwdOrFileList,
    ignore_symlink => $self->{ignore_symlink},
    dir => sub {
      my ($dir, $yatt) = @_;
      # print join("\t", dir => $yatt->cget('dir'), $yatt->EntNS), "\n";
      my @result = (kind => 'dir', path => $dir->cget('path'),
                    entns => $dir->cget('entns'));
      $self->cli_output(\@result);
    },
    file => sub {
      my ($tmpl, $yatt) = @_;
      my @result = (kind => 'dir', path => $tmpl->cget('path'),
                    entns => $tmpl->cget('entns'));
      $self->cli_output(\@result);
    },
  );
}


#========================================

sub cmd_list_widgets {
  (my MY $self, my @args) = @_;
  $self->configure($self->parse_opts(\@args));
  my $widgetNameGlob = shift @args;
  my %opts = @args == 1 ? %{$args[0]} : @args;
  $opts{kind} = ['widget', 'page'];
  $self->cmd_list_parts($widgetNameGlob, \%opts);
}

sub cmd_list_actions {
  (my MY $self, my @args) = @_;
  $self->configure($self->parse_opts(\@args));
  my $widgetNameGlob = shift @args;
  my %opts = @args == 1 ? %{$args[0]} : @args;
  $opts{kind} = ['action'];
  $self->cmd_list_parts($widgetNameGlob, \%opts);
}

sub cmd_list_parts {
  (my MY $self, my @args) = @_;
  $self->configure($self->parse_opts(\@args));
  my $widgetNameGlob = shift @args;
  my %opts = @args == 1 ? %{$args[0]} : @args;
  my $searchFrom = delete $opts{from};
  my $onlyKind = delete $opts{kind};
  if (%opts) {
    Carp::croak "Unknown options: ". join(", ", sort keys %opts);
  }

  my $cwdOrFileList = $self->list_target_dirs($searchFrom);

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
      if ($onlyKind and not grep {$found->{kind} eq $_} lexpand($onlyKind)) {
        # XXX: 
        return;
      }
      my Template $tmpl = $widget->{cf_folder};
      my $path = $tmpl->{cf_path};
      my $args = $self->{detail}
        ? [$self->list_part_args_internal($widget)]
        : $widget->{arg_order};
      my @result = ((map {$_ => $found->{$_}} sort keys %$found)
                      , args => $args, path => $self->clean_path($path));
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
