# Introduction #

You like having pure, wizardly shell scripting power at your fingertips, and being able to modify things as you see fit, as you use them, and to fully automate things, with nothing between you and the console-scrolling love?  This is the version for you!

[Get the BASH stuff from version control; it's just text files.](https://code.google.com/p/videowebscript/source/browse/#svn%2Ftrunk%2FBASH)

# Details #

BASH is shell script supported by Mac OSX and the various other UNIXes and LINUXes.  If you are a Windows user, you're not necessarily out in the cold. there is always Cygwin or Win-BASH or various other GNU tools ports for windows.  It's possible the little script I have could be adapted to 'dir /s /b' and some of the token pasting iterators that 'CMD' supports, but... I don't feel motivated to.  If you're computer literate enough to use a shell script (or 'batch file'), you can read the script and port it yourself, or just install one of the aforementioned BASHes for Windows, to run this script.

There is a 'templates' sub-folder with the various HTML tidbits, scripts and CSS that the resulting web pages are created from.  Review the source, and have a look at the output index.html files, too.  You can customize it any which way, or use it as a 'guide' to make your own from scratch.  Basically all it does is paste the pieces together and do some word substitutions to insert titles and paths.  Once you've seen it and understood it, you'll know that you could make one.  It's simple.  The script is less than 200 lines long, and lots of it is comments.

HTML5 support for media files is still crap, as of this writing.  Mostly because Microsoft, Apple, Mozilla, Opera, and everyone else is allowed to pick and choose what features they like, and still claim to be 'standard compliant'.  So some support ogg.  Some support MP4.  Some support 'webm'.  I hold it much less against the companies like Mozilla, who balk at licensing fees for MP3/MP4, and more against the big, rich corporations, like Microsoft and Apple, who won't implement a free, open source, unlimited license standard, with no strings attached for its use, other than to share any modifications that they make to the original source code.

  * http://www.w3schools.com/html/html5_video.asp

This also uses the 'ffmpegthumbnailer' project to create thumbnail images.  You can modify the script to use other thumbnailers, or remove the thumbnail images all together.  Basically, it grabs a frame from a ways in, in the video, and makes a little jpeg picture for the index, and names it the same as the original video file.  Some DLNA servers want thumbnails like that, and this conforms to that 'standard'.  Most linuxes have it in the software library, and OSX users can install it with 'Homebrew'.  Windows users will probably find binaries for it 'hosted' with infectious, browser altering, malware installing 'setup' packages, all over the web.

  * https://code.google.com/p/ffmpegthumbnailer/

  * http://brew.sh/

See Also: [SecurityCaveats](SecurityCaveats.md)