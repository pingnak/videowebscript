#!/bin/sh
pngquant --ext .png --force *.png
find . -name '*.png' -exec base64 \{\} \; | sed 's@\(^.*$\)@<img src="data:image/png;base64,\1" />@' > scratch.txt
