#!/bin/sh
pngquant -v --ext .png --force *.png
optipng -strip all -o7 *.png
find . -name '*.png' -exec printf "\n<!--%s-->\ndata:image/png;base64," \{\} \; -exec base64 \{\} \; > scratch.txt
