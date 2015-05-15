#!/usr/bin/env python

#
# The python version.
# This will work basically the same as the shell version, only less sketchy
# across platforms.  You'll need to install python, but once it's there, it 
# should be pretty consistent.
#

import os
import sys
import re
import random
import distutils.spawn
from subprocess import call
import urllib
from xml.sax.saxutils import quoteattr
from xml.sax.saxutils import escape

root_dir = os.path.normpath(sys.argv[1])
need_jpeg= [];

# What to call the video player files
WEBIFY_PLAYER_INDEX="Jukebox.html"

# What to call the index/table of contents
WEBIFY_INDEX="index.html"

# List of matchable files
FILE_TYPES="\.(mp3|ogg)"

# Where is this script
SCRIPT_ROOT = os.path.dirname(os.path.realpath(sys.argv[0]))

# Where to look for the script templates
SCRIPT_TEMPLATES = os.path.join(SCRIPT_ROOT, "templates/jukeboxscript")

# File to suck css out of (exported to be findable in backquotes)
CSS_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, "template.css")

# Cache CSS template
with open (CSS_TEMPLATE_FILE, "r") as myfile:
    CSS_TEMPLATE=myfile.read()

# Which template to use 
PLAYER_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, "player_template.html")

# Cache player template
with open (PLAYER_TEMPLATE_FILE, "r") as myfile:
    PLAYER_TEMPLATE=myfile.read()

# Find and cache a copy of media file with thumbnail template
INDEX_FILE_MATCH=re.search('<!--INDEX_FILE(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL) 
INDEX_FILE=INDEX_FILE_MATCH.group(1)

# Which template to use 
INDEX_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, "index_template.html")

# Cache index template
with open (INDEX_TEMPLATE_FILE, "r") as myfile:
    INDEX_TEMPLATE=myfile.read()

# Folder index list (left side of template file)
INDEX_SMALL_MATCH = re.search('<!--INDEX_SMALL(.*?)-->', INDEX_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_SMALL = INDEX_SMALL_MATCH.group(1);

# Folder index (right side of template file)
INDEX_TOC_FOLDER_MATCH=re.search('<!--INDEX_TOC_FOLDER(.*?)-->', INDEX_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_TOC_FOLDER = INDEX_TOC_FOLDER_MATCH.group(1);

# Play file index   
INDEX_TOC_FILE_MATCH=re.search('<!--INDEX_TOC_FILE(.*?)-->', INDEX_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_TOC_FILE = INDEX_TOC_FILE_MATCH.group(1);

print( "Crawling folders in %s...\n" % (root_dir) )

#
# Iterate folders & files
#
index_toc_small=""
index_toc=""



for root, dirs, files in os.walk(root_dir):
    #dirs.sort();
    files.sort();

    totalFiles = 0
    for relPath in files:
        dummy,extCurr = os.path.splitext(relPath)
        if None is not re.search( extCurr.lower(), FILE_TYPES ): 
            totalFiles = totalFiles + 1

    if 0 != totalFiles:
        playlist=""

        folder_path, folder_name = os.path.split(root);
        folder_relative = os.path.relpath(root,root_dir);
        folder_curr = os.path.relpath(root,root_dir);
        folder_curr_escaped = urllib.quote(os.path.join(folder_curr,WEBIFY_PLAYER_INDEX))
        folder_name_escaped = escape(folder_name)
        print folder_relative
        sys.stdout.flush();

        # Record folder for left box index/TOC
        output = str(INDEX_SMALL);
        output = output.replace( 'FOLDER_TITLE', folder_name_escaped);
        output = output.replace( 'FOLDER_PATH',  folder_curr_escaped);
        output = output.replace( 'FOLDER_STYLE', '');
        index_toc_small = index_toc_small + output;
    
        # Record folder for big folder+file TOC
        output = str(INDEX_TOC_FOLDER);
        output = output.replace( 'FOLDER_TITLE', folder_name_escaped);
        output = output.replace( 'FOLDER_PATH',  folder_curr_escaped);
        output = output.replace( 'FOLDER_STYLE', '');
        index_toc = index_toc + output;

        for relPath in files:
            fileName, fileExtension = os.path.splitext(relPath)
            fullPath = os.path.join(root, fileName) + fileExtension
            # There should be a jpeg file in folder; if not, add to a list to make it
            dummy,extCurr = os.path.splitext(relPath)
            if None is not re.search( extCurr.lower(), FILE_TYPES ):
                media_path = os.path.relpath(fullPath,root);
                media_path_escaped=urllib.quote(media_path)
                filename_title_escaped=escape(fileName)
                pathcurr=str(INDEX_FILE);

                # Emit elements for video player
                pathcurr = pathcurr.replace( 'MEDIA_PATH', media_path_escaped);
                pathcurr = pathcurr.replace( 'FILE_STYLE', '');
                pathcurr = pathcurr.replace( 'MEDIA_TITLE', filename_title_escaped);
                playlist = playlist + pathcurr;

                # Emit elements for index navigation player
                pathcurr = str(INDEX_TOC_FILE)
                pathcurr = pathcurr.replace( 'MEDIA_PATH', urllib.quote(os.path.join(folder_curr,WEBIFY_PLAYER_INDEX))+'?'+media_path_escaped);
                pathcurr = pathcurr.replace( 'FILE_STYLE', '');
                pathcurr = pathcurr.replace( 'MEDIA_TITLE', filename_title_escaped);
                index_toc = index_toc + pathcurr;

        # Manufacture a VideoPlayer.html for folder
        folder_path, folder_name=os.path.split(root);
        output = str(PLAYER_TEMPLATE);
        output = output.replace( 'TITLE_TEXT', escape(folder_name));
        output = output.replace( '/*INSERT_CSS_HERE*/', CSS_TEMPLATE);
        output = output.replace( '<!--INDEXES_HERE-->', playlist);
        with open(os.path.join(root,WEBIFY_PLAYER_INDEX), "w") as text_file:
            text_file.write(output)

# Manufacture an index.html for entire run
sys.stdout.flush();
print "Building index..."
output = str(INDEX_TEMPLATE);
output = output.replace( '/*INSERT_CSS_HERE*/', CSS_TEMPLATE);
output = output.replace( '<!--FOLDERS_HERE-->', index_toc_small);
output = output.replace( '<!--INDEXES_HERE-->', index_toc);
with open(os.path.join(root_dir,WEBIFY_INDEX), "w") as text_file:
    text_file.write(output)

