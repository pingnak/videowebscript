#!/bin/sh

#
# Script to generate a single web file of all videos
#

# Default (no parameter) search path for video files
CONTENT_ROOT="/Volumes/media/Music"

# What to call the video player files
WEBIFY_PLAYER_INDEX="Jukebox.html"

# What to call the index/table of contents
WEBIFY_INDEX="index.html"

# Get root of script, where we assume the template folder will be
SCRIPT_ROOT=$(dirname "$0")
SCRIPT_TEMPLATES="$SCRIPT_ROOT/templates/JukeboxScript/default"

# File to suck css out of (exported to be findable in backquotes)
CSS_TEMPLATE_FILE="$SCRIPT_TEMPLATES/template.css"
cat "$CSS_TEMPLATE_FILE" > ~/css.txt

# Which template to use 
PLAYER_TEMPLATE_FILE="$SCRIPT_TEMPLATES/player_template.html"

# Cache player template
PLAYER_TEMPLATE=$(cat "$PLAYER_TEMPLATE_FILE")

# Find and cache a copy of media file with thumbnail template
INDEX_FILE=$(echo $PLAYER_TEMPLATE | perl -wln -0777 -e 'm/\<\!\-\-INDEX_FILE(.*?)\-\-\>/s and print $1;')

# Which template to use 
INDEX_TEMPLATE_FILE="$SCRIPT_TEMPLATES/index_template.html"

# Cache player template
INDEX_TEMPLATE=$(cat "$INDEX_TEMPLATE_FILE")

# Folder index list (left side of template file)
INDEX_SMALL=$(echo $INDEX_TEMPLATE | perl -wln -0777 -e 'm/\<\!\-\-INDEX_SMALL(.*?)\-\-\>/s and print $1;')

# Folder index (right side of template file)
INDEX_TOC_FOLDER=$(echo $INDEX_TEMPLATE | perl -wln -0777 -e 'm/\<\!\-\-INDEX_TOC_FOLDER(.*?)\-\-\>/s and print $1;')

# Play file index   
INDEX_TOC_FILE=$(echo $INDEX_TEMPLATE | perl -wln -0777 -e 'm/\<\!\-\-INDEX_TOC_FILE(.*?)\-\-\>/s and print $1;')

# What kinds of files to find
FIND_PARAMS="-type f -name '*.mp3' -o -name '*.ogg'"

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
        echo "    Generate Audio indexes/players in default location set in 'CONTENT_ROOT'."
        echo
        echo "$0 PATH_TO_AUDIO"
        echo "    Change path to 'PATH_TO_AUDIO', and do the job."
        exit 1
    fi
fi

set -o errexit	# Stop running the script if an error occurs
set -o nounset	# Stop running the script if a variable isn't set
#set -o verbose	# Echo every command

#
# Now that the globals and resources are set up, call the folder webifier
#
main_index="$CONTENT_ROOT/$WEBIFY_PLAYER_INDEX"

folder_start=`basename "$CONTENT_ROOT"`

# If we had content in the root of the tree, we need to keep the rest aligned
needed_root=

# We only do one pass of find.
complete_file_list=

# Escape reserved characters in URI
uri_escape() {
    echo $1 | sed -e 's/ /%20/g' -e 's/\!/%21/g' -e 's/\#/%23/g' -e 's/\$/%24/g' -e 's/\&/%26/g' -e 's/(/%28/g' -e 's/)/%29/g' -e 's/\*/%2A/g' -e 's/\+/%2B/g' -e 's/\,/%2C/g' -e 's/\:/%3A/g' -e 's/\;/%3B/g' -e 's/\=/%3D/g' -e 's/\?/%3F/g' -e 's/\@/%40/g' -e 's/\[/%5B/g' -e 's/\]/%5D/g'
# My XML attributes are double-quoted...
# -e "s/\'/%27/g"
}
# Escape quotes in text
quote_escape() {
    # The ampersand '&' is a real pain... escape '@', too, since I use that as a delimiter for sed
    echo $1 | sed -e 's@&@\\\&amp;@g' -e "s@'@\\\\\&apos;@g" -e 's@"@\\\\\&quot;@g' -e 's@<@\\\\\&lt;@g' -e 's@>@\\\\\&gt;@g' -e 's/@/\\\\\&U+00A9;/g'
}

