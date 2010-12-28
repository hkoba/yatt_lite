package YATT::Lite::XHF; sub MY () {__PACKAGE__}
use strict;
use warnings FATAL => qw(all);
use Carp;

use base qw(YATT::Lite::Object);
use fields qw(cf_FH cf_filename cf_string cf_tokens
	      cf_skip_comment cf_binary);

use Exporter qw(import);
our @EXPORT = qw(read_file_xhf);
our @EXPORT_OK = (@EXPORT, qw(parse_xhf));

use Encode qw(encode);

=head1 NAME

YATT::Lite::XHF - Extended Header Fields format.

=cut

use YATT::Lite::Util;
use YATT::Lite::Util::Enum _ => [qw(NAME SIGIL VALUE)];

our $cc_name  = qr{\w|[\.\-/~!]};
our $cc_sigil = qr{[:\#,\-\[\]\{\}]};
our $cc_tabsp = qr{[\ \t]};

our %OPN = ('[' => \&organize_array, '{' => \&organize_hash);

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
  $self->{cf_filename} = $fn;
  $self;
}

sub configure_encoding {
  (my MY $self, my $enc) = @_;
  unless ($self->{cf_FH}) {
    croak "Can't set encoding for empty FH!";
  }
  binmode $self->{cf_FH}, ":encoding($enc)";
  $self;
}

sub configure_string {
  my MY $self = shift;
  ($self->{cf_string}) = @_;
  open $self->{cf_FH}, '<', \ $self->{cf_string}
    or croak "Can't create string stream: $!";
  $self;
}

# XXX: Should be renamed to read_all?
sub read {
  my MY $self = shift;
  my ($keys, $values) = $self->cf_bindings(@_);
  local @{$self}{@$keys} = @$values; # XXX: configure_ZZZ hook is not applied.
  local $/ = "";
  my $fh = $$self{cf_FH};
  my @tokens;
 LOOP: {
    do {
      defined (my $para = <$fh>) or last LOOP;
      $para = untaint_unless_tainted
	($self->{cf_filename} // $self->{cf_string}
	 , $para);
      $para = encode(utf8 => $para) if $self->{cf_binary};
      @tokens = $self->tokenize($para);
    } until (not $self->{cf_skip_comment} or @tokens);
  }
  $self->organize(@tokens);
}

sub tokenize {
  my MY $reader = shift;
  $_[0] =~ s{\n+$}{\n}s;
  my ($ncomments, @result);
  foreach my $token (split /(?<=\n)(?=[^\ \t])/, $_[0]) {
    if ($token =~ s{^(?:\#[^\n]*(?:\n|$))+}{}) {
      $ncomments++;
      next if $token eq '';
    }

    unless ($token =~ s{^($cc_name*(?:\[\])?) ($cc_sigil) (?:($cc_tabsp)|(\n|$))}{}x) {
      croak "Invalid XHF token: $token in $_[0]"
    }
    my ($name, $sigil, $tabsp, $eol) = ($1, $2, $3, $4);

    # Comment fields are ignored.
    $ncomments++, next if $sigil eq "#";

    # Line continuation.
    $token =~ s/\n[\ \t]/\n/g;

    unless (defined $eol) {
      # Values are trimmed unless $eol
      $token =~ s/^\s+|\s+$//gs;
    } elsif ($sigil eq '{') {
      # Deny:  name{ foo
      # Allow: name[ foo
      croak "Invalid XHF token(container with value): "
	. join("", grep {defined $_} $name, $sigil, $tabsp, $token)
	  if $token ne "";
    } else {
      # Trim leading space for $tabsp eq "\n".
      $token =~ s/^[\ \t]//;
    }
    push @result, [$name, $sigil, $token];
  }

  # Comment only paragraph should return nothing.
  return if $ncomments && !@result;

  wantarray ? @result : \@result;
}

sub organize {
  my MY $reader = shift;
  my @result;
  while (@_) {
    my $desc = shift;
    push @result, $desc->[_NAME];
    if (my $sub = $OPN{$desc->[_SIGIL]}) {
      # sigil がある時、value を無視して、良いのか?
      push @result, $sub->($reader, \@_);
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

sub organize_array {
  (my MY $reader, my ($tokens, $first)) = @_;
  my @result;
  push @result, $first->[_VALUE] if defined $first and $first->[_VALUE] ne '';
  while (@$tokens) {
    my $desc = shift @$tokens;
    if ($desc->[_NAME] ne '') {
      push @result, $desc->[_NAME];
    }
    last if $desc->[_SIGIL] eq ']';
    if (my $sub = $OPN{$desc->[_SIGIL]}) {
      # sigil がある時、value があったらどうするかは、子供次第。
      push @result, $sub->($reader, $tokens, $desc);
    } else {
      push @result, $desc->[_VALUE];
    }
  }
  \@result;
}

sub organize_hash {
  (my MY $reader, my ($tokens, $first)) = @_;
  die "Invalid XHF hash block beginning! ". join("", @$first)
    if defined $first and $first->[_VALUE] ne '';
  my %result;
  while (@$tokens) {
    my $desc = shift @$tokens;
    if (my $sub = $OPN{$desc->[_SIGIL]}) {
      # sigil がある時、value を無視して、良いのか?
      $desc->[_VALUE] = $sub->($reader, $tokens);
    }
    last if $desc->[_SIGIL] eq '}';
    $reader->add_value($result{$desc->[_NAME]}, $desc->[_VALUE]);
  }
  \%result;
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
