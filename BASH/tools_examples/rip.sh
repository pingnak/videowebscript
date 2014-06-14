#!/bin/bash

#
# Auto-multi-ISO-ripper (OSX)
#
# As you replace CD/DVD disks in the finished drives, you can re-invoke in a new
# shell to carry on ripping more.  It won't re-rip and overwrite what's in the
# scratch folder.  
#
# CAUTION: Not all discs are labeled properly (DVD_VIDEO is a common default, for instance)
#

# This is where you want the output to pile up.  I made a scratch folder on the 
# second HDD.  You should point these wherever you want the files to go, as  
# they're ripped.
outputfolder="/Volumes/Macintosh HD 2/scratch"


if [ -n "$1" ] ; then
	# We got a parameter: Specific volume or recursive call case
	# Grab the name from the volume label.
	ripto="$outputfolder/`basename $1`.iso"

	if [ -e "$ripto" ] ; then
		echo Skipping:	$ripto
	else
		echo Ripping:	$ripto

		# Invoke makehybrid on $1, rip to iso, then spit it out
		hdiutil makehybrid -iso -joliet -o "$ripto" "$1" 
		hdiutil eject "$1" 

		echo
		echo Finished $1

		# Make a noise, to wake user up, to feed more media, as applicable
		tput bel
		#say -r 200 "Finished $1"

	fi
else
	# Find all read only volumes (assume they're what we're ripping)
	# Tell xargs to launch 'rip.sh' on them.
	# Maximum 4 processes (4 drives ripping to $outputfolder, at once)
	disclist=`find /Volumes -maxdepth 1 -fstype rdonly`
	echo $disclist | xargs -P 4 -n 1 rip.sh 

    # Now we could invoke HandBrakeCLI on it, except it doesn't really lend its
    # self to a generic invocation, with all the various kinds of DVD tacks,
    # languages, etc.  Far easier to manage that manually in the GUI, and use its 
    # internal queue.
    #
    # echo $disclist | xargs -n 1 encode.sh
	
	echo All done!
fi

