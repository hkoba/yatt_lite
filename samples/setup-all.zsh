#!/bin/zsh

for f in **/t; do
  ../runyatt.lib/YATT/scripts/setup.zsh $f:h
done
