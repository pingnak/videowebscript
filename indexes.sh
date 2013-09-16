#!/bin/bash

#
# Script to link together index.html files
#

# Default (no parameter) search path for video files
CONTENT_ROOT="/Volumes/video"

# Adds 'TOC.html' in root of video tree, lists all folders
WEBIFY_MAIN_INDEX="TOC.html"

# Get root of script, where we assume the template folder will be
SCRIPT_ROOT=`dirname "$0"`
SCRIPT_TEMPLATES="$SCRIPT_ROOT/templates"

# slurp in constantly pasted content, to speed things along
INDEX_TOPMOST="$SCRIPT_TEMPLATES/index_topmost.html"
INDEX_CSS="$SCRIPT_TEMPLATES/webified.css"
INDEX_PROLOG="$SCRIPT_TEMPLATES/TOC_prolog.html"
INDEX_EPILOG="$SCRIPT_TEMPLATES/index_epilog.html"

# These two are used so much, just cache them
INDEX_INDEX=`cat $SCRIPT_TEMPLATES/index_index.html`

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
        echo "    Find index.html files, and string them together into a '$WEBIFY_MAIN_INDEX'."
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

# Find all video files, then get the paths, then sort to unique, to build a 
# list of folers to process.
echo
echo On a LAN with a lot of files, initial find may take a little time...
echo $CONTENT_ROOT
pushd "$CONTENT_ROOT" > /dev/null
find . -name 'index.html' | sort -u | while read folder_relative ; 
do
    echo $folder_relative
    # Lookup 'BASH parameter expansion', to decode this stuff
    folder_parent=`dirname "$folder_relative"`
    folder_name=`basename "$folder_parent"`
    folder_parent=`dirname "$folder_parent"`
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
    fi
    
    # Parse folder name depth to indent?
    echo $INDEX_INDEX | sed \
        -e "s@FOLDER_PATH@$folder_relative@g" \
        -e "s@FOLDER_PARENT@$folder_parent@g" \
        -e "s@FOLDER_TITLE@$folder_name@g" >> "$main_index"
done
popd > /dev/null

cat $INDEX_EPILOG >> "$main_index"
