#!/bin/bash

#
# Script to generate web page tree from video collection
#

# Default (no parameter) search path for video files
export CONTENT_ROOT="/Volumes/video/Classes"

# Override CONTENT_ROOT if we pass in a directory/folder 
if test -d "$1" ; then 
	CONTENT_ROOT="$1"
else
    echo "Use default: $CONTENT_ROOT"
fi


# Name of folder we bury our page content in
export PAGES_NAME="webify_data"

# Name of our global CSS file
export CSS_NAME="webified.css"
export VIDEO_PLAYER="videoplayer.html"

# Get root of script, where we assume the template folder will be
export SCRIPT_ROOT=`dirname "$0"`
export SCRIPT_TEMPLATES="$SCRIPT_ROOT/templates"

# Root to put all the html stuff in, relative to ROOT
export HTMLROOT=.

# Name of root index file (a flattened version of all movies)
export WEBIFY_INDEX="$CONTENT_ROOT/index.html"

# Name of folder to stuff all the other things, besides the index
export WEBIFY_PAGES="$CONTENT_ROOT/$PAGES_NAME"

# mp4, webm, ogg 
#Exclude the web content, naturally -not -path "./directory/*"
export FIND_VIDEOS="-name *.mp4 -o -name *.ogg -o -name *.webm -not -path \"$WEBIFY_PAGES\""

# slurp in constantly pasted content, to speed things along
export LINE_HTML=`cat $SCRIPT_TEMPLATES/index_file.html`
export FOLDER_HTML=`cat $SCRIPT_TEMPLATES/index_folder.html`

# Make sure we have the output path for all the bits and pieces
mkdir -p "$WEBIFY_PAGES"

# Copy the CSS file
cp "$SCRIPT_TEMPLATES/$CSS_NAME" "$WEBIFY_PAGES"
cp "$SCRIPT_TEMPLATES/Folder.svg" "$WEBIFY_PAGES"

# Copy the video player and tell it about the CSS file
sed -e "s@WEBIFIED_CSS@./$CSS_NAME@g" \
    $SCRIPT_ROOT/templates/$VIDEO_PLAYER > "$WEBIFY_PAGES/$VIDEO_PLAYER"

#
# Now that the globals and resources are set up, call the folder webifier
#

$SCRIPT_ROOT/templates/webify_folder.sh $CONTENT_ROOT

# Note: We've littered this bash session with all of these variables, to call 
# webify_folder.sh.  So now you can call webify_folder.sh, too. 
