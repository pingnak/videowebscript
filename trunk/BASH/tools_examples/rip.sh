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

# Kill the parent of $$
function closetab() {
    #sleep 1
    kill -9 `ps -p ${pid:-$$} -o ppid=`
}

if [ -n "$1" -a -n "$2" ] ; then
	# We got a parameter: Specific volume or recursive call case
	# Grab the name from the volume label.
	ripname="`basename $1`.dvdmedia"
	ripto="$outputfolder/$ripname"
	#ripto="$outputfolder/`basename $1`.iso"

	if [ -e "$ripto" ] ; then
		echo Skipping:	$ripto
		closetab
	else
		echo
		echo Ripping:	$2 to $ripto
		echo

		# We must unmount logical drive
		hdiutil unmount "$2" 
		
		# Use ddrescue to copy to iso (real slow)
		# http://www.gnu.org/s/ddrescue/
		#ddrescue "$2" "$ripto"

		# Use dvdbackup to copy to iso
		# http://dvdbackup.sourceforge.net/
		dvdbackup --progress -M -i "$2" -o "$outputfolder" -n "$ripname"

		# Eject completed rip
		hdiutil eject "$2" 

		echo
		echo Finished $1

		# Make a noise, to wake user up, to feed more media, as applicable
		tput bel
		#say -r 200 "Finished $1"

		# We opened a tab to do this, so close it.
		closetab
	fi
else
    #
	# Find all mounted volumes that look like DVDs.
	#
	# Launch rip task on each DVD found, in a different tab.
	#
	# This process is basically I/O bound, so several (relatively) slow optical
	# drives vs one hard drive isn't much of an issue.  The bigger issue is
	# having a human standing by to feed them.
	#
	
    mount | grep /dev/disk.*udf | while read currmount
    do
        device=`echo $currmount | cut -d ' ' -f 1`
        volume=`echo $currmount | cut -d ' ' -f 3`
        volume=`basename $volume`
        volume=`echo "$volume" | tr -cd 'A-Za-z0-9'`
        echo bash -c "rip.sh '$volume' $device"
        osascript -e 'tell application "Terminal" to activate' -e 'tell application "System Events" to tell process "Terminal" to keystroke "t" using command down'
        osascript -e 'tell application "Terminal" to do script "rip.sh '$volume' '$device'" in selected tab of the front window'
    done

	#disclist=`find /Volumes -maxdepth 1 -fstype rdonly`
	#echo $disclist | xargs -P 4 -n 1 rip.sh 

    # Now we could invoke HandBrakeCLI on it, except it doesn't really lend its
    # self to a generic invocation, with all the various kinds of DVD tracks,
    # languages, etc.  Far easier to manage that manually in the GUI, and use its 
    # internal queue.
    #
    # echo $disclist | xargs -n 1 (call some kind of encode.sh)
	
	echo All done!
fi

