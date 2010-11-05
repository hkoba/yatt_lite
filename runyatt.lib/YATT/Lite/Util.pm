package YATT::Lite::Util;
use strict;
use warnings FATAL => qw(all);

require Scalar::Util;

{
  package YATT::Lite::Util;
  use Exporter qw(import);
  BEGIN {
    $INC{'YATT/Lite/Util.pm'} = 1;
    our @EXPORT = qw(numLines coalesce default globref symtab lexpand escape
		     untaint_any ckeval ckrequire ckdo untaint_unless_tainted
		     dict_sort terse_dump catch
		   );
    our @EXPORT_OK = (@EXPORT, qw(cached_in split_path rootname dict_order
				  appname extname
				  captured is_debugging callerinfo
				  dofile_in compile_file_in
				  url_encode url_decode
				  ostream
				));
  }
  use Carp;
  sub numLines {
    croak "undefined value for numLines!" unless defined $_[0];
    $_[0] =~ tr|\n||;
  }
  sub coalesce {
    foreach my $item (@_) {
      return $item if defined $item;
    }
    undef;
  }
  *default = \*coalesce;

  sub globref {
    my ($thing, $name) = @_;
    my $class = ref $thing || $thing;
    no strict 'refs';
    \*{join("::", $class, $name)};
  }
  sub symtab {
    *{globref(shift, '')}{HASH}
  }

  sub fields_hash {
    *{globref(shift, 'FIELDS')}{HASH};
  }
  sub lexpand {
    unless (defined $_[0]) {
      wantarray ? () : 0
    } elsif (not ref $_[0]) {
      $_[0]
    } else {
      @{$_[0]}
    }
  }
  # $fn:e
  sub extname { my $fn = shift; return $1 if $fn =~ s/\.(\w+)$// }
  # $fn:r
  sub rootname { my $fn = shift; $fn =~ s/\.\w+$//; join "", $fn, @_ }
  # $fn:r:t
  sub appname {
    my $fn = shift;
    $fn =~ s/\.\w+$//;
    return $1 if $fn =~ m{(\w+)$};
  }
  sub untaint_any { $_[0] =~ m{.*}s; $& }
  our $DEBUG_INJECT_TAINTED = 0;
  # untaint_unless_tainted($fn, read_file($fn))
  sub untaint_unless_tainted {
    return $_[1] unless ${^TAINT};
    if (defined $_[0] and not Scalar::Util::tainted($_[0])) {
      $DEBUG_INJECT_TAINTED ? $_[1] : untaint_any($_[1]);
    } else {
      $_[1];
    }
  }
  sub ckeval {
    my $__SCRIPT__ = join "", grep {
      defined $_ and Scalar::Util::tainted($_) ? croak "tainted! '$_'" : 1;
    } @_;
    my @__RESULT__;
    if (wantarray) {
      @__RESULT__ = eval $__SCRIPT__;
    } else {
      $__RESULT__[0] = eval $__SCRIPT__;
    }
    die $@ if $@;
    wantarray ? @__RESULT__ : $__RESULT__[0];
  }
  sub ckrequire {
    ckeval("require $_[0]");
  }
  sub ckdo {
    my @__RESULT__;
    if (wantarray) {
      @__RESULT__ = do $_[0];
    } else {
      $__RESULT__[0] = do $_[0];
    }
    die $@ if $@;
    wantarray ? @__RESULT__ : $__RESULT__[0];
  }
  use Scalar::Util qw(refaddr);
  sub cached_in {
    my ($dir, $dict, $name, $sys, $mark, $loader, $refresher) = @_;
    if (not exists $dict->{$name}) {
      my $item = $dict->{$name} = $loader ? $loader->($dir, $sys, $name)
	: $dir->load($sys, $name);
      $mark->{refaddr($item)} = 1 if $item and $mark;
      $item;
    } else {
      my $item = $dict->{$name};
      unless ($item and ref $item
	      and (not $mark or not $mark->{refaddr($item)}++)) {
	# nop
      } elsif ($refresher) {
	$refresher->($item, $sys, $name)
      } elsif (my $sub = UNIVERSAL::can($item, 'refresh')) {
	$sub->($item, $sys);
      }
      $item;
    }
  }

  sub split_path {
    my ($path, $startDir) = @_;
    $startDir ||= '';
    $startDir =~ s,/+$,,;
    unless ($path =~ m{^\Q$startDir\E}gxs) {
      die "Can't split_path: prefix mismatch: $startDir vs $path";
    }
    my ($dir, $pos, $file) = ($startDir, pos($path));
    while ($path =~ m{\G/+([^/]*)}gcxs and -e "$dir/$1" and not defined $file) {
      if (-d _) {
	$dir .= "/$1";
      } else {
	$file = $1;
      }
    } continue {
      $pos = pos($path);
    }
    unless (defined $file) {
      croak "Can't recognize target file for $path, startDir=$startDir";
    }
    ($startDir, substr($dir, length($startDir)), $file, substr($path, $pos));
  }

  sub dict_order {
    my ($a, $b, $start) = @_;
    $start = 1 unless defined $start;
    my ($result, $i) = (0);
    for ($i = $start; $i <= $#$a and $i <= $#$b; $i++) {
      if ($a->[$i] =~ /^\d/ and $b->[$i] =~ /^\d/) {
	$result = $a->[$i] <=> $b->[$i];
      } else {
	$result = $a->[$i] cmp $b->[$i];
      }
      return $result unless $result == 0;
    }
    return $#$a <=> $#$b;
  }

  # a   => ['a', 'a']
  # q1a => ['q1a', 'q', 1, 'a']
  # q11b => ['q11b', 'q', 11, 'b']
  sub dict_sort (@) {
    map {$_->[0]} sort {dict_order($a,$b)} map {[$_, split /(\d+)/]} @_;
  }

  sub captured (&) {
    my ($code) = @_;
    open my $fh, '>', \ (my $buffer = "") or die "Can't create capture buf:$!";
    $code->($fh);
    $buffer;
  }

  sub terse_dump {
    require Data::Dumper;
    join ", ", map {
      Data::Dumper->new([$_])->Terse(1)->Indent(0)->Dump;
    } @_;
  }

  sub is_debugging {
    my $symtab = $main::{'DB::'} or return 0;
    defined ${*{$symtab}{HASH}}{cmd_b}
  }

  sub catch (&) {
    my ($sub) = @_;
    local $@ = '';
    eval { $sub->() };
    $@;
  }
}

sub dofile_in {
  my ($pkg, $file) = @_;
  unless (-e $file) {
    croak "No such file: $file\n";
  } elsif (not -r _) {
    croak "Can't read file: $file\n";
  }
  ckeval("package $pkg; my \$result = do '$file'; die \$\@ if \$\@; \$result");
}

sub compile_file_in {
  my ($pkg, $file) = @_;
  my $sub = dofile_in($pkg, $file);
  unless (defined $sub and ref $sub eq 'CODE') {
    die "file '$file' should return CODE (but not)!\n";
  }
  $sub;
}


BEGIN {
  my %escape = (qw(< &lt;
		   > &gt;
		   " &quot;
		   & &amp;)
		, "\'", "&#39;");

  our $ESCAPE_UNDEF = '';

  sub escape {
    return if wantarray && !@_;
    my @result;
    foreach my $str (@_) {
      push @result, do {
	unless (defined $str) {
	  $ESCAPE_UNDEF;
	} elsif (ref $str eq 'SCALAR') {
	  # PASS Thru. (Already escaped)
	  $$str;
	} else {
	  my $copy = $str;
	  $copy =~ s{([<>&\"\'])}{$escape{$1}}g;
	  $copy;
	}
      };
    }
    wantarray ? @result : $result[0];
  }
}

# Verbatimly stolen from CGI::Simple
sub url_decode {
  my ( $self, $decode ) = @_;
  return () unless defined $decode;
  $decode =~ tr/+/ /;
  $decode =~ s/%([a-fA-F0-9]{2})/ pack "C", hex $1 /eg;
  return $decode;
}

sub url_encode {
  my ( $self, $encode ) = @_;
  return () unless defined $encode;
  $encode
    =~ s/([^A-Za-z0-9\-_.!~*'() ])/ uc sprintf "%%%02x",ord $1 /eg;
  $encode =~ tr/ /+/;
  return $encode;
}

sub callerinfo {
  my ($pkg, $file, $line) = caller(shift // 1);
  (file => $file, line => $line);
}

sub ostream {
  my $fn = ref $_[0] ? $_[0] : \ ($_[0] //= "");
  open my $fh, '>', $fn or die "Can't create output memory stream: $!";
  # XXX: IOLayer, encoding...
  $fh;
}

1;
