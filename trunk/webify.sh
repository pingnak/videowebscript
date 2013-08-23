#!/bin/bash

#
# Script to generate web page tree from video collection
#

# Default (no parameter) search path for video files
CONTENT_ROOT="/Volumes/video"

# Top level folder navigator
WEBIFY_MAIN_INDEX="TOC.html"

# Each folder gets an index.html, but you can rename it if it conflicts
WEBIFY_INDEX="index.html"

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
    if test "$1" = "-clean" ; then
        rm "$CONTENT_ROOT/$WEBIFY_MAIN_INDEX"
        find -s "$CONTENT_ROOT" -name '*.mp4' -o -name '*.ogg' -o -name '*.webm' | while read i ; do dirname "$i" ; done | sort -u | while read folder_path ; 
        do
            rm "$folder_path/$WEBIFY_INDEX"
        done
        exit 0
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
            echo
            echo "$0 -clean"
            echo "    Remove up what this did."
            exit 1
        fi
    fi
fi

set -o errexit	# Stop running the script if an error occurs
set -o nounset	# Stop running the script if a variable isn't set
#set -o verbose	# Echo every command


# lovingly stolen from https://gist.github.com/1573996
relpath() {
    local from="$1" to="$2"
    from=${from//\/\//\/}
    from=${from%/}
    IFS=/
    dirs=(${from#/})
    for to; do
        to=${to//\/\//\/}
        to=${to%/}
        local commonPrefix=/ d=
        for d in "${dirs[@]}"; do
            case "$to/" in "$commonPrefix$d/"*) ;;
            *) break;;
            esac
            commonPrefix+="$d/"
        done
        local ancestor="${from#${commonPrefix%/}}"
        ancestor=${ancestor//[^\/]/}
        ancestor=${ancestor//\//..\/}
    done
    echo "$ancestor${to#$commonPrefix}"
}

#
# Now that the globals and resources are set up, call the folder webifier
#
main_index="$CONTENT_ROOT/$WEBIFY_MAIN_INDEX"

# Generate top portion of index file
cat $INDEX_TOPMOST > "$main_index"
cat $INDEX_CSS >> "$main_index"
cat "$SCRIPT_TEMPLATES/index_main_prolog.html" >> "$main_index"

# Find all video files, then get the paths, then sort to unique, to build a 
# list of folers to process.
echo
echo On network, initial find may take a little time...
find -s "$CONTENT_ROOT" -name '*.mp4' -o -name '*.ogg' -o -name '*.webm' | while read i ; do dirname "$i" ; done | sort -u | while read folder_path ; 
do 
    echo "$folder_path"
    folder_relative=`relpath "$CONTENT_ROOT" "$folder_path"`
    folder_name=${folder_path##*/}
    folder_name_noext=${folder_name%.*}
    
    index_file="$folder_path/$WEBIFY_INDEX"

    # Generate top portion of index file
    cat $INDEX_TOPMOST > "$index_file"
    cat $INDEX_CSS >> "$index_file"
    cat $INDEX_PROLOG | sed -e "s@TITLE_TEXT@$folder_name_noext@g" >> "$index_file"

    pushd "$folder_path" > /dev/null
    find -s . -depth 1 -name '*.mp4' -o -name '*.ogg' -o -name '*.webm' | while read movie_path ; 
    do 
        echo "    $movie_path"
        filename=${movie_path##*/}
        filename_noext=${filename%.*}
        filename_extension=${filename##*.}
        filename_jpeg=${filename%.*}.jpg
        # Generate a thumbnail (if it doesn't already exist)
        # https://code.google.com/p/ffmpegthumbnailer/
        # Puts it along-side the movies, since that's the way my DLNA server takes 'em.
        if test ! -f "$filename_jpeg"; then
            echo ffmpegthumbnailer "$movie_path" 
            ffmpegthumbnailer -f -t18 -s256 -i "$movie_path" -o "$filename_jpeg"
        fi

        # Spit out a line of table of contents
        echo $INDEX_LINE | \
            sed -e "s@VIDEO_IMAGE@$filename_jpeg@g" \
            -e "s@VIDEO_PATH@$filename@g" \
            -e "s@MOVIE_TITLE@$filename_noext@g" >> "$index_file"
    done
    popd > /dev/null

    # Finish index file
    cat $INDEX_EPILOG >> "$index_file"

    # Parse folder name depth to indent?
    echo $INDEX_FOLDER | sed \
        -e "s@FOLDER_PATH@$folder_relative/$WEBIFY_INDEX@g" \
        -e "s@FOLDER_TITLE@$folder_relative@g" >> "$main_index"
    
done

cat "$SCRIPT_TEMPLATES/index_main_epilog.html" >> "$main_index"
