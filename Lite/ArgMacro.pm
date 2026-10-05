package YATT::Lite::ArgMacro;
use strict;
use warnings qw(FATAL all NONFATAL misc);
use Carp;

sub MY () {__PACKAGE__}

use YATT::Lite::Util qw(globref define_const);
use YATT::Lite::Constants;

#
# package MyApp::ArgMacro::Enum;
# use YATT::Lite::ArgMacro
#   out => [qw(list=list)],
#   in  => ['first=value/0', 'last=value!'];
#
# sub on_expand {
#   (my MY $macro, my CGen $cgen, my Args $args, my Vars $vars) = @_;
#   my Result $result = {};
#   ...
#   $result;
# }
#
sub import {
  my ($pack, %opts) = @_;
  # Subclasses (ie. argmacro modules) inherit this import. Using them
  # must not redefine anything.
  return if $pack ne MY;
  my $callpack = caller;
  MY->declare_into($callpack, %opts);
}

sub declare_into {
  my ($pack, $destpkg, %opts) = @_;

  my $out = delete $opts{out}
    or croak "ArgMacro requires 'out' (list of output args)";
  my $in = delete $opts{in} // [];
  my $refer = delete $opts{refer} // [];
  if (keys %opts) {
    croak "Unknown options for ArgMacro: ".join(", ", sort keys %opts);
  }

  # refer は widget 側で宣言する引数を参照するだけなので、名前のみ
  foreach my $name (@$refer) {
    croak "ArgMacro refer accepts only arg names: $name"
      unless $name =~ /^\w+\z/;
  }

  my $spec = +{
    out => [map {$pack->parse_arg_spec($_)} @$out],
    in  => [map {$pack->parse_arg_spec($_)} @$in],
    refer => [@$refer],
  };
  croak "ArgMacro requires at least one output arg" unless @{$spec->{out}};

  my %seen;
  foreach my $name ((map {$_->[0]} @{$spec->{out}}, @{$spec->{in}})
                    , @{$spec->{refer}}) {
    croak "Duplicate arg name in ArgMacro: $name" if $seen{$name}++;
  }

  require YATT::Lite::MFields;
  YATT::Lite::MFields->add_isa_to($destpkg, MY);

  my @in_names = ((map {$_->[0]} @{$spec->{in}}), @{$spec->{refer}});
  my @out_names = map {$_->[0]} @{$spec->{out}};

  my %types = (
    MY     => $destpkg,
    Args   => $pack->define_record_class("${destpkg}::Args", @in_names),
    Vars   => $pack->define_record_class("${destpkg}::Vars", @in_names),
    Result => $pack->define_record_class("${destpkg}::Result", @out_names),
    CGen   => 'YATT::Lite::CGen::Perl',
  );
  foreach my $name (sort keys %types) {
    my $glob = globref($destpkg, $name);
    next if *{$glob}{CODE};
    define_const($glob, $types{$name});
  }

  define_const(globref($destpkg, 'macro_spec'), $spec);

  $destpkg;
}

# "name", "name=type", "name=type/default" ... (same as argument spec
# of <!yatt:argmacro>). Returns [name, spec_or_undef].
sub parse_arg_spec {
  my ($pack, $item) = @_;
  my ($name, $desc) = ref $item ? @$item : split /=/, $item, 2;
  unless (defined $name and $name =~ /^[[:alpha:]_]\w*\z/) {
    croak "Invalid arg name in ArgMacro: ".($name // '(undef)');
  }
  if (defined $desc) {
    my ($type) = split m{[|/?!:]}, $desc, 2;
    if (defined $type and $type =~ /^(?:code|delegate)\z/
        or $desc =~ /^\[/) {
      croak "ArgMacro arg type '$desc' is not supported in modules: $name";
    }
  }
  [$name, $desc];
}

# Defines a class whose %FIELDS is exactly @names. This enables compile time
# checking of field names on typed lexicals: my Result $r; $r->{typo} dies.
# Idempotent, so templates can be recompiled.
sub define_record_class {
  my ($pack, $class, @names) = @_;
  my $glob = globref($class, 'FIELDS');
  %{*$glob} = map {$_ => 1} @names;
  my $new = globref($class, 'new');
  *$new = sub { require fields; fields::new(ref $_[0] || $_[0]) }
    unless *{$new}{CODE};
  $class;
}

#========================================
# Bridge to YATT::Lite::Core::ArgMacro

sub as_argmacro_part {
  my ($class, $parser, $name, $ns) = @_;

  my $spec = $class->macro_spec;
  $ns //= $parser->primary_ns;

  # Default values (eg. value/0) are parsed as text with entities,
  # which needs position info of the parser.
  local $parser->{_startpos} = 0;
  local $parser->{_curpos} = 0;
  local $parser->{_startln} = 1;
  local $parser->{_endln} = 1;

  my $argmacro = $parser->ArgMacro->new(
    name => $name, kind => 'argmacro', decl => 'argmacro',
    namespace => $ns,
    output_args => [map {$class->_mk_arg_node(@$_)} @{$spec->{out}}],
    refer_names => [@{$spec->{refer}}],
  );

  $parser->add_args($argmacro, map {$class->_mk_arg_node(@$_)} @{$spec->{in}});

  $argmacro->{_on_expand} = sub {
    my ($cgen, $args, $vars, $macro) = @_;
    my $result = $class->on_expand($cgen, $args, $vars, $macro);
    unless (ref $result eq 'HASH' or UNIVERSAL::isa($result, 'HASH')) {
      croak "$class->on_expand must return a hash";
    }
    $result;
  };

  require YATT::Lite::CGen::ArgMacro;
  $argmacro->{_on_declare}
    = YATT::Lite::CGen::ArgMacro->make_on_declare($argmacro);

  $argmacro;
}

sub _mk_arg_node {
  my ($class, $name, $desc) = @_;
  my $node = [];
  if (defined $desc) {
    $node->[NODE_TYPE] = TYPE_ATT_TEXT;
    $node->[NODE_BODY] = $desc;
  } else {
    $node->[NODE_TYPE] = TYPE_ATT_NAMEONLY;
  }
  $node->[NODE_PATH] = $name;
  $node;
}

sub on_expand {
  my ($class) = @_;
  croak "$class must implement on_expand";
}

1;
