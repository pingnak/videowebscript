#/bin/sh
#
# List files in most recent order (no parameter), or find files (given search parameter)
#

# Set to location of video collection
wherearethey=/Volumes/media/Movies
if [ -z "$1" ]
then
    find "$wherearethey" -type f -iname *.mp4 -print0 | xargs -0 stat -f "%m %N" | sort -rn | cut -f2- -d" " | less
else
    find "$wherearethey" -type f -iname *.mp4 | sort | grep -i "$1" | less
fi
                                               