# BusyBox pushd/popd equivalents from Mijzelf
mypushd() {
   pwd >>/tmp/$$.pushed
   cd "$1"
}
mypopd() {
   local last=$( tail -n 1 /tmp/$$.pushed )
   sed -i '$ d' /tmp/$$.pushed
   cd "$last"
}
PUSHD=pushd
POPD=popd
pushd / >/dev/null 2>&1 && popd >/dev/null || { 
    PUSHD="mypushd" 
    POPD="mypopd" 
}

export_folder() {

    # Just the path
    folder_curr="$1"
    folder_name=$(basename "$1")
    if [ "." = "$folder_name" ] ; then
        folder_name=$(basename `pwd`)
    fi

    folder_name_escaped=$(quote_escape "$folder_name")
    folder_curr_escaped=$(uri_escape "$folder_curr")

    # Record folder for index/TOC
    echo $INDEX_SMALL | \
        sed -e "s@FOLDER_PATH@$folder_curr_escaped/$WEBIFY_PLAYER_INDEX@g" \
            -e "s@FOLDER_STYLE@@g" \
            -e "s@FOLDER_TITLE@$folder_name_escaped@g" >> ~/toc1.txt
            
    echo $INDEX_TOC_FOLDER | \
        sed -e "s@FOLDER_PATH@$folder_curr_escaped/$WEBIFY_PLAYER_INDEX@g" \
            -e "s@FOLDER_STYLE@@g" \
            -e "s@FOLDER_TITLE@$folder_name_escaped@g" >> ~/toc2.txt

    # Complete list of files in this folder, at this depth
    # Note: This is the simplest way to get relative paths...
    filelist=$(find . -maxdepth 1 -type f -name '*.mp3' -o -name '*.ogg' -o -name '*.webm' | sort )
    
    echo > ~/tmp.txt
    echo "$filelist" | while read media_path ; 
    do 
        filename=${media_path##*/}
        filename_title=${filename%.*}
        filename_jpeg=${media_path%.*}.jpg

        media_path_escaped=$(uri_escape "$media_path")
        filename_jpeg_escaped=$(uri_escape "$filename_jpeg")
        filename_title_escaped=$(quote_escape "$filename_title")

        # Emit file playback html
        echo $INDEX_FILE | \
            sed -e "s@MEDIA_PATH@$media_path_escaped@g" \
                -e "s@FILE_STYLE@@g" \
                -e "s@MEDIA_TITLE@$filename_title_escaped@g" >> ~/tmp.txt
    
        # Record file for index/TOC
        echo $INDEX_TOC_FILE | \
            sed -e "s@MEDIA_PATH@$folder_curr_escaped/$WEBIFY_PLAYER_INDEX?$media_path_escaped@g" \
                -e "s@FILE_STYLE@@g" \
                -e "s@MEDIA_TITLE@$filename_title_escaped@g" >> ~/toc2.txt
    done

    # Make the player file.
    echo "$PLAYER_TEMPLATE" | \
        sed -e "s@TITLE_TEXT@$folder_name_escaped@g" | \
        perl -pe 's/\/\*INSERT_CSS_HERE\*\//`cat \~\/css.txt`/ge' | \
        perl -pe 's/<\!\-\-INDEXES_HERE\-\-\>/`cat \~\/tmp.txt`/ge' > $WEBIFY_PLAYER_INDEX

    rm ~/tmp.txt

}

# Find all video files, then get the paths, then sort to unique, to build a 
# list of folers to process.
echo
echo On a LAN with a lot of files, initial find may take a little time...
echo 
echo Generating file list from "$CONTENT_ROOT"
$PUSHD "$CONTENT_ROOT"

complete_file_list=$(find . -type f -name '*.mp3' -o -name '*.ogg' )
complete_folder_list=$(echo "$complete_file_list" | while read i ; do dirname "$i" ; done | sort -u -i -f )

echo > ~/toc1.txt
echo > ~/toc2.txt
echo "$complete_folder_list" | while read folder_relative ;
do
    $PUSHD "$folder_relative"
    export_folder "$folder_relative"
    $POPD > /dev/null
done

# Generate the index file
echo "$INDEX_TEMPLATE" | \
    perl -pe 's/\/\*INSERT_CSS_HERE\*\//`cat \~\/css.txt`/ge' | \
    perl -pe 's/<\!\-\-FOLDERS_HERE\-\-\>/`cat \~\/toc1.txt`/ge' |\
    perl -pe 's/<\!\-\-INDEXES_HERE\-\-\>/`cat \~\/toc2.txt`/ge' > $WEBIFY_INDEX

rm ~/toc1.txt
rm ~/toc2.txt
rm ~/css.txt

$POPD > /dev/null
