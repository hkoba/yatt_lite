#!/bin/zsh

cd $0:h || exit 1

for f in **/t; do
  ../runyatt.lib/YATT/scripts/setup.zsh $f:h
done
