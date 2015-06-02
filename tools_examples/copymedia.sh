#!/bin/bash
echo
echo Media backup script!
echo 

# Our main video pile, on NAS, some place...
srcvolume=/Volumes/media

# Incremental copy, show progress, skip invisible, copy links as files, delete what doesn't exist on source, some DOS/FAT params
aflags='--progress --update --recursive --exclude=".*" --cvs-exclude --copy-links --delete --modify-window=2 -l --no-g --no-p --max-size=4294967295'
# --dry-run 

# Ultimately quicker to do it on destination volume, which is usually locally mounted
function CopyFiles {
	if [ -d "$1" ]; then 

		echo $srcvolume/Movies/ -\> $1/Movies
		rsync $aflags "$srcvolume/Movies/" "$1/Movies"
		
		echo $srcvolume/Series/ -\> $1/Series
		rsync $aflags "$srcvolume/Series/" "$1/Series"
		
		# Remove time stamps that could be used as a signature from destination
		find "$1" -name '.*' -exec rm -rf \{\} \;
		find "$1" -exec touch \{\} \;
		
		# OS X: Don't crawl this drive over and over while I copy to it.
		touch "$1/.metadata_never_index" ; chmod -w "$1/.metadata_never_index"
	fi
}


# If we give a parameter, use it as a destination
if [ -n "$1" ] ; then
	CopyFiles "$1"
fi
