package YATT::Lite::XHF; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use Carp;

use base qw(YATT::Lite::Object);
use fields qw(cf_FH cf_filename cf_string cf_tokens
	      fh_configured
	      cf_encoding cf_crlf
	      cf_nocr cf_subst
	      cf_skip_comment cf_bytes);

use Exporter qw(import);
our @EXPORT = qw(read_file_xhf);
our @EXPORT_OK = (@EXPORT, qw(parse_xhf $cc_name));

=head1 NAME

YATT::Lite::XHF - Extended Header Fields format.

=cut

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
		    $self->organize($self->tokenize);
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

    # Comment fields are ignored.
    $ncomments++, next if $sigil eq "#";

    if ($NAME_LESS{$sigil} and $name ne '') {
      croak "Invalid XHF token('$sigil' should not have name '$name')"
    }

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
  $lineno += tr|\n|| for @$tokens[0 .. $pos];
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
