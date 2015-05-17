#!/usr/bin/env python
# shebang for unix-like shells... Windows users type 'python videowebscript.py'

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
from xml.sax.saxutils import escape
import urllib

root_dir = os.path.normpath(sys.argv[1])
need_jpeg= []

# What to call the video player files
WEBIFY_PLAYER_INDEX="VideoPlayer.html"

# What to call the index/table of contents
WEBIFY_INDEX="index.html"

# List of matchable files
FILE_TYPES=['.mp4','.m4v','.m4p','.m4r','.3gp','.3g2']

# The folder with the templates to generate from, relative to this script
TEMPLATE_PATH="templates/VideoWebScript/kiosk"

# Where is this script
SCRIPT_ROOT = os.path.dirname(os.path.realpath(sys.argv[0]))

# Where to look for the script templates
SCRIPT_TEMPLATES = os.path.join(SCRIPT_ROOT, TEMPLATE_PATH)

# What our thumbnailer is called.  Dike out if you don't want thumbnails.
THUMBNAILER='ffmpegthumbnailer'

# Thumbnail image width (height determined by video size)
THUMB_SIZE=240

# Check if the specifiec thumbnailer exists.  Enables thumbnail generation.
HAVE_THUMBNAILER = distutils.spawn.find_executable(THUMBNAILER) is not None

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

# Find and cache a copy of media file without thumbnail template
INDEX_FILE_NOTHUMB_MATCH=re.search('<!--INDEX_FILE_NOTHUMB(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_FILE_NOTHUMB=INDEX_FILE_NOTHUMB_MATCH.group(1)

# Which template to use 
INDEX_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, "index_template.html")

# Cache index template
with open (INDEX_TEMPLATE_FILE, "r") as myfile:
    INDEX_TEMPLATE=myfile.read()

