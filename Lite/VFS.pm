package YATT::Lite::VFS;
use strict;
use warnings FATAL => qw(all);
use Exporter qw(import);
use Scalar::Util qw(weaken);
use Carp;

#========================================
# VFS 層. vfs_file (Template) のダミー実装を含む。
#========================================
{
  sub MY () {__PACKAGE__}
  use YATT::Lite::Types
    ([Item => -fields => [qw(cf_name cf_public)]
      , [Folder => -fields => [qw(Item cf_path cf_parent cf_base
				  cf_entns)]
	 , -eval => q{use YATT::Lite::Util qw(cached_in);}
	 , [File => -fields => [qw(partlist cf_string cf_overlay)]
	    , -alias => 'vfs_file']
	 , [Dir  => -fields => [qw(cf_encoding)]
	    , -alias => 'vfs_dir']]]);

  sub YATT::Lite::VFS::Item::after_create {}
  sub YATT::Lite::VFS::Folder::configure_parent {
    my MY $self = shift;
    # 循環参照対策
    # XXX: Item に移すべきかもしれない。そうすれば、 Widget->parent が引ける。
    weaken($self->{cf_parent} = shift);
  }

  package YATT::Lite::VFS; BEGIN {$INC{"YATT/Lite/VFS.pm"} = 1}
  sub VFS () {__PACKAGE__}
  use base qw(YATT::Lite::Object);
  use fields qw(cf_ext_private cf_ext_public cf_cache cf_no_auto_create
		cf_facade cf_base
		cf_entns
		root extdict n_creates n_updates cf_mark
		pkg2folder);
  use YATT::Lite::Util qw(lexpand rootname);
  sub default_ext_public {'yatt'}
  sub default_ext_private {'ytmpl'}
  sub new {
    my ($class, $spec) = splice @_, 0, 2;
    (my VFS $vfs, my @task) = $class->SUPER::just_new(@_);
    foreach my $desc ([1, ($vfs->{cf_ext_public}
				  ||= $vfs->default_ext_public)]
		      , [0, ($vfs->{cf_ext_private}
			     ||= $vfs->default_ext_private)]) {
      my ($value, @ext) = @$desc;
      $vfs->{extdict}{$_} = $value for @ext;
    }
    $vfs->root_create(linsert($spec, 2, $vfs->cf_delegate(qw(entns))))
      if $spec;
    $$_[0]->($vfs, $$_[1]) for @task;
    $vfs->after_new;
    $vfs;
  }
  sub after_new {
    my MY $self = shift;
    confess __PACKAGE__ . ": facade is empty!" unless $self->{cf_facade};
    weaken($self->{cf_facade});
  }
  sub error {
    my MY $self = shift;
    $self->{cf_facade}->error(@_);
  }
  #========================================
  sub find_file {
    (my VFS $vfs, my $filename) = @_;
    # XXX: 拡張子をどうしたい？
    my ($name) = $filename =~ m{^(\w+)}
      or croak "Can't extract part name from filename '$filename'";
    $vfs->{root}->lookup($vfs, $name);
  }
  #========================================
  sub find_part {
    my VFS $vfs = shift;
    $vfs->{root}->lookup($vfs, @_);
  }
  sub find_part_from {
    (my VFS $vfs, my $from) = splice @_, 0, 2;
    my Item $item = $from->lookup($vfs, @_);
    if ($item and $item->isa($vfs->Folder)) {
      (my Folder $folder = $item)->{Item}{''}
    } else {
      $item;
    }
  }

  # To limit call of refresh atmost 1, use this.
  sub reset_refresh_mark {
    (my VFS $vfs) = shift;
    $vfs->{cf_mark} = @_ ? shift : {};
  }

  use Scalar::Util qw(refaddr);
  sub YATT::Lite::VFS::File::lookup {
    (my vfs_file $file, my VFS $vfs, my $name) = splice @_, 0, 3;
    unless (@_) {
      # ファイルの中には、深さ 1 の name しか無いはずだから。
      # mtime, refresh
      $file->refresh($vfs) unless $vfs->{cf_mark}{refaddr($file)}++;
      my Item $item = $file->{Item}{$name};
      return $item if $item;
    }
    # 深さが 2 以上の (name, @_) については、継承先から探す。
    $file->lookup_base($vfs, $name, @_);
  }
  sub YATT::Lite::VFS::Dir::lookup {
    (my vfs_dir $dir, my VFS $vfs, my $name) = splice @_, 0, 3;
    if (my Item $item = $dir->cached_in
	($dir->{Item} //= {}, $name, $vfs, $vfs->{cf_mark})) {
      if (not ref $item and not $vfs->{cf_no_auto_create}) {
	$item = $dir->{Item}{$name} = $vfs->create
	  (data => $item, parent => $dir, name => $name);
      }
      return $item unless @_;
      $item = $item->lookup($vfs, @_);
      return $item if $item;
    }
    $dir->lookup_base($vfs, $name, @_);
  }
  sub YATT::Lite::VFS::Folder::lookup_base {
    (my Folder $item, my VFS $vfs, my $name) = splice @_, 0, 3;
    foreach my $super ($item->list_base) {
      my $ans = $super->lookup($vfs, $name, @_) or next;
      return $ans;
    }
    undef;
  }
  sub YATT::Lite::VFS::Folder::list_base {
    my Folder $folder = shift; @{$folder->{cf_base} ||= []}
  }
  sub YATT::Lite::VFS::File::list_base {
    my vfs_file $file = shift;
    # $dir/$file.yatt inherits...
    grep(defined $_
	 , $file->YATT::Lite::VFS::Folder::list_base
	 # $dir and its base
	 , map((defined $_ ? ($_, $_->list_base) : ())
	       , $file->{cf_parent})
	 # and then, $dir/$file.ytmpl
	 , $file->{cf_overlay});
  }
  #----------------------------------------
  sub YATT::Lite::VFS::Dir::load {
    (my vfs_dir $in, my VFS $vfs, my $partName) = @_;
    return unless defined $in->{cf_path};
    my $vfsname = "$in->{cf_path}/$partName";
    my @opt = (name => $partName, parent => $in);
    if (my $fn = $vfs->find_ext($vfsname, $vfs->{cf_ext_public})) {
      $vfs->create(file => $fn, @opt, public => 1);
    } elsif ($fn = $vfs->find_ext($vfsname, $vfs->{cf_ext_private})) {
      # dir の場合、 new_tmplpkg では？
      my $kind = -d $fn ? 'dir' : 'file';
      $vfs->create($kind => $fn, @opt);
    } else {
      undef;
    }
  }
  sub find_ext {
    (my VFS $vfs, my ($vfsname, $spec)) = @_;
    foreach my $ext (!defined $spec ? () : ref $spec ? @$spec : $spec) {
      my $fn = "$vfsname.$ext";
      return $fn if -e $fn;
    }
  }
  #========================================
  # 実験用、ダミーのパーサー
  sub YATT::Lite::VFS::File::reset {
    (my File $file) = @_;
    undef $file->{partlist};
    undef $file->{Item};
    undef $file->{cf_string};
    undef $file->{cf_base};
  }
  sub YATT::Lite::VFS::Dir::refresh {}
  sub YATT::Lite::VFS::File::refresh {
    (my vfs_file $file, my VFS $vfs) = @_;
    return unless $$file{cf_path} || $$file{cf_string};
    # XXX: mtime!
    $vfs->{n_updates}++;
    my @part = do {
      local $/; split /^!\s*(\w+)\s+(\S+)[^\n]*?\n/m, do {
	if ($$file{cf_path}) {
	  open my $fh, '<', $$file{cf_path}
	    or die "Can't open '$$file{cf_path}': $!";
	  scalar <$fh>
	} else {
	  $$file{cf_string};
	}
      };
    };
    $file->add_widget('', shift @part);
    while (my ($kind, $name, $part) = splice @part, 0, 3) {
      if (defined $kind and my $sub = $file->can("declare_$kind")) {
	$sub->($file, $name, $vfs, $part);
      } else {
	$file->can("add_$kind")->($file, $name, $part);
      }
    }
  }
  #========================================
  sub add_to {
    (my VFS $vfs, my ($path, $data)) = @_;
    my @path = ref $path ? @$path : $path;
    my $lastName = pop @path;
    my Folder $folder = $vfs->{root};
    while (@path) {
      my $name = shift @path;
      $folder = $folder->{Item}{$name} ||= $vfs->create
	(data => {}, name => $name, parent => $folder);
    }
    # XXX: path を足すと、memory 動作の時に困る
    $folder->{Item}{$lastName} = $vfs->create
	(data => $data, name => $lastName, parent => $folder);
  }
  #========================================
  # special hook for root creation.
  sub root_create {
    (my VFS $vfs, my ($kind, $primary, %rest)) = @_;
    $rest{entns} //= $vfs->{cf_entns};
    $vfs->{root} = $vfs->create($kind, $primary, %rest);
  }
  sub create {
    (my VFS $vfs, my ($kind, $primary, %rest)) = @_;
    # XXX: $vfs は className の時も有る。
    if (my $sub = $vfs->can("create_$kind")) {
      $vfs->fixup_created($sub->($vfs, $primary, %rest));
    } else {
      $vfs->{cf_cache}{$primary} ||= do {
	# XXX: Really??
	$rest{entns} //= $vfs->{cf_entns};
	$vfs->fixup_created
	  ($vfs->can("vfs_$kind")->()->new(%rest, path => $primary));
      };
    }
  }
  sub fixup_created {
    (my VFS $vfs, my Folder $folder) = @_;
    # create の直後、 after_create より前に、mark を打つ。そうしないと、 delegate で困る。
    if (ref $vfs) {
      $vfs->{n_creates}++;
      $vfs->{cf_mark}{refaddr($folder)}++;
    }
    if (my Folder $parent = $folder->{cf_parent}) {
      # XXX: そうか、 package 名を作るだけじゃなくて、親子関係を設定しないと。
      # XXX: private なら、 new_tmplpkg では？
      if (defined $parent->{cf_entns}) {
	$folder->{cf_entns} = join '::'
	  , $parent->{cf_entns}, $folder->{cf_name};
	$vfs->{pkg2folder}{$folder->{cf_entns}} = $folder;
      }
    }
    $folder->after_create($vfs);
    $folder;
  }
  sub create_data {
    (my VFS $vfs, my ($primary)) = splice @_, 0, 2;
    if (ref $primary) {
      # 直接 Folder slot にデータを。
      my vfs_dir $item = $vfs->vfs_dir->new(@_);
      $item->{Item} = $primary;
      $item;
    } else {
      $vfs->vfs_file->new(public => 1, @_, string => $primary);
    }
  }
  sub YATT::Lite::VFS::Dir::after_create {
    (my vfs_dir $dir, my VFS $vfs) = @_;
    foreach my Folder $desc (@{$dir->{cf_base}}) {
      $desc = $vfs->create(@$desc) if ref $desc eq 'ARRAY';
      # parent がある == parent から指されている。なので、 weaken する必要が有る。
      weaken($desc) if $desc->{cf_parent};
    }
    # $dir->refresh($vfs);
    $dir;
  }
  # file 系は create 時に必ず refresh. refresh は decl のみ parse.
  sub YATT::Lite::VFS::File::after_create {
    (my vfs_file $file, my VFS $vfs) = @_;
    $file->refresh_overlay($vfs);
    $file->refresh($vfs);
  }
  sub YATT::Lite::VFS::File::refresh_overlay {
    (my vfs_file $file, my VFS $vfs) = @_;
    return if $file->{cf_overlay};
    return unless $file->{cf_path};
    my $dir = join '.', rootname($file->{cf_path}), $vfs->{cf_ext_private};
    return unless -d $dir;
    $file->{cf_overlay} = $vfs->create
      (dir => $dir, parent => $file->{cf_parent});
  }
  #----------------------------------------
  sub YATT::Lite::VFS::File::declare_base {
    (my vfs_file $file, my ($spec), my VFS $vfs, my $part) = @_;
    my ($kind, $path) = split /=/, $spec, 2;
    # XXX: 物理 path だと困るよね？ findINC 的な処理が欲しい
    # XXX: 帰属ディレクトリより強くするため、先頭に。でも、不満。
    unshift @{$file->{cf_base}}, $vfs->create($kind => $path);
    weaken($file->{cf_base}[0]);
    $file->{Item}{''} .= $part;
  }
  sub YATT::Lite::VFS::File::add_widget {
    (my vfs_file $file, my ($name, $part)) = @_;
    push @{$file->{partlist}}, $file->{Item}{$name} = $part;
  }

  sub linsert {
    my @ls = @{shift()};
    splice @ls, shift, 0, @_;
    wantarray ? @ls : \@ls;
  }
}

use YATT::Lite::Breakpoint;
YATT::Lite::Breakpoint::break_load_vfs();

1;
