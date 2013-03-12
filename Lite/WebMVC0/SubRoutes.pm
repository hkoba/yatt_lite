package YATT::Lite::WebMVC0::SubRoutes;
use strict;
use warnings FATAL => qw/all/;
use Carp;

use YATT::Lite::Types ([Route =>
			-fields => [qw/pattern_re
				       cf_name
				       cf_pattern cf_item cf_params/]]);

sub new {
  bless [], shift;
}

sub prepend {
  my $self = shift; unshift @$self, @_; $self;
}

sub append {
  my $self = shift; push @$self, @_; $self;
}

sub match {
  my $self = shift;
  foreach my Route $r (@$self) {
    my ($slash, @match) = $_[0] =~ $r->{pattern_re}
      or next;
    return ($r->{cf_item} // $r->{cf_name}, $r->{cf_params}, \@match);
  }
  return;
}

sub create {
  my ($self, $spec, $item) = @_;
  my ($name, $pat) = ref $spec eq 'ARRAY' ? @$spec : (undef, $spec);
  my Route $r = $self->Route->new;
  $r->{cf_name}    = $name;
  $r->{cf_pattern} = $pat;
  $r->{cf_item}    = $item;
  ($r->{pattern_re}, my @params) = $self->parse_pattern($pat);
  $r->{cf_params}  = \ @params;
  $r;
}

sub parse_pattern {
  my ($self, $pat) = @_;

  my (@pat, @params);
  unless ($pat =~ m!^/!g) {
    croak "Unsupported url pattern! $pat";
  }

  my $last = 0;
  while ($pat =~ m!\G(?: ([^:{}]+)               # other text
		   |    (?<=/) \:(\w+(?:\:\w+)*) # :var:type
		   | \{(\w+                      # {var:...}
		       (?:
			 : (?: (?:\w+(?:\:\w+)*) # :type
			 | (?: [^{}]+            # regexp(other than {})
			   | (\{                 # re-qualifier(nestable)
			       (?: (?> [^{}]+)
			       | (?-1)
			       )*
			       \})
			   )+
			 )
		       )?
		     )
		     \}
		   )
		  !xg) {
    if (not @pat) {
      push @pat, "(/)"; # To make sure first slash is captured.
    }
    if ($1) {
      push @pat, quotemeta($1);
    } elsif (my $var_type = $2 // $3) {
      my ($name, $type_or_pat) = split /:/, $var_type, 2;
      my @type;
      push @pat, do {
	if (not $type_or_pat
	    or ($type_or_pat =~ /^\w+$/ and do {push @type, $&})) {
	  q!([^/]+)!
	} else {
	  "($type_or_pat)";
	}
      };
      push @params, [$name, @type];
    } else {
      last;
    }
  } continue {
    $last = pos($pat);
  }
  push @pat, quotemeta(substr($pat, $last)) if $last < length $pat;
  my $all = join "", @pat;

  (qr{^$all$}x, @params);
}

1;
