#!/bin/zsh

set -e
setopt extendedglob

function die { echo 1>&2 $*; exit 1 }

cd $0:h:h:h:h
[[ -d runyatt.lib ]] || die "Can't find runyatt.lib!"
[[ -r runyatt.lib/YATT/Lite.pm ]] || die "Can't find YATT::Lite!"
origdir=$PWD

#version=$(perl -Irunyatt.lib -MYATT::Lite -le 'print YATT::Lite->VERSION')
version=$(
    perl -Irunyatt.lib -MExtUtils::MakeMaker -le \
	'print MM->parse_version(shift)' runyatt.lib/YATT/Lite.pm
)

main=(
    -name _build -prune
    -o -name cover_db -prune
    -o -name .git -prune
    -o -name \*.bak -prune
    -o -name \*~ -prune
)

tmpdir=/tmp/_build_yatt_lite$$
mkdir -p $tmpdir

build=$tmpdir/YATT-Lite-$version
{
    git clone $PWD $tmpdir/yatt_lite

    cd $tmpdir/yatt_lite

    [[ -r MANIFEST ]] || echo MANIFEST > MANIFEST
    print -l *~*.bak(.) > MANIFEST
    find *(/) $main -o -print >> MANIFEST

    sort MANIFEST > $origdir/MANIFEST

    cpio -pd $build < $origdir/MANIFEST
    sed -i "s/^Version: .*/Version: $version/" \
	$build/vendor/redhat/perl-YATT-Lite.spec

    tar zcvf $build.tar.gz -C $tmpdir YATT-Lite-$version

    if [[ -d ~/rpmbuild/SOURCES ]]; then
	mv -vu $build.tar.gz ~/rpmbuild/SOURCES
    fi
} always {
    rm -rf $tmpdir
}
