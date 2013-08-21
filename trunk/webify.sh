#!/bin/bash

#
# Script to generate web page tree from video collection
#

#
# TODO: Hierarchically generate TOC to match directory structure.
#

ROOT=../Classes
INDEX="./index.html"
PAGES="./pages"

#
# Function to generate index and web page for video 
#
function export_html {
    echo $1
    # Chop the path up
    movie_path=$1
    basepath=`dirname "$movie_path"`
    filename=${movie_path##*/}
    filename_noext=${filename%.*}
    filename_webpage=$PAGES/$filename_noext.html
    filename_jpeg=$basepath/$filename_noext.jpg
    
    # Generate a thumbnail (if it doesn't already exist)
    # https://code.google.com/p/ffmpegthumbnailer/
    if test ! -f "$filename_jpeg"; then
        echo ffmpegthumbnailer "$movie_path" 
        ffmpegthumbnailer -f -t18 -s256 -i "$movie_path" -o "$filename_jpeg"
    fi
        
    # Generate the index.html entry
    line_text='        <div><a href="PAGE_PATH"><img style="vertical-align:middle" src="MOVIE_IMAGE" /><font color="#00ffff" size="24">MOVIE_TITLE</font></a></div>'
    echo $line_text | sed -e "s@PAGE_PATH@$filename_webpage@g" -e "s@MOVIE_IMAGE@$basepath/$filename_noext.jpg@g" -e "s@MOVIE_TITLE@$filename_noext@g" >> "$INDEX"
    
    # Generate the web page
    sed -e "s@MOVIE_PATH@../$movie_path@g" -e "s@MOVIE_TITLE@$filename_noext@g" -e "s@MOVIE_TYPE@video/mp4@g" ./templates/single.html > "$filename_webpage"
}

# Generate tree
mkdir -p "$PAGES"
cat ./templates/index_prolog.html > "$INDEX"
find -s $ROOT -name *.mp4 | while read i ; do export_html "$i" ; done
cat ./templates/index_epilog.html >> "$INDEX"
