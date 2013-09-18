package YATT::Lite::Util;
use strict;
use warnings FATAL => qw(all);

use URI::Escape ();
use Tie::IxHash;

require Scalar::Util;

{
  package YATT::Lite::Util;
  use Exporter qw(import);
  BEGIN {
    $INC{'YATT/Lite/Util.pm'} = 1;
    our @EXPORT = qw/numLines coalesce default globref symtab lexpand escape
		     untaint_any ckeval ckrequire untaint_unless_tainted
		     dict_sort terse_dump catch
		     nonempty
		     subname
		   /;
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

  sub nonempty {
    defined $_[0] && $_[0] ne '';
  }

  sub globref {
    my ($thing, $name) = @_;
    my $class = ref $thing || $thing;
    no strict 'refs';
    \*{join("::", $class, defined $name ? $name : ())};
  }
  sub symtab {
    *{globref(shift, '')}{HASH}
  }
  # XXX: Nice to have look_for_symtab, too.
  sub look_for_globref {
    my ($class, $name) = @_;
    my $symtab = symtab($class);
    return undef unless defined $symtab->{$name};
    globref($class, $name);
  }
  sub fields_hash {
    my $sym = look_for_globref(shift, 'FIELDS')
      or return undef;
    *{$sym}{HASH};
  }
  sub lexpand {
    # lexpand can be used to counting.
    unless (defined $_[0]) {
      wantarray ? () : 0;
    } elsif (not ref $_[0]) {
      $_[0]
    } elsif (ref $_[0] eq 'ARRAY') {
      @{$_[0]}
    } elsif (ref $_[0] eq 'HASH') {
      %{$_[0]}
    } else {
      wantarray ? () : 0;
    }
  }
  sub lsearch (&@) {
    my $sub = shift;
    my $i = 0;
    foreach (@_) {
      return $i if $sub->($_);
    } continue {$i++}
    return;
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
    if ($] < 5.014) {
      if (wantarray) {
	@__RESULT__ = eval $__SCRIPT__;
      } else {
	$__RESULT__[0] = eval $__SCRIPT__;
      }
      die $@ if $@;
    } else {
      local $@;
      if (wantarray) {
	@__RESULT__ = eval $__SCRIPT__;
      } else {
	$__RESULT__[0] = eval $__SCRIPT__;
      }
      die $@ if $@;
    }
    wantarray ? @__RESULT__ : $__RESULT__[0];
  }
  sub ckrequire {
    ckeval("require $_[0]");
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
    my ($path, $startDir, $cut_depth) = @_;
    # $startDir is $app_root.
    # $doc_root should resides under $app_root.
    $cut_depth //= 1;
    $startDir =~ s,/+$,,;
    unless ($path =~ m{^\Q$startDir\E}gxs) {
      die "Can't split_path: prefix mismatch: $startDir vs $path";
    }

    my ($dir, $pos, $file) = ($startDir, pos($path));
    # *DO NOT* initialize $file. This loop relies on undefined-ness of $file.
    while ($path =~ m{\G/+([^/]*)}gcxs and -e "$dir/$1" and not defined $file) {
      if (-d _) {
	$dir .= "/$1";
      } else {
	$file = $1;
	# *DO NOT* last. To match one more time.
      }
    } continue {
      $pos = pos($path);
    }

    $dir .= "/" if $dir !~ m{/$};
    my $subpath = substr($path, $pos);
    if (not defined $file) {
      if ($subpath =~ m{^/(\w+)(?:/|$)} and -e "$dir/$1.yatt") {
	$subpath = substr($subpath, 1+length $1);
	$file = "$1.yatt";
      } elsif (-e "$dir/index.yatt") {
	# index.yatt should subsume all subpath.
      } elsif ($subpath =~ s{^/([^/]+)$}{}) {
	# Note: Actually, $file is not accesible in this case.
	# This is just for better error diag.
	$file = $1;
      }
    }

    my $loc = substr($dir, length($startDir));
    while ($cut_depth-- > 0) {
      $loc =~ s,^/[^/]+,,
	or croak "Can't cut path location: $loc";
      $startDir .= $&;
    }

    ($startDir
     , $loc
     , $file // ''
     , $subpath
     , (not defined $file)
    );
  }

  sub lookup_dir {
    my ($loc, $dirlist) = @_;
    $loc =~ s{^/*}{/};
    foreach my $dir (@$dirlist) {
      my $real = "$dir$loc";
      next unless -d $real;
      return wantarray ? ($real, $dir) : $real;
    }
  }

  sub lookup_path {
    my ($path_info, $dirlist, $index_name, $want_ext, $use_subpath) = @_;
    $index_name //= 'index';
    $want_ext //= '.yatt';
    my $ixfn = $index_name . $want_ext;
    my @dirlist = grep {defined $_ and -d $_} @$dirlist;
    my $pi = $path_info;
    my ($loc, $cur, $ext) = ("", "");
  DIG:
    while ($pi =~ s{^/+([^/]+)}{}) {
      $cur = $1;
      $ext = ($cur =~ s/(\.[^\.]+)$// ? $1 : undef);
      foreach my $dir (@dirlist) {
	my $base = "$dir$loc/$cur";
	if (defined $ext and -r "$base$ext") {
	  # If extension is specified and it is readable, use it.
	  return ($dir, "$loc/", "$cur$ext", $pi);
	} elsif ($pi =~ m{^/} and -d $base) {
	  # path_info has '/' and directory exists.
	  next; # candidate
	} elsif (-r (my $fn = "$base$want_ext")) {
	  return ($dir, "$loc/", "$cur$want_ext", $pi);
	} elsif ($use_subpath
		 and -r (my $alt = "$dir$loc/$ixfn")) {
	  $ext //= "";
	  return ($dir, "$loc/", $ixfn, "/$cur$ext$pi", 1);
	} else {
	  # Neither dir nor $cur$want_ext exists, it should be ignored.
	  undef $dir;
	}
      }
    } continue {
      $loc .= "/$cur";
      @dirlist = grep {defined} @dirlist;
    }

    return unless $pi =~ m{^/+$};

    foreach my $dir (@dirlist) {
      next unless -r "$dir$loc/$ixfn";
      return ($dir, "$loc/", "$ixfn", "", 1);
    }

    return;
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
		   --> --&gt;
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
	} elsif (not ref $str) {
	  my $copy = $str;
	  $copy =~ s{([<>&\"\'])}{$escape{$1}}g;
	  $copy;
	} elsif (ref $str eq 'SCALAR') {
	  # PASS Thru. (Already escaped)
	  $$str;
	} elsif (my $sub = UNIVERSAL::can($str, 'as_escaped')) {
	  $sub->($str);
	} elsif ($sub = UNIVERSAL::can($str, 'cf_pairs')) {
	  ref($str).'->new('.(join(", ", map {
	    my ($k, $v) = @$_;
	    "$k => " . do {
	      my $esc = escape($v);
	      if (not defined $esc) {
		'undef'
	      } elsif ($esc eq '') {
		"''"
	      } else {
		$esc;
	      }
	    };
	  } $sub->($str))).')';
	} else {
	  # XXX: Is this secure???
	  # XXX: Should be JSON?
	  my $copy = terse_dump($str);
	  $copy =~ s{([<\"]|-->)}{$escape{$1}}g; # XXX: Minimum. May be insecure.
	  $copy;
	}
      };
    }
    wantarray ? @result : $result[0];
  }
}

{
  package
    YATT::Lite::Util::named_attr;
  use overload qw("" as_string);
  sub as_string {
    shift->[-1];
  }
  sub as_escaped {
    sprintf q{ %s="%s"}, $_[0][0], $_[0][1];
  }
}

sub named_attr {
  my $attname = shift;
  my @result = grep {defined $_ && $_ ne ''} @_;
  return '' unless @result;
  bless [$attname, join ' ', map {escape($_)} @result]
    , 'YATT::Lite::Util::named_attr';
}

{
  # XXX: These functions are deprecated. Use att_value_in() instead.

  sub value_checked  { _value_checked($_[0], $_[1], checked => '') }
  sub value_selected { _value_checked($_[0], $_[1], selected => '') }

  sub _value_checked {
    my ($value, $hash, $then, $else) = @_;
    sprintf q|value="%s"%s|, escape($value)
      , _if_checked($hash, $value, $then, $else);
  }

  sub _if_checked {
    my ($in, $value, $then, $else) = @_;
    $else //= '';
    return $else unless defined $in;
    if (ref $in ? $in->{$value // ''} : ($in eq $value)) {
      " $then"
    } else {
      $else;
    }
  }
}

{
  our %input_types = qw!select 0 radio 1 checkbox 2!;
  sub att_value_in {
    my ($in, $type, $name, $formal_value, $as_value) = @_;
    defined (my $typeid = $input_types{$type})
      or croak "Unknown type: $type";

    unless (defined $name and $name ne '') {
      croak "name is empty";
    }

    unless (defined $formal_value and $formal_value ne '') {
      croak "value is empty";
    }

    my @res;

    if ($type and $typeid) {
      push @res, qq|type="$type"|;
    }

    if ($typeid) {
      my $sfx = $typeid ? '['.escape($formal_value).']' : '';
      push @res, qq|name="@{[escape($name)]}$sfx"|;
    }

    if (not $typeid) {
      # select
      push @res, qq|value="@{[escape($formal_value)]}"|;
    } elsif ($as_value) {
      # checkbox/radio, with explicit value
      push @res, qq|value="@{[escape($as_value)]}"|;
    }

    if (find_value_in($in, $name, $formal_value)) {
      push @res, $typeid ? "checked" : "selected";
    }

    join(" ", @res);
  }

  sub find_value_in {
    my ($in, $name, $formal_value) = @_;

    my $actual_value = do {
      if (my $sub = $in->can("param")) {
	$sub->($in, $name);
      } elsif (ref $in eq 'HASH') {
	$in->{$name};
      } else {
	croak "Can't extract parameter from $in";
      }
    };

    if (not defined $actual_value) {
      0
    } elsif (not ref $actual_value) {
      $actual_value eq $formal_value
    } elsif (ref $actual_value eq 'HASH') {
      $actual_value->{$formal_value};
    } elsif (ref $actual_value eq 'ARRAY') {
      defined lsearch {$_ eq $formal_value} @$actual_value
    } else {
      undef
    }
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
  # XXX: Forward slash (and ':') is allowed, for cleaner url. This may break...
  $encode
    =~ s{([^A-Za-z0-9\-_.!~*'() /:])}{ uc sprintf "%%%02x",ord $1 }eg;
  $encode =~ tr/ /+/;
  return $encode;
}

sub url_encode_kv {
  my ($self, $k, $v) = @_;
  url_encode($self, $k) . '=' . url_encode($self, $v);
}

sub encode_query {
  my ($self, $param, $sep) = @_;
#  require URI;
#  my $url = URI->new('http:');
#  $url->query_form($item->{cf_PARAM});
#  $url->query;
  return $param unless ref $param;
  join $sep // ';', do {
    if (ref $param eq 'HASH') {
      map {
	url_encode_kv($self, $_, $param->{$_});
      } keys %$param
    } else {
      my @param = @$param;
      my @res;
      while (my ($k, $v) = splice @param, 0, 2) {
	my $ek = url_encode($self, $k);
	push @res, $ek . '='. url_encode($self, $_)
	  for ref $v ? @$v : $v;
      }
      @res;
    }
  };
}

sub callerinfo {
  my ($pkg, $file, $line) = caller(shift // 1);
  (file => $file, line => $line);
}

sub ostream {
  my $fn = ref $_[0] ? $_[0] : \ ($_[0] //= "");
  open my $fh, '>' . ($_[1] // ''), $fn
    or die "Can't create output memory stream: $!";
  $fh;
}

sub read_file {
  my ($fn, $layer) = @_;
  open my $fh, '<' . ($layer // ''), $fn or die "Can't open '$fn': $!";
  local $/;
  scalar <$fh>;
}

sub dispatch_all {
  my ($this, $con, $prefix, $argSpec) = splice @_, 0, 4;
  my ($nargs, @preargs) = ref $argSpec ? @$argSpec : $argSpec;
  my @queue;
  foreach my $item (@_) {
    if (ref $item) {
      print {$con} escape(splice @queue) if @queue;
      my ($wname, @args) = @$item;
      my $sub = $this->can('render_' . $prefix . $wname)
	or croak "Can't find widget '$wname' in dispatch";
      $sub->($this, $con, @preargs, splice(@args, 0, $nargs // 0), \@args);
    } else {
      push @queue, $item;
    }
  }
  print {$con} escape(@queue) if @queue;
}

sub dispatch_one {
  my ($this, $con, $prefix, $nargs, $item) = @_;
  if (ref $item) {
    my ($wname, @args) = @$item;
    my $sub = $this->can('render_' . $prefix . $wname)
      or croak "Can't find widget '$wname' in dispatch";
    $sub->($this, $con, splice(@args, 0, $nargs // 0), \@args);
  } else {
    print {$con} escape($item);
  }
}

sub con_error {
  my ($con, $err, @args) = @_;
  if ($con->can("raise") and my $sub = $con->can("error")) {
    $sub->($con, $err, @args)
  } else {
    sprintf $err, @args;
  }
}

sub safe_render {
  my ($this, $con, $wspec, @args) = @_;
  my @nsegs = lexpand($wspec);
  my $wname = join _ => map {defined $_ ? $_ : ''} @nsegs;
  my $sub = $this->can("render_$wname")
    or die con_error($con, "Can't find widget '%s'", $wname);
  $sub->($this, $con, @args);
}

sub mk_http_status {
  my ($code) = @_;
  require HTTP::Status;

  my $message = HTTP::Status::status_message($code);
  "Status: $code $message\015\012";
}

sub list_isa {
  my ($pack, $all) = @_;
  my $symtab = symtab($pack);
  my $sym = $symtab->{ISA} or return;
  my $isa = *{$sym}{ARRAY} or return;
  return @$isa unless $all;
  map {
    [$_, list_isa($_, $all)];
  } @$isa;
}

sub get_locale_encoding {
  require Encode;
  require encoding;
  Encode::find_encoding(encoding::_get_locale_encoding())->name;
}

sub set_inc {
  my ($pkg, $val) = @_;
  $pkg =~ s|::|/|g;
  $INC{$pkg.'.pm'} = $val || 1;
  # $INC{$pkg.'.pmc'} = $val || 1;
  $_[1];
}

sub try_invoke {
  my $obj = shift;
  my ($method, @args) = lexpand(shift);
  my $default = shift;
  if (my $sub = UNIVERSAL::can($obj, $method)) {
    $sub->($obj, @args);
  } else {
    wantarray ? () : $default;
  }
}

sub NIMPL {
  my ($pack, $file, $line, $sub, $hasargs) = caller($_[0] // 1);
  croak "Not implemented call of '$sub'";
}

sub shallow_copy {
  if (ref $_[0] eq 'HASH') {
    +{%{$_[0]}};
  } elsif (ref $_[0] eq 'ARRAY') {
    +[@{$_[0]}];
  } elsif (not ref $_[0]) {
    my $copy = $_[0];
  } elsif ($_[1]) {
    # Pass thru unknown refs if 2nd arg is true.
    $_[0];
  } else {
    croak "Unsupported data type for shallow_copy: " . ref $_[0];
  }
}

if (catch {require Sub::Name}) {
  *subname = sub { my ($name, $sub) = @_; $sub }
} else {
  *subname = *Sub::Name::subname;
}

sub incr_opt {
  my ($key, $list) = @_;
  my $hash = do {
    if (@$list and defined $list->[0] and ref $list->[0] eq 'HASH') {
      shift @$list;
    } else {
      +{}
    }
  };
  $hash->{$key}++;
  $hash;
}

sub num_is_ge {
  defined $_[0] and not ref $_[0] and $_[0] ne ''
    and $_[0] =~ /^\d+$/ and $& >= $_[1];
}

# Order preserving unique.
sub unique (@) {
  my %dup;
  map {$dup{$_}++ ? () : $_} @_;
}

sub secure_text_plain {
  shift;
  ("Content-type" => "text/plain; charset=utf-8"
   , "X-Content-Type-Options" => "nosniff"  # To protect IE8~ from XSS.
   );
}

sub psgi_error {
  my ($self, $status, $msg, @rest) = @_;
  return [$status, [$self->secure_text_plain, @rest], [escape($msg)]];
}

sub ixhash {
  tie my %hash, 'Tie::IxHash', @_;
  \%hash;
}

# Ported from: Rack::Utils.parse_nested_query
sub parse_nested_query {
  return {} unless defined $_[0] and $_[0] ne '';
  my ($enc) = $_[1];
  my $params = $_[2] // ixhash();
  foreach my $p (split /[;&]/, $_[0]) {
    my ($k, $v) = map {
      s/\+/ /g;
      my $raw = URI::Escape::uri_unescape($_);
      $enc ? Encode::decode($enc, $raw) : $raw;
    } split /=/, $p, 2;
    normalize_params($params, $k, $v) if defined $k;
  }
  $params;
}

sub normalize_params {
  my ($params, $name, $v) = @_;
  my ($k) = $name =~ m(\A[\[\]]*([^\[\]]+)\]*)
    or return;

  my $after = substr($name, length $&);

  if ($after eq '') {
    $params->{$k} = $v;
  } elsif ($after eq "[]") {
    my $item = $params->{$k} //= [];
    croak "expected ARRAY (got ".(ref $item || 'String').") for param `$k'"
      unless ref $item eq 'ARRAY';
    push @$item, $v;
  } elsif ($after =~ m(^\[\]\[([^\[\]]+)\]$) or $after =~ m(^\[\](.+)$)) {
    my $child_key = $1;
    my $item = $params->{$k} //= [];
    croak "expected ARRAY (got ".(ref $item || 'String').") for param `$k'"
      unless ref $item eq 'ARRAY';
    if (@$item and ref $item->[-1] eq 'HASH'
	and not exists $item->[-1]->{$child_key}) {
      normalize_params($item->[-1], $child_key, $v);
    } else {
      push @$item, normalize_params(ixhash(), $child_key, $v);
    }
  } else {
    my $item = $params->{$k} //= ixhash();
    croak "expected HASH (got ".(ref $item || 'String').") for param `$k'"
      unless ref $item eq 'HASH';
    $params->{$k} = normalize_params($item, $after, $v);
  }

  $params;
}

#
# to put all functions into @EXPORT_OK.
#
{
  our @EXPORT_OK;
  my $symtab = symtab(__PACKAGE__);
  foreach my $name (grep {/^[a-z]/} keys %$symtab) {
    my $glob = $symtab->{$name};
    next unless *{$glob}{CODE};
    push @EXPORT_OK, $name;
  }
}

1;
