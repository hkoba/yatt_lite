package YATT::Lite::XHF; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use Carp;

our $VERSION = "0.02";

use base qw(YATT::Lite::Object);
use fields qw(cf_FH cf_filename cf_string cf_tokens
	      fh_configured
	      cf_allow_empty_name
	      cf_encoding cf_crlf
	      cf_nocr cf_subst
	      cf_skip_comment cf_bytes);

use Exporter qw(import);
our @EXPORT = qw(read_file_xhf);
our @EXPORT_OK = (@EXPORT, qw(parse_xhf $cc_name));

use YATT::Lite::Util;
use YATT::Lite::Util::Enum _ => [qw(NAME SIGIL VALUE)];

our $cc_name  = qr{\w|[\.\-/~!]};
our $re_suffix= qr{\[$cc_name*\]};
our $cc_sigil = qr{[:\#,\-=\[\]\{\}]};
our $cc_tabsp = qr{[\ \t]};

our %OPN = ('[' => \&organize_array, '{' => \&organize_hash
	    , '=' => \&organize_expr);
our %CLO = (']' => '[', '}' => '{');
our %NAME_LESS = (%CLO, '-' => 1);
our %ALLOW_EMPTY_NAME = (':' => 1);

sub read_file_xhf {
  my ($pack, $fn, @rest) = @_;
  MY->new(filename => $fn, encoding => 'utf8', @rest)->read;
}

sub parse_xhf {
  MY->new(string => @_)->read;
}

*configure_file = \&configure_filename;
*configure_file = \&configure_filename;
sub configure_filename {
  (my MY $self, my ($fn)) = @_;
  open $self->{cf_FH}, '<', $fn
    or croak "Can't open file '$fn': $!";
  $self->{fh_configured} = 0;
  $self->{cf_filename} = $fn;
  $self;
}

# To accept in-stream encoding spec.
# (See YATT::Lite::Test::XHFTest::load and t/lite_xhf.t)
sub configure_encoding {
  (my MY $self, my $value) = @_;
  $self->{fh_configured} = 0;
  $self->{cf_encoding} = $value;
}

sub configure_binary {
  (my MY $self, my $value) = @_;
  warnings::warnif(deprecated =>
		   "XHF option 'binary' is deprecated, use 'bytes' instead");
  $self->{cf_bytes} = $value;
}

sub configure_string {
  my MY $self = shift;
  ($self->{cf_string}) = @_;
  open $self->{cf_FH}, '<', \ $self->{cf_string}
    or croak "Can't create string stream: $!";
  $self;
}

# XXX: Is this should renamed to read_all?
sub read {
  my MY $self = shift;
  $self->cf_let(\@_, sub {
		  if (my @tokens = $self->tokenize) {
		    $self->organize(@tokens);
		  } else {
		    return;
		  }
		});
}

sub tokenize {
  (my MY $self) = @_;
  local $/ = "";
  my $fh = $$self{cf_FH};
  unless ($self->{fh_configured}++) {
    if (not $self->{cf_bytes} and not $self->{cf_string}
	and $self->{cf_encoding}) {
      binmode $fh, ":encoding($self->{cf_encoding})";
    }
    if ($self->{cf_crlf}) {
      binmode $fh, ":crlf";
    }
  }

  my @tokens;
 LOOP: {
    do {
      defined (my $para = <$fh>) or last LOOP;
      $para = untaint_unless_tainted
	($self->{cf_filename} // $self->{cf_string}
	 , $para);
      @tokens = $self->tokenize_1($para);
    } until (not $self->{cf_skip_comment} or @tokens);
  }
  @tokens;
}

sub tokenize_1 {
  my MY $reader = shift;
  $_[0] =~ s{\n+$}{\n}s;
  $_[0] =~ s{\r+}{}g if $reader->{cf_nocr};
  if (my $sub = $reader->{cf_subst}) {
    local $_;
    *_ =  \ $_[0];
    $sub->($_);
  }
  my ($pos, $ncomments, @tokens, @result);
  foreach my $token (@tokens = split /(?<=\n)(?=[^\ \t])/, $_[0]) {
    $pos++;
    if ($token =~ s{^(?:\#[^\n]*(?:\n|$))+}{}) {
      $ncomments++;
      next if $token eq '';
    }

    unless ($token =~ s{^($cc_name*$re_suffix*) ($cc_sigil) (?:($cc_tabsp)|(\n|$))}{}x) {
      croak "Invalid XHF token '$token': line " . token_lineno(\@tokens, $pos);
    }
    my ($name, $sigil, $tabsp, $eol) = ($1, $2, $3, $4);

    if ($name eq '') {
      croak "Invalid XHF token(name is empty for '$token')"
	if $sigil eq ':' and not $reader->{cf_allow_empty_name};
    } elsif ($NAME_LESS{$sigil}) {
      croak "Invalid XHF token('$sigil' should not be prefixed by name '$name')"
    }

    # Comment fields are ignored.
    $ncomments++, next if $sigil eq "#";

    if ($CLO{$sigil}) {
      undef $name;
    }

    # Line continuation.
    $token =~ s/\n[\ \t]/\n/g;

    unless (defined $eol) {
      # Values are trimmed unless $eol
      $token =~ s/^\s+|\s+$//gs;
    } else {
      # Deny:  name{ foo
      # Allow: name[ foo
      croak "Invalid XHF token(container with value): "
	. join("", grep {defined $_} $name, $sigil, $tabsp, $token)
	  if $sigil eq '{' and $token ne "";

      # Trim leading space for $tabsp eq "\n".
      $token =~ s/^[\ \t]//;
    }
    push @result, [$name, $sigil, $token];
  }

  # Comment only paragraph should return nothing.
  return if $ncomments && !@result;

  wantarray ? @result : \@result;
}

sub token_lineno {
  my ($tokens, $pos) = @_;
  my $lineno = 1;
  $lineno += tr|\n|| for grep {defined} @$tokens[0 .. $pos];
  $lineno;
}

sub organize {
  my MY $reader = shift;
  my @result;
  while (@_) {
    my $desc = shift;
    unless (defined $desc->[_NAME]) {
      croak "Invalid XHF: Field close '$desc->[_SIGIL]' without open!";
    }
    push @result, $desc->[_NAME] if $desc->[_NAME] ne ''
      or $ALLOW_EMPTY_NAME{$desc->[_SIGIL]};
    if (my $sub = $OPN{$desc->[_SIGIL]}) {
      # sigil がある時、value を無視して、良いのか?
      push @result, $sub->($reader, \@_, $desc);
    } else {
      push @result, $desc->[_VALUE];
    }
  }
  if (wantarray) {
    @result
  } else {
    my %hash = @result;
    \%hash;
  }
}

# '[' block
sub organize_array {
  (my MY $reader, my ($tokens, $first)) = @_;
  my @result;
  push @result, $first->[_VALUE] if defined $first and $first->[_VALUE] ne '';
  while (@$tokens) {
    my $desc = shift @$tokens;
    # NAME
    unless (defined $desc->[_NAME]) {
      if ($desc->[_SIGIL] ne ']') {
	croak "Invalid XHF: paren mismatch. '[' is closed by '$desc->[_SIGIL]'";
      }
      return \@result;
    }
    elsif ($desc->[_NAME] ne '') {
      push @result, $desc->[_NAME];
    }
    # VALUE
    if (my $sub = $OPN{$desc->[_SIGIL]}) {
      # sigil がある時、value があったらどうするかは、子供次第。
      push @result, $sub->($reader, $tokens, $desc);
    }
    else {
      push @result, $desc->[_VALUE];
    }
  }
  croak "Invalid XHF: Missing close ']'";
}

# '{' block.
sub organize_hash {
  (my MY $reader, my ($tokens, $first)) = @_;
  die "Invalid XHF hash block beginning! ". join("", @$first)
    if defined $first and $first->[_VALUE] ne '';
  my %result;
  while (@$tokens) {
    my $desc = shift @$tokens;
    # NAME
    unless (defined $desc->[_NAME]) {
      if ($desc->[_SIGIL] ne '}') {
	croak "Invalid XHF: paren mismatch. '{' is closed by '$desc->[_SIGIL]'";
      }
      return \%result;
    }
    elsif ($desc->[_SIGIL] eq '-') {
      # Should treat two lines as one key value pair.
      unless (@$tokens) {
	croak "Invalid XHF hash:"
	  ." key '- $desc->[_VALUE]' doesn't have value!";
      }
      my $valdesc = shift @$tokens;
      my $value = do {
	if (my $sub = $OPN{$valdesc->[_SIGIL]}) {
	  $sub->($reader, $tokens, $valdesc);
	} elsif ($valdesc->[_SIGIL] eq '-') {
	  $valdesc->[_VALUE];
	} else {
	  croak "Invalid XHF hash value:"
	    . " key '$desc->[_VALUE]' has invalid sigil '$valdesc->[_SIGIL]'";
	}
      };
      $reader->add_value($result{$desc->[_VALUE]}, $value);
    } else {
      if (my $sub = $OPN{$desc->[_SIGIL]}) {
	# sigil がある時、value を無視して、良いのか?
	$desc->[_VALUE] = $sub->($reader, $tokens, $desc);
      }
      $reader->add_value($result{$desc->[_NAME]}, $desc->[_VALUE]);
    }
  }
  croak "Invalid XHF: Missing close '}'";
}

# '=' value
sub _undef {undef}
our %EXPR = (null => \&_undef, 'undef' => \&_undef);
sub organize_expr {
  (my MY $reader, my ($tokens, $first)) = @_;
  if ((my $val = $first->[_VALUE]) =~ s/^\#(\w+)\s*//) {
    my $sub = $EXPR{$1}
      or croak "Invalid XHF keyword: '= #$1'";
    $sub->($reader, $val, $tokens);
  } else {
    croak "Not yet implemented XHF token: '@$first'";
  }
}

sub add_value {
  my MY $reader = shift;
  unless (defined $_[0]) {
    $_[0] = $_[1];
  } elsif (ref $_[0] ne 'ARRAY') {
    $_[0] = [$_[0], $_[1]];
  } else {
    push @{$_[0]}, $_[1];
  }
}

use YATT::Lite::Breakpoint;
YATT::Lite::Breakpoint::break_load_xhf();

1;

=head1 NAME

YATT::Lite::XHF - Extended Header Fields format.

=head1 SYNOPSIS

  require YATT::Lite::XHF;

  # YATT::Lite::XHF->new(FH => \*STDIN);
  # YATT::Lite::XHF->new(filename => $filename);
  my $parser = YATT::Lite::XHF->new(string => <<'END');
  # Taken from http://docs.ansible.com/YAMLSyntax.html#yaml-basics
  name: Example Developer
  job: Developer
  skill: Elite
  employed: 1
  foods[
  - Apple
  - Orange
  - Strawberry
  - Mango
  ]
  languages{
  ruby: Elite
  python: Elite
  dotnet: Lame
  }

  name: hkoba
  languages{
  yatt: Elite?
  }
  END
  
  # read() returns one set of parsed result by one paragraph, separated by \n\n+.
  # In array context, you will get a flattened list of items in one paragraph.
  # (It may usually be a list of key-value pairs, but you can write other types)
  # In scalar context, you will get a hash struct.
  while (my %hash = $parser->read) {
    print Dumper(\%hash), "\n";
  }

  {
    # You can use YATT::Lite::XHF as mixin for read_file_xhf() and parse_xhf()
    package MyPackage {
      use YATT::Lite::XHF;
      ...
    }
    my %hash2 = MyPackage->read_file_xhf($filename);
  }

=head1 DESCRIPTION

Extended Header Fields (B<XHF>) format, which I'm defining here,
is a data format based on Email header
(and HTTP header), with extension to carry nested data structures.
With compared to L<YAML>, well known serialization format,
XHF is specifically designed to help B<writing test data> for unit tests.

For simplest cases, YAML and XHF may look fairly similar. For example,
a hash structure C<< {foo => 1, bar => 2} >> can be written in a same way
both in YAML and in XHF:

  foo: 1
  bar: 2

However, if you serialize a structure C<< {x => [1, 2, "3, 4"], y => 5} >>,
you will notice significant differences.

B<In XHF>, above will be written as:

  {
  x[
  - 1
  - 2
  - 3, 4
  ]
  y: 5
  }


In contrast B<in YAML>, same structure will be written as:

  ---
  x:
    - 1
    - 2
    - '3, 4'
  y: 5

The differences are:

=over 4

=item * XHF uses B<Parens> C< {} [] >. YAML uses B<indents>.

=item * XHF can represent C<3, 4> as is. YAML B<needs to escape> it like C<'3, 4'>.

=back

Here is a more dense example B<in XHF>:

  name: hkoba
  # (1) You can write a comment line here, starting with '#'.
  job: Programming Language Designer (self-described;-)
  skill: Random
  employed: 0
  foods[
  - Sushi
  # (2) here too.
  - Tonkatsu
  - Curry and Rice
  [
  - More nested elements
  ]
  ]
  favorites[
  # (3) here also.
  {
  title: Chaika - The Coffin Princess
  # (4) ditto.
  heroine: Chaika Trabant
  }
  {
  title: Witch Craft Works
  heroine: Ayaka Kagari
  # (5) You can use leading "-" for hash key/value too (so that include any chars)
  - Witch, Witch!
  - Tower and Workshop!
  }
  # (6) You can put NULL(undef) like below. (equal space sharp+keyword)
  = #null
  ]

Above will be loaded like following structure:

  $VAR1 = {
          'foods' => [
                     'Sushi',
                     'Tonkatsu',
                     'Curry and Rice',
                     [
                       'More nested element'
                     ]
                   ],
          'job' => 'Programming Language Designer (self-described;-)',
          'name' => 'hkoba',
          'employed' => '0',
          'skill' => 'Random',
          'favorites' => [
                         {
                           'heroine' => 'Chaika Trabant',
                           'title' => 'Chaika - The Coffin Princess'
                         },
                         {
                           'title' => 'Witch Craft Works',
                           'heroine' => 'Ayaka Kagari',
                           'Witch, Witch!' => 'Tower and Workshop!'
                         },
                         undef
                       ]
        };


Above will be written B<in YAML> like below (note: inline comments are omitted):

  ---
  employed: 0
  favorites:
    - heroine: Chaika Trabant
      title: 'Chaika - The Coffin Princess'
    - 'Witch, Witch!': Tower and Workshop!
      heroine: Ayaka Kagari
      title: Witch Craft Works
    - ~
  foods:
    - Sushi
    - Tonkatsu
    - Curry and Rice
    -
      - More nested element
  job: Programming Language Designer (self-described;-)
  name: hkoba
  skill: Random


This YAML example clearly shows how you need to escape strings quite randomly,
e.g. see above value of C<< $VAR1->{favorites}[0]{title} >>.
Also the key of C<< $VAR1->{favorites}[1]{'Witch, Witch!'} >> is nightmare.

I don't want to be bothered by this kind of escaping.
That's why I made XHF.

=head1 FORMAT SPECIFICATION
X<XHF-FORMAT>

XHF are parsed one paragraph by one.
Each paragraph can contain a set of C<xhf-item>s.
Every xhf-items start from a fresh newline, ends with a newline
and is basically formed like following:

  <name> <sigil> <sep> <body>

C<sigil> defines type of C<body>.
C<sep> is usually one of whitespace chars where C<space>, C<tab> and C<newline>
(newline is used for verbatim text).
But for block items(dict/array), only C<newline> is allowed.

Here is all kind of sigils:

=over 4

=item C<"name:"> then C<" "> or C<"\n">

C<":"> is for ordinally text with name. I<MUST> be prefixed by C<name>. C<sep> can be any of WS.

=item C<"-"> then C<" "> or C<"\n">

C<"-"> is for ordinally text without name. I<CANNOT> be prefixed by C<name>.

(Note: C<","> works same as C<"-">.)

=item C<"name{"> then C<"\n">

=item C<"{"> then C<"\n">

C<"{"> is for dictionary block (C< { %HASH } > container). I<Can> be prefixed by C<name>.

I<MUST> be closed by C<"}\n">. Number of elements I<MUST> be even.


=item C<"name["> then C<"\n">

=item C<"["> then C<"\n">

C<"["> is for array block. (C< [ @ARRAY ] > container). I<Can> be prefixed by C<name>.

I<MUST> be closed by C<"]\n">

=item C<"name="> then C<" "> or C<"\n">

=item C<"="> then C<" "> or C<"\n">

C<"="> is for special values. I<Can> be prefixed by C<name>.

Currently only C<#undef> and its synonym C<#null> is defined.

=item C<"#"> then C<" ">

C<"#"> is for embedded comment line. I<CANNOT> be prefixed by C<name>.

=back

=head2 XHF Syntax definition in extended BNF

Here is a syntax definition of XHF in extended BNF
(I<roughly> following L<ABNF|https://tools.ietf.org/html/rfc5234>.)

  xhf-block       = 1*xhf-item

  xhf-item        = field-pair / single-text
                   / dict-block / array-block / special-expr
                   / comment

  field-pair      = field-name  field-body

  field-name      = 1*NAME *field-subscript

  field-subscript = "[" *NAME "]"

  field-body      = ":" text-payload / dict-block / array-block / special-expr

  text-payload    = ( trimmed-text / verbatim-text ) NL

  trimmed-text    = SPTAB *( 1*NON-NL / NL SPTAB )

  verbatim-text   = NL    *( 1*NON-NL / NL SPTAB )

  single-text     = "-" text-payload

  dict-block      = "{" NL *xhf-item "}" NL

  array-block     = "[" NL *xhf-item "]" NL

  special-expr    = "=" SPTAB known-specials NL

  known-specials  = "#" ("null" / "undef")

  comment         = "#" SPTAB *NON-NL NL

  NL              = [\n]
  NON-NL          = [^\n]
  SPTAB           = [\ \t]
  NAME            = [0-9A-Za-z_.-/~!]

=head2 Some notes on current definition

=over 4

=item field-name, field-subscript

B<field-name> can contain C</>,  C<.>, C<~> and C<!>.
Former two are for file names (path separator and extension separator).
Later two (and B<field-subscript>) are incorporated just to help
writing test input/output data for L<YATT::Lite>,
so these can be arguable for general use.


=item trimmed-text vs verbatim-text

If B<field-name> is separated by C<": ">, its B<field-body> will be trimmed
their leading/trailing spaces/tabs.
This is useful to handle hand-written configuration files.

But for some software-testing purpose(e.g. templating engine!),
this space-trimming makes it impossible to write exact input/output data.

So, when B<field-sep> is NL, field-body is treated verbatim (=not trimmed).

=item LF vs CRLF

Currently, I'm not so rigid to reject the use of CRLF.
This ambiguity may harm use of XHF as a serialization format, however.

=item C<","> can be used in-place of C<"-">.

This feature also may be arguable for general use.

=item C<":"> without C<name> was valid, but is now deprecated.

Hmm, should I provide deprecation cycle?

=item line-continuation is valid.

Although line-continuation is obsoleted in email headers and http headers,
line-continuation will be kept valid in XHF spec. This is my preference.

=back
