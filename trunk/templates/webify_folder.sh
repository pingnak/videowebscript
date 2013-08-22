#!/bin/bash
#
# This script is recursive.  It will build a list of folders, then a list of
# files, and call its self for each of those folders, to make the contents for
# those folders.
#
# Parameters besides the root path are passed as 
#
# Script to generate web page tree from video collection
#
#++++++|+++++++|+++++++|+++++++|+++++++|+++++++|+++++++|+++++++|+++++++|+++++++|
# Notes:
#
# We use relative paths in the export, because we expect one web site or file
# tree to hold it all.  This makes sharing it amoung the various operating 
# systems that share a POSIX OS, and Microsoft's OS, and web sites a lot 
# easier.
#
# This script is recursive.  It will build a list of folders, then a list of
# files, and call its self for each of those folders, to make the contents for
# those folders.

# Override root if we pass in a directory/folder 
if test ! -d $1 ; then
	echo 'Normally this is called from webify.sh.'
	echo 'The parameter must be a folder:' $1
	exit 1
fi

# Escape a string that might contain URI contamination
function uri_escape() {
    echo "$@" | sed 's/ /%20/g;s/!/%21/g;s/"/%22/g;s/#/%23/g;s/\$/%24/g;s/\&/%26/g;s/'\''/%27/g;s/(/%28/g;s/)/%29/g;s/:/%3A/g'
}

#
# Function to generate index and web page for video 
#
function export_html {
    echo $1

    # Chop the path up into manageable chunks
    # This is probably where your odball, BASH-like shells will have issues.
    movie_path=$1
    filename=${movie_path##*/}
    filename_noext=${filename%.*}
    filename_extension=${filename##*.}

    # Generate a thumbnail (if it doesn't already exist)
    # https://code.google.com/p/ffmpegthumbnailer/
    # Puts it along-side the movies, since that's the way my DLNA server takes 'em.
    filename_jpeg=${movie_path%.*}.jpg
    if test ! -f "$filename_jpeg"; then
        echo ffmpegthumbnailer "$movie_path" 
        ffmpegthumbnailer -f -t18 -s256 -i "$movie_path" -o "$filename_jpeg"
    fi

    # Generate the index.html entry
    uri_path=.`uri_escape $movie_path`
    echo $LINE_HTML | sed \
        -e "s@VIDEO_PLAYER@./$PAGES_NAME/$VIDEO_PLAYER@g" \
        -e "s@MOVIE_IMAGE@$filename_jpeg@g" \
        -e "s@VIDEO_PATH@$uri_path@g" \
        -e "s@MOVIE_TITLE@$filename_noext@g" >> "$WEBIFY_INDEX"
}

# Generate top half of index
sed -e "s@WEBIFIED_CSS@./$PAGES_NAME/$CSS_NAME@g" \
    -e "s@TITLE_TEXT@${1##*/}@g" \
    -e "s@WEBIFIED_FOLDER@./$PAGES_NAME@g" \
    $SCRIPT_ROOT/templates/index_prolog.html > "$WEBIFY_INDEX"

# Generate tree
pushd "$CONTENT_ROOT"
find -s . $FIND_VIDEOS -not -path "$WEBIFY_PAGES" | while read i ; do export_html "$i" ; done
popd

# Finish index
cat $SCRIPT_ROOT/templates/index_epilog.html >> "$WEBIFY_INDEX"