# Folder index list (left side of template file)
INDEX_SMALL_MATCH = re.search('<!--INDEX_SMALL(.*?)-->', INDEX_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_SMALL = INDEX_SMALL_MATCH.group(1)

# Folder index (right side of template file)
INDEX_TOC_FOLDER_MATCH=re.search('<!--INDEX_TOC_FOLDER(.*?)-->', INDEX_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_TOC_FOLDER = INDEX_TOC_FOLDER_MATCH.group(1)

# Play file index   
INDEX_TOC_FILE_MATCH=re.search('<!--INDEX_TOC_FILE(.*?)-->', INDEX_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_TOC_FILE = INDEX_TOC_FILE_MATCH.group(1)

# File/folder left padding
LEFT_PADDING = 4

# Offset for folder depths in TOC file
FOLDER_DEPTH = 16


print( "\nCrawling folders in %s..." % (root_dir) )

#
# Iterate folders & files
#
all_paths_with_media=[]
total_media_count = 0
index_toc_small=[]
index_toc=""

for root, dirs, files in sorted(os.walk(root_dir)):
    files.sort()

    # Bake some details about this folder
    folder_path, folder_name = os.path.split(root)
    folder_relative = os.path.relpath(root,root_dir)
    folder_curr = os.path.relpath(root,root_dir)
    folder_curr_escaped = os.path.join(folder_curr,WEBIFY_PLAYER_INDEX)
    folder_curr_escaped = urllib.quote(folder_curr_escaped.replace('\\', '/')) # Fix any Windows backslashes
    folder_name_escaped = escape(folder_name)
    folder_depth = len(os.path.relpath(root, root_dir).split(os.sep))-1
    if '.' != folder_curr:
        folder_depth = folder_depth + 1;
    folder_depth = LEFT_PADDING + (folder_depth*FOLDER_DEPTH)

    # How many media files in this folder?
    totalFiles = 0
    for relPath in files:
        dummy,extCurr = os.path.splitext(relPath)
        if extCurr.lower() in FILE_TYPES:
            totalFiles = totalFiles + 1

    # Record folder for left box index/TOC
    small_output = str(INDEX_SMALL)
    small_output = small_output.replace( 'FOLDER_TITLE', folder_name_escaped)
    small_output_style = 'padding-left:' + str(folder_depth) + 'px;'

    # A folder with content to play
    if 0 != totalFiles:

        # Record live link folder for left box index/TOC
        all_paths_with_media.append(root)
        small_output = small_output.replace( 'FOLDER_PATH',  folder_curr_escaped)
        small_output = small_output.replace( 'FOLDER_STYLE', small_output_style )
        index_toc_small.append( (root,small_output) );

        playlist=""

        print '    '+folder_relative
        sys.stdout.flush()

        # Record folder for big folder+file TOC
        output = str(INDEX_TOC_FOLDER)
        output = output.replace( 'FOLDER_TITLE', folder_name_escaped)
        output = output.replace( 'FOLDER_PATH',  folder_curr_escaped)
        output = output.replace( 'FOLDER_STYLE', '')
        index_toc = index_toc + output

        for relPath in files:

            # Skip files that aren't playable
            fileName, fileExtension = os.path.splitext(relPath)
            fullPath = os.path.join(root, fileName) + fileExtension
            dummy,extCurr = os.path.splitext(relPath)
            if extCurr.lower() in FILE_TYPES:
                # Keep track for trivia
                total_media_count = total_media_count + 1;
                
                # Bake some details about this file
                media_path = os.path.relpath(fullPath,root)
                media_path_escaped = urllib.quote(media_path.replace('\\', '/')) # Fix any Windows backslashes
                filename_title_escaped=escape(fileName)
                pathcurr=str(INDEX_FILE)
                
                if HAVE_THUMBNAILER:
                    # We should have a jpg file, named the same as the playable file
                    jpegName = fileName + '.jpg'
                    jpegPath = os.path.join(root, jpegName)
                    filename_jpeg_escaped=urllib.quote(os.path.relpath(jpegPath,root))
                    if jpegName not in files:
                        need_jpeg.append( (fullPath,jpegPath) )
                    pathcurr=re.sub('MEDIA_IMAGE',filename_jpeg_escaped,pathcurr)
                else:
                    # We don't have a thumbnailer.
                    pathcurr=str(INDEX_FILE_NOTHUMB)

                # Emit elements for video player
                pathcurr = pathcurr.replace( 'MEDIA_PATH', media_path_escaped)
                pathcurr = pathcurr.replace( 'FILE_STYLE', '')
                pathcurr = pathcurr.replace( 'MEDIA_TITLE', filename_title_escaped)
                playlist = playlist + pathcurr

                # Emit elements for index navigation player
                pathcurr = str(INDEX_TOC_FILE)
                pathcurr_escaped = os.path.join(folder_curr,WEBIFY_PLAYER_INDEX).replace('\\', '/')
                pathcurr_escaped = urllib.quote(pathcurr_escaped)+'?'+media_path_escaped
                pathcurr = pathcurr.replace( 'MEDIA_PATH', pathcurr_escaped)
                pathcurr = pathcurr.replace( 'FILE_STYLE', '')
                pathcurr = pathcurr.replace( 'MEDIA_TITLE', filename_title_escaped)
                index_toc = index_toc + pathcurr
                
        # Manufacture a VideoPlayer.html for folder
        folder_path, folder_name=os.path.split(root)
        output = str(PLAYER_TEMPLATE)
        output = output.replace( 'TITLE_TEXT', escape(folder_name))
        output = output.replace( '/*INSERT_CSS_HERE*/', CSS_TEMPLATE)
        output = output.replace( '<!--INDEXES_HERE-->', playlist)
        with open(os.path.join(root,WEBIFY_PLAYER_INDEX), "w") as text_file:
            text_file.write(output)
            
    else:
        # Record dead link folder for left box index/TOC
        small_output = small_output.replace( 'FOLDER_PATH', '')
        small_output = small_output.replace( 'FOLDER_STYLE', small_output_style + ' pointer-events: none; opacity: 0.75;' )
        index_toc_small.append( (root,small_output) );


# Manufacture index.html for entire run of folders, if there were any
if 0 != len(all_paths_with_media):
    print "\nBuilding index..."
    sys.stdout.flush()
    
    # Build index file
    output = str(INDEX_TEMPLATE)
    output = output.replace( '/*INSERT_CSS_HERE*/', CSS_TEMPLATE)
    output = output.replace( '<!--INDEXES_HERE-->', index_toc)
    
    # Add the small index list; Only emit index paths that lead to media 
    small_indexes=''
    for indexPath, item in sorted(index_toc_small):
        for apath in all_paths_with_media:
            if 0 == apath.find(indexPath):
                small_indexes = small_indexes + item + '\n'
                break;
    output = output.replace( '<!--FOLDERS_HERE-->', small_indexes)
    
    # Write index file
    with open(os.path.join(root_dir,WEBIFY_INDEX), "w") as text_file:
        text_file.write(output)

    # Build thumbnails from files that need them.
    if HAVE_THUMBNAILER:
        print "\nMaking thumbnails..."
        sys.stdout.flush()
        for needs in need_jpeg:
            print("Making jpeg from: " + needs[0])
            call([ THUMBNAILER, '-t', str(random.randrange(25, 75))+'%', '-s', str(THUMB_SIZE), '-i', needs[0], '-o', needs[1] ])
            
    print "\nMade %d folders with %d files.\n" %(len(all_paths_with_media),total_media_count)
else:
    print "\nNo media found.  Nothing written.\n"
