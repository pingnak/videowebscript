# Introduction #

This does more or less the same thing as [AIRWebScript](AIRWebScript.md), but with your JPEG photographs.

# Setup #

[You can get the contact sheet maker here.](https://videowebscript.googlecode.com/svn/trunk/AIR/contactscript/deploy/ContactSheet.air)

[If you run it, and nothing good happens, you'll need Adobe AIR.](http://get.adobe.com/air/)

# It Says I Didn't Configure The Installer Right! #

Actually, that's Adobe having fits about the self signed certificate being different. If you manually remove the previous version from the computer, you can install the next (and later) versions, just fine.

# How To Use It #

This works just the same as 'VideoWebScript', iterating folders and files, generating thumbnails and viewers.  Rather than generate thumbnails along-side the images, it bakes them into the ContactSheet.html pages, at a slight additional cost in storage, but very conveniently for having some tidy place to keep them all.

Otherwise, recursively crawl a tree of folders for images, and link them all together with thumbnails in web pages.  The thumbnails 'wrap' like text, so the page layout adapts to whatever sized device is opening the thumbnails.  Keep them small, if you're going to view on tablets and phones.

The tool cooks up EXIF data, and generates GPS links (if present) for the images.

Click the little thumbnails, see big image at top of page.  Click big image, it collapses to just the thumbnails.

This is beta quality, and there are going to be bugs, for a bit.

  * [...] Pick a path.
  * [`*`] Open path in your OS' file browser.
  * [♫] Checkbox enable 'ding dong' at end.
  * Thumbnail size Sets how big the thumbnails will be.
  * Generate index.html Makes a single index.html with all of the ContactSheet.html files linked together.

It builds just like VideoWebScript.  I probably need to make a way to export and override the html templates, so it's easier to customize the appearance and behavior of what this spits out.