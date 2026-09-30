package YATT::Lite::PageConsts;
use strict;
use warnings qw(FATAL all NONFATAL misc);

use MOP4Import::Base::CLI_JSON -as_base
  , [fields => qw(_pages _file _line)];

use File::Spec;
use List::Util qw(first);

use YATT::Lite::Util qw(globref);
require YATT::Lite::MFields;

# The instance registered by define_pages. The receiver can be a class name,
# or an object created elsewhere (eg. by cli_run) which has no pages.
sub _registered {
  my ($self_or_class) = @_;
  if (ref $self_or_class and $self_or_class->{_pages}) {
    $self_or_class;
  } else {
    $self_or_class->instance;
  }
}

sub define_pages :MetaOnly {
  my ($pack, @pairs) = @_;
  my ($callpack, $file, $line) = caller;
  my MY $self = $pack->new(pages => \@pairs);
  # Remember where the pages are defined, for locate_const.
  $self->{_file} = File::Spec->rel2abs($file);
  $self->{_line} = $line;
  $self->register_into($callpack);
  $self;
}

sub onconfigure_pages {
  (my MY $self, my $pairs) = @_;
  my @pairs = @$pairs;
  while (my ($page, $vars) = splice @pairs, 0, 2) {
    $self->{_pages}{$page} = $vars;
  }
  $self;
}

sub register_into :MetaOnly {
  (my MY $self, my $pkg) = @_;
  YATT::Lite::MFields->add_isa_to($pkg, MY);
  *{globref($pkg, 'instance')} = sub { $self };
  *{globref($pkg, 'import')} = sub {
    my $callpack = caller;
    $self->inject_into($callpack, @_[1..$#_]);
  };
}

sub inject_into {
  (my MY $self, my ($destpkg, $page, %opts)) = @_;
  my $failok = delete $opts{missing_ok};
  if (keys %opts) {
    Carp::croak "Unknown options: ".join(", ", sort keys %opts);
  }
  $page ||= do {
    if (my $sub = $self->can("page_name")) {
      $sub->($self)
    }
  };
  unless (defined $page and $page ne '') {
    Carp::croak("page name is not specified");
  }
  my $vars = $self->find_consts($page)
    or $failok or Carp::croak("No such page: $page");

  # print STDERR "# injecting vars (@{[keys %$vars]})in $page\n"
  #   , YATT::Lite::Util::terse_dump($self);

  foreach my $name (keys %$vars) {
    my $value = $vars->{$name};
    if ($failok and ref $value and UNIVERSAL::can($value, 'varname')
        and UNIVERSAL::can($value, 'value')) {
      # For $failok case (== from yatt)
      my $glob = globref($destpkg, $value->varname($name));
      (*$glob) = map {ref $_ ? $_ : \ $_} $value->value;
    } else {
      my $glob = globref($destpkg, $name);
      *$glob = do {
        if (not ref $value or ref $value eq 'ARRAY' or ref $value eq 'HASH') {
          \ $value
        } else {
          $value;
        }
      };
      # 関数の場合は、関数だけでなく、スカラ変数にも入れておく。
      *$glob = \ $value if ref $value eq 'CODE';
    }
  }
}


*find_vars = *find_consts;
*find_vars = *find_consts;
sub find_consts :Doc(Find constant(s) for specified PAGE/NAME) {
  my MY $self = shift->_registered;
  my ($page, $varname) = @_;
  my $page_vars = $self->{_pages}{$page}
    or return;
  if (not defined $varname) {
    $page_vars;
  } else {
    $page_vars->{$varname};
  }
}

sub const_type :Doc(Type of yatt variable for the constant VALUE) {
  my ($self_or_class, $value) = @_;
  if (not ref $value) {
    'text';
  } elsif (ref $value eq 'ARRAY') {
    'list'
  } elsif (ref $value eq 'CODE') {
    'code'
  } elsif (UNIVERSAL::can($value, 'varname')
           and UNIVERSAL::can($value, 'value')) {
    'html';
  } else {
    'scalar';
  }
}

# Best effort. Looks for "NAME =>" in the block of PAGE first,
# then anywhere in the file (for common values), then falls back to
# the line of define_pages.
sub locate_const :Doc(Locate the definition of constant NAME for PAGE as file and line) {
  my MY $self = shift->_registered;
  my ($page, $name) = @_;
  my $page_vars = $self->{_pages}{$page}
    or return;
  exists $page_vars->{$name}
    or return;
  my $file = $self->{_file}
    or return;
  open my $fh, '<', $file
    or return ($file, $self->{_line});
  my @lines = <$fh>;

  my $key_re = sub {
    my ($key, $follow) = @_;
    qr/(?:^|[\s,{(])(['"]?)\Q$key\E\1\s*$follow/;
  };
  my $page_re = $key_re->($page, qr/(?:=>|\}\s*=)/);
  my @other_page_re = map {$key_re->($_, qr/(?:=>|\}\s*=)/)}
    grep {$_ ne $page} keys %{$self->{_pages}};
  my $const_re = $key_re->($name, qr/=>/);

  if (defined(my $start = first {$lines[$_] =~ $page_re} 0 .. $#lines)) {
    foreach my $i ($start .. $#lines) {
      last if $i > $start and grep {$lines[$i] =~ $_} @other_page_re;
      return ($file, $i+1) if $lines[$i] =~ $const_re;
    }
  }
  if (defined(my $i = first {$lines[$_] =~ $const_re} 0 .. $#lines)) {
    return ($file, $i+1);
  }
  ($file, $self->{_line});
}

sub as_html {
  my ($text) = @_;
  bless \ $text, 'YATT::Lite::PageConsts::html';
}

package
  YATT::Lite::PageConsts::html;
use overload '""' => 'value';
sub varname {shift; 'html_'. shift}
sub value {${shift()}}


1;
