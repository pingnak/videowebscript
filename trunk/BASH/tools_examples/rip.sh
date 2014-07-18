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
# I use homebrew to get the dvdbackup tool, and various other handy things
# http://brew.sh/
#

# Set BASH options 
#set -o verbose	# Echo every command
set -o errexit	# Stop running the script if an error occurs

# This is where you want the output to pile up.  I made a scratch folder on the 
# second HDD.  You should point these wherever you want the files to go, as  
# they're ripped.  Hard-wired in the script, because it's rarely changed.
outputfolder="/Volumes/Macintosh HD 2/scratch"

# Kill the parent of $$
function closetab() {
    #sleep 1
    kill -9 `ps -p ${pid:-$$} -o ppid=`
}

if [ -n "$1" -a -n "$2" ] ; then
	# We got a parameter: Specific volume or recursive call case
	# Grab the name from the volume label.
	set -o nounset	# Stop running the script if a variable isn't set
	device=$1
	ripname=$2
	ripto=$outputfolder/$ripname.dvdmedia
    rippingto=$outputfolder/~$ripname

    # Note: We spit the disk out to show which one had a problem, or finished.
    # It's also easier to put it back in than to launch 'disk utility', to remount
	if [ -e "$ripto" ] ; then
	    echo
		echo Skipping: $ripto because it was already completed.
		tput bel
		read -p "Press [Enter] key to close tab..."
		hdiutil eject "$device" 
		closetab
	elif [ -e "$rippingto" ] ; then
	    echo
		echo "Skipping: $ripto because it is in progress (may be abandoned rip, or duplicate title name)"
		tput bel
		read -p "Press [Enter] key to close tab..."
		hdiutil eject "$device" 
		closetab
	else

		echo
		echo Ripping: $device to $ripto
		echo
        
		# We must unmount logical drive
		hdiutil unmount "$device" 
		
		# Use ddrescue to copy to iso (really slow, but may help with damaged media)
		# http://www.gnu.org/s/ddrescue/
		#ddrescue "$2" "$ripto"

		# Use dvdbackup to copy to iso
		# http://dvdbackup.sourceforge.net/
		dvdbackup --progress -M -i "$device" -o "$outputfolder" -n "~$ripname"
		
		# Work-around for some sort of internal buffer overflow that occasionally truncates '.dvdmedia' from output filename
		# Also doesn't leave '.dvdmedia' folders that are being actively created, to be played/encoded by mistake
		mv "$rippingto" "$ripto"

		# Eject completed rip
		hdiutil eject "$device" 

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

	# Show us what we're up to, in output folder.
    open "$outputfolder"

    mount | grep /dev/disk.*udf | while read currmount
    do
        # Get device
        device=`echo $currmount | cut -d ' ' -f 1`
		# Clean up messy DVD titles
        volume=`echo $currmount | cut -d ' ' -f 3`
        volume=`basename $volume`
        volume=`echo "$volume" | tr -cd 'A-Za-z0-9_-'`
        echo "rip.sh $device -> $volume"
        osascript -e 'tell application "Terminal" to activate' -e 'tell application "System Events" to tell process "Terminal" to keystroke "t" using command down'
        osascript -e 'tell application "Terminal" to do script "rip.sh '$device' '$volume'" in selected tab of the front window'
    done
	
	echo All done!
fi

