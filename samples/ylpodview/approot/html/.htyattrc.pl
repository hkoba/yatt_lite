use strict;
use YATT::Lite::Util qw(lexpand);
use YATT::Lite qw/*CON/;

use fields qw/cf_docpath
	      cf_lang_available/;

Entity search_pod => sub {
  my ($this, $modname) = @_;
  my $modfn = modname2fileprefix($modname);
  my MY $yatt = $this->YATT;
  my $debug = -r "$yatt->{cf_dir}/.htdebug";
  my @dir = lexpand($yatt->{cf_docpath});
  my @suf = (map("$_.pod", $this->entity_suffix_list), ".pm");
  my @found;
  foreach my $dir (@dir) {
    foreach my $suf (@suf) {
      my $fn = "$dir/$modfn$suf";
      my $found = -r $fn;
      $CON->logdump(debug => ($found ? "found" : "not found"), $fn) if $debug;
      next unless $found;
      return $fn unless wantarray;
      push @found, $fn
    }
  }
  @found;
};

Entity suffix_list => sub {
  my ($this) = @_;
  my $lang = $this->entity_want_lang;
  if ($lang eq $this->entity_default_lang) {
    return ('')
  } else {
    return (".$lang", '');
  }
};

Entity podtree => sub {
  my ($this, $fn) = @_;
  unless (-r $fn) {
    die "Can't read '$fn'";
  }

  require Pod::Simple::SimpleTree;
  my $parser = Pod::Simple::SimpleTree->new;
  $parser->accept_targets(qw(html css syntax));
  my $tree = $parser->parse_file($fn)->root;
  &YATT::Lite::Breakpoint::breakpoint();
  postprocess($tree);
  wantarray ? @$tree : $tree;
};

sub postprocess {
  my ($list) = @_;
  # &YATT::Lite::Breakpoint::breakpoint() if ref $list ne 'ARRAY';
  my $hash = $list->[1];
  # &YATT::Lite::Breakpoint::breakpoint() if ref $hash ne 'HASH';
  for (my $i = $#$list; $i >= 2; $i--) {
    ref $list->[$i] and $list->[$i][0] eq 'X'
      or next;
    my ($xref) = splice @$list, $i;
    push @{$hash->{X}}, $xref->[-1];
  }
  foreach my $item (@{$list}[2..$#$list]) {
    next unless ref $item;
    postprocess($item);
  }
}

Entity bar2underscore => sub {
  my ($this, $str) = @_;
  $str =~ s/-/_/g;
  $str;
};

Entity read_xhf => sub {
  my $this = shift;
  $this->YATT->read_file_xhf(@_);
};

Entity podsection => sub {
  my $this = shift;
  my $group; $group = sub {
    my ($list, $curlevel, @init) = @_;
    my @result = ($curlevel, @init);
    while (@$list) {
      my ($lv) = $list->[0][0] =~ /^head(\d+)$/;
      unless (defined $lv) {
	push @result, shift @$list;
      } elsif ($lv > $curlevel) {
	push @result, $group->($list, $lv, shift @$list);
      } else {
	# $lv <= $curlevel
	last;
      }
    }
    return \@result;
  };
  my ($root, $atts, @tree) = $this->entity_podtree(@_);
  my @result;
  push @result, $group->(\@tree, 1, shift @tree) while @tree;
  @result;
};

Entity is_smartmobile => sub {
  my $this = shift;
  # XXX: PSGI
  $ENV{HTTP_USER_AGENT}
    && $ENV{HTTP_USER_AGENT} =~ /\b(iPhone|iPad|iPod|iOS|Android|webOS)\b/;
};

sub section_enc {
  my ($str) = @_;
  $str =~ s/^\s+|\s+$//g;
  $str =~ s{(?:(\s+) | ([^\s0-9A-Za-z_]+))}{
    $1 ? ('_' x length($1))
      : join('', map {sprintf "-%02X", unpack("C", $_)} split '', $2)
    }exg;
  "--$str";
}


Entity list2id => sub {
  my ($this, $list, $start) = @_;
  unless (ref $list) {
    section_enc($list);
  } else {
    join "", map {
      ref $_ ? $this->entity_list2id($_, 2) : section_enc($_);
    } @$list[($start // 2) .. $#$list];
  }
};

Entity lremoveKey => sub {
  my ($this, $key, $list, $until) = @_;
  return unless ref $list;
  $until //= 0;
  for (my $i = $#$list; $i >= $until; $i--) {
    ref $list->[$i] and $list->[$i][0] eq $key
      or next;
    splice @$list, $i;
  }
  $list;
};

Entity podlink => sub {
  my ($this, $name, $atts) = @_;
  defined (my $type = $atts->{type})
    or return '#--undef--';

  if ($type eq 'pod') {
    my $url = '';
    if (my $mod = $atts->{to}) {
      $url .= $CON->mkurl() . '?' . "$name=$mod";
    }
    if (my $sect = $atts->{section}) {
      $url .= '#'. section_enc($sect);
    }
    return $url;
  } elsif ($type eq 'url') {
    return "$atts->{to}"; # to stringify.
  } else {
    return "#-unknown-linktype-$type";
  }
};

Entity trim_leading_ws => sub {
  my ($this, $str) = @_;
  my ($head, @rest) = split /\n/, $str;
  if ($head =~ s/^\s+//) {
    my $prefix = $&;
    s/^$prefix// for @rest;
  }
  join "\n", $head, @rest;
};


sub pod_info {
  my ($fn) = @_;
  open my $fh, '<:encoding(utf8)', $fn or die "Can't open $fn: $!";
  # &YATT::Lite::Breakpoint::breakpoint();
  my ($podname, $lang) = $fn =~ m{([^/\.]+)(?:\.(\w+))?\.pod$};
  $lang ||= EntNS->entity_default_lang();
  local $_;
  while (<$fh>) {
    chomp;
    # Note: eof($fh) is important to avoid flip-flop stay on.
    my $line = /^=head1 NAME/ .. (/^[^\s=].*/ || eof($fh))
      or next;
    # Encode::encode("utf-8", $_)
    return [$podname, $lang, $_] if $line =~ /E0$/
  }
  return;
}

Entity docpath_files => sub {
  my ($this, $ext) = @_;
  my YATT $yatt = $this->YATT;
  my ($dir) = lexpand($yatt->{cf_docpath})
    or return;

  # &YATT::Lite::Breakpoint::breakpoint();
  $ext =~ s/^\.*/./;
  my $want_lang = $this->entity_want_lang;

  my %gathered;
  foreach my $info (map { pod_info($_) } glob("$dir/*$ext")) {
    my ($name, $lang, $title) = @$info;
    $gathered{$name} //= [$name, [], ""];
    if ($lang eq $want_lang) {
      $gathered{$name}[2] = $title;
    } else {
      push @{$gathered{$name}[1]}, $lang;
    }
  }
  sort {$$a[0] cmp $$b[0]} values %gathered;
};

sub modname2fileprefix {
  my ($mod) = @_;
  $mod =~ s,::,/,g;
  $mod =~ s,^/+|/+$,,g;
  $mod;
}
