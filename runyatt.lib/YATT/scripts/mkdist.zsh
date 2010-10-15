#!/bin/zsh

set -e

# XXX: FindBin, chdir
# XXX: version detection.
version=0.0.1

clean=(
    runyatt.lib/t/vfs.d
)

main=(
    -name _build -prune
    -o -name cover_db -prune
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
