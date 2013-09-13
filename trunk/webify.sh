#!/bin/bash

#
# Script to generate a single web file of all videos
#

# Default (no parameter) search path for video files
CONTENT_ROOT="/Volumes/video"

# Adds 'TOC.html' in root of video tree, lists all folders
WEBIFY_MAIN_INDEX="index.html"

# Get root of script, where we assume the template folder will be
SCRIPT_ROOT=`dirname "$0"`
SCRIPT_TEMPLATES="$SCRIPT_ROOT/templates"

# slurp in constantly pasted content, to speed things along
INDEX_TOPMOST="$SCRIPT_TEMPLATES/index_topmost.html"
INDEX_CSS="$SCRIPT_TEMPLATES/webified.css"
INDEX_PROLOG="$SCRIPT_TEMPLATES/index_prolog.html"
INDEX_EPILOG="$SCRIPT_TEMPLATES/index_epilog.html"

# These two are used so much, just cache them
INDEX_LINE=`cat $SCRIPT_TEMPLATES/index_file.html`
INDEX_FOLDER=`cat $SCRIPT_TEMPLATES/index_folder.html`

# Override CONTENT_ROOT if we pass in a directory/folder 
if test -d "$1" ; then 
	CONTENT_ROOT="$1"
else
    if test -z "$1" ; then
        echo "Using default: $CONTENT_ROOT"
    else
        echo
        echo "Invalid parameter."
        echo
        echo "$0"
        echo "    Generate video indexes/players in default location set in 'CONTENT_ROOT'."
        echo
        echo "$0 PATH_TO_VIDEO"
        echo "    Change path to 'PATH_TO_VIDEO', and do the job."
        exit 1
    fi
fi

set -o errexit	# Stop running the script if an error occurs
set -o nounset	# Stop running the script if a variable isn't set
#set -o verbose	# Echo every command

#
# Now that the globals and resources are set up, call the folder webifier
#
main_index="$CONTENT_ROOT/$WEBIFY_MAIN_INDEX"

folder_start=`basename "$CONTENT_ROOT"`

# Generate top portion of index file
cat $INDEX_TOPMOST > "$main_index"
cat $INDEX_CSS >> "$main_index"
cat $INDEX_PROLOG | sed \-e "s@TITLE_TEXT@$folder_start@g" >> "$main_index"

# If we had content in the root of the tree, we need to keep the rest aligned
needed_root=

function export_folder {
    
    # Parse folder name depth to indent?
    echo $INDEX_FOLDER | sed \
        -e "s@FOLDER_PARENT@$folder_parent@g" \
        -e "s@FOLDER_TITLE@$folder_name@g" >> "$main_index"

    # Now drop in a collapsed tree of titles for the current folder entry
    if test "true" = "$isroot" ; then
        echo '<div id="titles">' >> "$main_index"
    else
        echo '<div id="titles" style="display:none;">' >> "$main_index"
    fi
    find -s "$folder_relative" -depth 1 -name '*.mp4' -o -name '*.ogg' -o -name '*.webm' | while read movie_path ; 
    do 
        echo "$movie_path"
        filename=${movie_path##*/}
        filename_noext=${filename%.*}
        filename_jpeg=${movie_path%.*}.jpg

        # Generate a thumbnail (if it doesn't already exist)
        # https://code.google.com/p/ffmpegthumbnailer/
        # Puts it along-side the movies, since that's the way my DLNA server takes 'em.
        # If you think that's 'messy', you can dump all the thumbnails into a different
        # folder by tinkering with the 'filename_jpeg', and making that folder.
        # e.g. filename_jpeg=$CONTENT_ROOT/thumbnails/$filename_noext.jpg
        if test ! -f "$filename_jpeg"; then
            echo ffmpegthumbnailer "$movie_path" 
            ffmpegthumbnailer -f -t18 -s128 -i "$movie_path" -o "$filename_jpeg"
        fi

        # Spit out a line of table of contents
        echo $INDEX_LINE | \
            sed -e "s@VIDEO_IMAGE@$filename_jpeg@g" \
            -e "s@VIDEO_PATH@$movie_path@g" \
            -e "s@MOVIE_TITLE@$filename_noext@g" >> "$main_index"
    done
    echo '</div>' >> "$main_index"
}

# Find all video files, then get the paths, then sort to unique, to build a 
# list of folers to process.
echo
echo On a LAN with a lot of files, initial find may take a little time...
echo "$CONTENT_ROOT"
pushd "$CONTENT_ROOT" > /dev/null
find -s . -name '*.mp4' -o -name '*.ogg' -o -name '*.webm' | while read i ; do dirname "$i" ; done | sort -u -i -f | while read folder_relative ; 
do
    echo $folder_relative
    # Lookup 'BASH parameter expansion', to decode this stuff
    isroot=
    folder_name=`basename "$folder_relative"`
    folder_path="$CONTENT_ROOT${folder_relative#.}"
    folder_parent=`dirname "$folder_relative"`
    if test "." = "$folder_name" ; then
        folder_name="$folder_start"
        needed_root="$folder_start/"
        folder_parent=
    else
        if test "." = "$folder_parent" ; then
            folder_parent="$needed_root"
        else
            folder_parent="$needed_root${folder_parent:2}/"
        fi
        export_folder
    fi
    
done

isroot="true"
folder_relative="."
folder_name="$folder_start"
needed_root="$folder_start/"
folder_parent=
export_folder

popd > /dev/null

cat $INDEX_EPILOG >> "$main_index"
