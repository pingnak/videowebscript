# Video Web Script, Jukebox Script, Contact Sheet

Scripts to generate a web interface for a collection of videos, music or pictures.  See the wiki links, somewhere on this page, for details about setting up or building the various pieces.

## Introduction

So you have a bunch of MP4s, MP3s, JPEGs, perhaps for a library, perhaps for classes?  

Maybe you just need to knock together a simple, snappy web site to play your home movies?

All these scripts do, is iterate through folders and build a web page interface for the media, with a table of contents.  It can be browsed and played by a web browser that supports the relevant HTML5 features, either locally, on a hard disk, or served by a web server built into NAS or on your computer, over your LAN.

This provides a consistent, portable user interface for that content on practically any computer that you open it with, given an HTML5 compatible-enough browser.

##The Wiki Documents

Go to the [Wiki Pages](https://github.com/pingnak/videowebscript/wiki), to get more details about how to use and customize this.

##The new, 'monolithic' UI...

* Has a new implementation that sucks all of the web pages into one index.html, instead of one html player file, per folder, and an index.html file, too.

* The Python scripts should still directly run on most NAS boxes that you can shell into, unless you have truly monstrous numbers of media files.

* Builds the pages a bit faster, when run over network shares.

* You can put the video player into 'full screen' mode, and keep it that way.  Runs well in any browser mode, especially where the main browser controls are hidden, including 'kiosk' and 'presentation' modes.

* Added/fixed the junk to add it as an iOS/Android 'Home Screen' icon ('web app' launch), and gave it an icon.

* Fixed issues with full-screen mode present on Android/Silk/etc. browsers.  

* A bit more scalable/navigable for smaller screens

* Mostly fixed my 'nice' seek bar, to work for most screens, except truly ridiculously small ones.  Reverts to native video controls when there just isn't enough room.

* Kindle Silk browser still has some issues, if you leave full screen mode and try to go back in the same session, you get technicolor spew.  Also the audio player positioning is a bit borked.  These appear to be driver/browser implementation bugs.

There are native and Adobe AIR installers, if you have a phobia of shell commands.

I'm still deciding whether to dive in and make a python front-end and installer with 'kivy'. 

##Screen Shots

![screen shot 2015-06-02 at 10 59 29](https://cloud.githubusercontent.com/assets/6754243/7943027/de4f79f2-0916-11e5-84b4-e001eab2c205.png)

Landscape, Phone/iPod Sized, Play List (Physics for Future Presidents, Richard A. Muller, Berkely)

![screen shot 2015-06-02 at 16 31 10](https://cloud.githubusercontent.com/assets/6754243/7949663/12d0a272-0945-11e5-83d7-e299326282ce.png)

Landscape, Phone/iPod Sized, Player (Physics for Future Presidents, Richard A. Muller, Berkely)

![screen shot 2015-06-02 at 11 08 43](https://cloud.githubusercontent.com/assets/6754243/7943181/ced4c2ba-0917-11e5-8084-93cc4e463900.png)

Portrait, Phone/iPod Sized, Audio Player

## Skinning

Now you can skin/change the HTML templates for all of the tools, from a couple of files.  Without recompiling.  

Just edit a CSS file, point the tool at it, and run, if you don't like my topaz coloring, or icons, or just want to make the icons 'match' your own browser's control scheme.

Edit the other files to add your own personal touches, like your own personalized titles, or completely alter the user interface, to fit some other need.

See: https://github.com/pingnak/videowebscript/wiki/Skinning-or-Theming

##License

I can't control what you do with it, and don't really care, because _I can't control what you do with it_.  Use it, abuse it, modify and release it again as your own without giving me any 'credit'.  Just don't blame me for what happens if you break laws or try to use it as part of a missile guidance system and blow yourself up, or whatever.

The output of these tools is your own, and your own fault.  What it generates is just plain HTML with minimal javascript code to do the job.  It's too trivial for me to care about.  Grab the source and make any changes you like.

