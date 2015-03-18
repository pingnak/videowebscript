A script to generate a web interface for a collection of videos.

# Introduction #

So you have a bunch of MP4s, MP3s, JPEGs, perhaps for a library, perhaps for classes?

Maybe you just need to knock together a simple, snappy web site to play your home movies?

All these scripts do are iterate through folders and build a web page interface for the media, with a table of contents.  It can be browsed and played by a web browser that supports the relevant HTML5 features, either locally, on a hard disk, or served by a web server built into NAS or on your computer, over your LAN.

This provides a consistent, portable user interface for that content on practically any computer you open it with, given an HTML5 compatible-enough browser.

# To Just Get The Binaries (What You're Usually Here For) #

  * [VideoWebScript.air - Generate Web Interfaces To Play MP4/M4V](https://videowebscript.googlecode.com/svn/trunk/AIR/videowebscript/deploy/VideoWebScript.air)

  * [JukeboxScript.air - Generate Web Interfaces To Play MP3](https://videowebscript.googlecode.com/svn/trunk/AIR/jukeboxscript/deploy/JukeboxScript.air)

  * [ContactSheet.air - Generate Web Interfaces To View Photos](https://videowebscript.googlecode.com/svn/trunk/AIR/contactscript/deploy/ContactSheet.air)

# The Projects #

  * [AIRWebScript](AIRWebScript.md) - An Adobe AIR app For Mac, Windows, ~~Linux~~ (thanks, Adobe, for being short-sighted nitwits), etc. users.  With setup software for your OS, and a graphical user interface.

  * [AIRContactSheet](AIRContactSheet.md) - An organizer/indexer/thumbnailer for digital photographs.

  * [AIRWebJukebox](AIRWebJukebox.md) - An organizer/indexer/player for MP3 music.

  * [BASHWebScript](BASHWebScript.md) - A set of simple BASH (Mac, Linux, UNIX) shell scripts based on several command line tools, to do the video export.

# Compatibility #

Works with iOS, Android, various browsers, basically, anything 'new' enough to claim support for.

  * [HTML5 Canvas](http://www.w3schools.com/html/html5_canvas.asp) (Contact Sheet)
  * [HTML5 Audio + MP3](http://www.w3schools.com/html/html5_audio.asp) (Jukebox)
  * [HTML5 Video + MP4](http://www.w3schools.com/html/html5_video.asp) (Video Player)
  * Works with a desktop Chrome browser and a [ChromeCast](ChromeCast.md) device, but inefficiently.
  * Pointing a symbolic link at the accessible content with a web server works great, to stream to devices **See [SecurityCaveats](SecurityCaveats.md)**

[Also try HTML5test, for a list attempting to break down these capabilities by devices and browsers...](http://html5test.com/results/other.html)

# Building It #

See: [BuildIt](BuildIt.md)

# License #

I picked the MIT license, mainly because the 'contact sheet' app [uses an 'exif-as3' library from GitHub](https://github.com/bashi/exif-as3) that picks through the EXIF data in jpeg files, and that's its license.

I can't control what you do with it, and don't really care, because _I can't control what you do with it_.  Use it, abuse it, modify and release it again as your own without giving me any 'credit'.  Just don't blame me for what happens if you break laws or try to use it as part of a missile guidance system and blow yourself up, or whatever.

The output of these tools is your own.  What it generates is just plain HTML with minimal javascript code to do the job.  It's too trivial to care about.  Grab the source and make any changes you like.

JPGEncoder.as found its way back into the project, for AIR 2.6+Linux compatibility, and that's "Copyright (c) 2008, Adobe Systems Incorporated - All rights reserved."  If you build with a newer version of AIR/Flex that has BitmapData.encode in it, you can be rid of this.