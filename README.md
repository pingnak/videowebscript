# Video Web Script, Jukebox Script, Contact Sheet

Scripts to generate a web interface for a collection of videos, music or pictures.  See the wiki links, somewhere on this page, for details about setting up or building the various pieces.

## Introduction

So you have a bunch of MP4s, MP3s, JPEGs, perhaps for a library, perhaps for classes?  

Maybe you just need to knock together a simple, snappy web site to play your home movies?

All these scripts do, is iterate through folders and build a web page interface for the media, with a table of contents.  It can be browsed and played by a web browser that supports the relevant HTML5 features, either locally, on a hard disk, or served by a web server built into NAS or on your computer, over your LAN.

This provides a consistent, portable user interface for that content on practically any computer that you open it with, given an HTML5 compatible-enough browser.

## Releases

[The latest stable release](https://github.com/pingnak/videowebscript/releases) is in the github release system.

Otherwise, each of the [AIR projects](https://github.com/pingnak/videowebscript/tree/master/AIR) has 'latest builds', and the [BASH script](https://github.com/pingnak/videowebscript/tree/master/BASH) version should always be usable.

## Skinning

Now you can skin/change the HTML templates for all of the tools, from a couple of files (or just customize the CSS).  Without recompiling.

See: https://github.com/pingnak/videowebscript/wiki/Skinning-or-Theming

## The Wiki Documents

Go to the [Wiki Pages](https://github.com/pingnak/videowebscript/wiki), to get more details about how to use and customize this.

##License

I picked the MIT license, mainly because the 'contact sheet' app [uses an 'exif-as3' library](https://github.com/bashi/exif-as3) that picks through the EXIF data in jpeg files, and that's its license.

I can't control what you do with it, and don't really care, because _I can't control what you do with it_.  Use it, abuse it, modify and release it again as your own without giving me any 'credit'.  Just don't blame me for what happens if you break laws or try to use it as part of a missile guidance system and blow yourself up, or whatever.

The output of these tools is your own, and your own fault.  What it generates is just plain HTML with minimal javascript code to do the job.  It's too trivial for me to care about.  Grab the source and make any changes you like.

