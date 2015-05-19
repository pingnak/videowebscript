#!/bin/sh
mediapath=/Volumes/media
if [ "" != "$1" ] ; then
	mediapath="$1"
fi
time python videowebscript.py $mediapath/Video $2
time python jukeboxscript.py  $mediapath/Music $2
