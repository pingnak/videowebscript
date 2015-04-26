# videowebscript

Scripts to generate a web interface for a collection of videos, music or pictures.  See the wiki links, somewhere on this page, for details about setting up or building the various pieces.

## Introduction

So you have a bunch of MP4s, MP3s, JPEGs, perhaps for a library, perhaps for classes?  

Maybe you just need to knock together a simple, snappy web site to play your home movies?

All these scripts do, is iterate through folders and build a web page interface for the media, with a table of contents.  It can be browsed and played by a web browser that supports the relevant HTML5 features, either locally, on a hard disk, or served by a web server built into NAS or on your computer, over your LAN.

This provides a consistent, portable user interface for that content on practically any computer that you open it with, given an HTML5 compatible-enough browser.

## To Just Get The Binaries (What you're probably here for...)

### VideoWebScript.air - Generate Web Interfaces To Play MP4/M4V

[Video Web Player Generator AIR Installer](https://github.com/pingnak/videowebscript/blob/master/AIR/videowebscript/VideoWebScript.air?raw=true)

[Video Web Player Generator Native OS X Installer](https://github.com/pingnak/videowebscript/blob/master/AIR/videowebscript/VideoWebScript.dmg?raw=true)

[Video Web Player Generator Native Windows Installer](https://github.com/pingnak/videowebscript/blob/master/AIR/videowebscript/VideoWebScript.exe?raw=true)

### Generate Web Interfaces To Play MP3

[Jukebox Web Generator AIR Installer](https://github.com/pingnak/videowebscript/blob/master/AIR/jukeboxscript/JukeboxScript.air?raw=true)

[Jukebox Web Generator Native OS X Installer](https://github.com/pingnak/videowebscript/blob/master/AIR/jukeboxscript/JukeboxScript.dmg?raw=true)

[Jukebox Web Generator Native Windows Installer](https://github.com/pingnak/videowebscript/blob/master/AIR/jukeboxscript/JukeboxScript.exe?raw=true)

### Generate Web Interfaces To View Photos

[Contact Sheet Generator AIR Installer](https://github.com/pingnak/videowebscript/blob/master/AIR/contactscript/ContactSheet.air?raw=true)

[Contact Sheet Generator Native OS X Installer](https://github.com/pingnak/videowebscript/blob/master/AIR/contactscript/ContactSheet.dmg?raw=true)

[Contact Sheet Generator Native Windows Installer](https://github.com/pingnak/videowebscript/blob/master/AIR/contactscript/ContactSheet.exe?raw=true)


https://get.adobe.com/air/

You'll need the Adobe AIR runtime, to run the AIR projects, or use the native installers that have their own copy of AIR.

## The Projects

  * AIRWebScript - An Adobe AIR app For Mac, Windows, ~~Linux~~ (thanks, Adobe, for being short-sighted nitwits), etc. users.  With setup software for your OS, and a graphical user interface.

  * AIRContactSheet - An organizer/indexer/thumbnailer for digital photographs.

  * AIRWebJukebox - An organizer/indexer/player for MP3 music.

  * BASHWebScript - A set of simple BASH (Mac, Linux, UNIX) shell scripts based on several command line tools, to do the video export.

##License

I picked the MIT license, mainly because the 'contact sheet' app [https://github.com/bashi/exif-as3 uses an 'exif-as3' library from GitHub] that picks through the EXIF data in jpeg files, and that's its license.

I can't control what you do with it, and don't really care, because _I can't control what you do with it_.  Use it, abuse it, modify and release it again as your own without giving me any 'credit'.  Just don't blame me for what happens if you break laws or try to use it as part of a missile guidance system and blow yourself up, or whatever.

The output of these tools is your own.  What it generates is just plain HTML with minimal javascript code to do the job.  It's too trivial to care about.  Grab the source and make any changes you like.

JPGEncoder.as found its way back into the project, for AIR 2.6+Linux compatibility, and that's "Copyright (c) 2008, Adobe Systems Incorporated - All rights reserved."  If you build with a newer version of AIR/Flex that has BitmapData.encode in it, you can be rid of this.
