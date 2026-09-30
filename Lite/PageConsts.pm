package YATT::Lite::PageConsts;
use strict;
use warnings qw(FATAL all NONFATAL misc);

use MOP4Import::Base::CLI_JSON -as_base
  , [fields => qw(_pages)];

use YATT::Lite::Util qw(globref);

sub define_pages :MetaOnly {
  my ($pack, @pairs) = @_;
  my $callpack = caller;
  $pack->new(pages => \@pairs)->register_into($callpack);
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
  my MY $self = ref $_[0] ? shift : shift->instance();
  my ($page, $varname) = @_;
  my $page_vars = $self->{_pages}{$page}
    or return;
  if (not defined $varname) {
    $page_vars;
  } else {
    $page_vars->{$varname};
  }
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
