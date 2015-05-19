#!/bin/sh
path=/Volumes/media
template=default
if [ '' != '$1' ]; then
	template="$1"
fi
echo Template $template
./videowebscript.py $path/Video $template
./jukeboxscript.py  $path/Music $template

