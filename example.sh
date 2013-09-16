#!/bin/sh

# Default (no parameter) search path for video files
CONTENT_ROOT="/Volumes/video"

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
        echo "    Rebuild video indexes."
        echo
        echo "$0 PATH_TO_VIDEO"
        echo "    Change path to 'PATH_TO_VIDEO', and do the job."
        exit 1
    fi
fi

set -o errexit	# Stop running the script if an error occurs
set -o nounset	# Stop running the script if a variable isn't set
#set -o verbose	# Echo every command

# Generate viewers for top-level categories of video, organized by folder 
find -s "$CONTENT_ROOT" -d 1 -type d -exec webify.sh \{\} \;

# Generate viewers from root, up
webify.sh "$CONTENT_ROOT"

# Generate an index to the various viewers
indexes.sh "$CONTENT_ROOT"

