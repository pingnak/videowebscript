#!/bin/sh

# Convert to 8 bit palettes
pngquant -v --ext .png --force *.png

# Remove any metadata, try various techniques to shrink further
optipng -strip all -o9 *.png

# Format for easy css copy/paste 
find . -name '*.png' -exec printf "\n\n    /* %s */\n    background: url(data:image/png;base64," \{\} \; -exec base64 \{\} \; -exec printf ") no-repeat;" \; | perl -0007 -pe 's/\n\)/)/g' > scratch.txt
