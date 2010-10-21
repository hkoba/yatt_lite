#!/bin/zsh

set -e

function die { echo 1>&2 $*; exit 1 }

cd $0:h:h:h:h
[[ -d runyatt.lib ]] || die "Can't find runyatt.lib!"
[[ -r runyatt.lib/YATT/Lite.pm ]] || die "Can't find YATT::Lite!"

#version=$(perl -Irunyatt.lib -MYATT::Lite -le 'print YATT::Lite->VERSION')
version=$(
    perl -Irunyatt.lib -MExtUtils::MakeMaker -le \
	'print MM->parse_version(shift)' runyatt.lib/YATT/Lite.pm
)

clean=(
    runyatt.lib/t/vfs.d
)

main=(
    -name _build -prune
    -o -name cover_db -prune
    -o -name .git -prune
)

samples=(
    -type l -prune
    -o -name .htaccess -prune
    -o -name \*.cgi -prune
)

rm -rf $clean
mkdir -p _build
rm -rf _build/YATT-Lite-$version

echo MANIFEST > MANIFEST
find . $main -o -name samples -prune -o -print >> MANIFEST
find samples $samples -o -print >> MANIFEST

cpio -pd _build/YATT-Lite-$version < MANIFEST
tar zcvf _build/YATT-Lite-$version.tar.gz -C _build YATT-Lite-$version

rm -rf _build/YATT-Lite-$version

if [[ -d ~/rpmbuild/SOURCES ]]; then
    mv -vu _build/YATT-Lite-$version.tar.gz ~/rpmbuild/SOURCES
    rmdir _build
fi
