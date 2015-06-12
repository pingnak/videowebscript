#!/usr/bin/env python
# -*- coding: utf-8 -*-

#
# The python version.
#
# This will work basically the same as the shell version, only less sketchy
# across platforms.  You may need to install python, but once it's there, it 
# should be pretty consistent.
#

import os
import sys
import re
import random
import urllib
import string
from xml.sax.saxutils import escape
from xml.sax.saxutils import unescape
import unicodedata
from subprocess import call
import distutils.spawn

def PrintHelp():
    print "\n\n" + sys.argv[0] + " /media/path [template | /path2/template]"
    print "Makes a web page to play HTML5 compatible video formats.\n"
    print "/media/path:\tPath to media to make web UI for.\n"
    print "template:\tWhich template to use.\n"
    print "/path2/template:Template in some other folder\n"
    sys.exit(1)

# I'd like to use 'natsort', but installing dependencies is a problem.
regex_strip_punctuation = re.compile('[%s]' % re.escape(string.punctuation))
def decompose(comptext):
    "Break input down into a string, for comparison."
    ret=''
    # Just deal with the first element of tuple, if it's not just a string
    if isinstance(comptext, tuple):
        comptext = comptext[0]
    comptext = ''.join(comptext)
    # Break up by numbers, include numbers
    comptext = re.split( '([0-9]+)', comptext.lower() )
    # Pad numbers with leading zeroes, rip out any puntuation, re-assemble string
    for ss in comptext:
        if 0 != len(ss) and ss[0].isdigit():
            ret = ret + "%010ld"%long(ss)
        else:
            ret = ret + regex_strip_punctuation.sub('', ss)
    return ret

def compare_natural(item1, item2):
    "Compare two strings as 'natural' strings."
    s1=decompose(item1)
    s2=decompose(item2)
    if s1 < s2:
        return -1;
    if s1 > s2:
        return 1;
    return 0;

def compare_natural_filename(item1, item2):
    "Compare two path strings as 'natural' strings."
    if isinstance(item1, tuple):
        item1 = item1[0]
    if isinstance(item2, tuple):
        item1 = item2[0]
    path,item1=os.path.split(item1)
    item1, ext = os.path.splitext(item1)
    path,item2=os.path.split(item2)
    item2, ext = os.path.splitext(item2)
    return compare_natural(item1, item2)

if 1 >= len(sys.argv):
    PrintHelp()

root_dir = os.path.abspath(sys.argv[1])

# Where is this script
SCRIPT_ROOT = os.path.join( os.path.dirname(os.path.realpath(sys.argv[0])), 'templates' );

# Fallback location to get template files
SCRIPT_TEMPLATES = SCRIPT_TEMPLATES_DEFAULT = os.path.join(SCRIPT_ROOT, 'default')

if 3 <= len(sys.argv):
    SCRIPT_TEMPLATES = os.path.join( SCRIPT_ROOT, sys.argv[2] )
    
    if not os.path.isdir(SCRIPT_TEMPLATES) :
        SCRIPT_TEMPLATES = sys.argv[2]
    
    if not os.path.isdir(SCRIPT_TEMPLATES) :
        print SCRIPT_TEMPLATES + " does not exist."
        PrintHelp()

# What to call the video player files
WEBIFY_PLAYER_INDEX="VideoPlayer.html"

# What to call the index/table of contents
WEBIFY_INDEX="index.html"

# List of matchable files
FILE_TYPES=['.mp4','.m4v','.m4p','.m4r','.3gp','.3g2']

# What our thumbnailer is called.  Dike out if you don't want thumbnails.
THUMBNAILER='ffmpegthumbnailer'

# Thumbnail image width (height determined by video size)
THUMB_SIZE=240

# Check if the specifiec thumbnailer exists.  Enables thumbnail generation.
HAVE_THUMBNAILER = distutils.spawn.find_executable(THUMBNAILER) is not None

# File to suck css out of (exported to be findable in backquotes)
CSS_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, "template.css")
if not os.path.isfile(CSS_TEMPLATE_FILE):
    CSS_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES_DEFAULT, "template.css")

# Cache CSS template
with open (CSS_TEMPLATE_FILE, "r") as myfile:
    CSS_TEMPLATE=myfile.read()

# Which template to use 
PLAYER_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, "video_template.html")
if not os.path.isfile(PLAYER_TEMPLATE_FILE):
    PLAYER_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES_DEFAULT, "video_template.html")

# Cache player template
with open (PLAYER_TEMPLATE_FILE, "r") as myfile:
    PLAYER_TEMPLATE=myfile.read()

# Find and cache a copy of media file template
INDEX_FOLDER_MATCH=re.search('<!--INDEX_FOLDER(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL) 
INDEX_FOLDER=INDEX_FOLDER_MATCH.group(1)

# Find and cache a copy of folder template
INDEX_PLAYLIST_MATCH=re.search('<!--INDEX_PLAYLIST(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL) 
INDEX_PLAYLIST=INDEX_PLAYLIST_MATCH.group(1)

# Find index playlist_section completion tag
INDEX_FILES_BEGIN_MATCH=re.search('<!--INDEX_FILES_BEGIN(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_FILES_BEGIN=INDEX_FILES_BEGIN_MATCH.group(1)

# Find and cache a copy of media file with thumbnail template
INDEX_FILE_MATCH=re.search('<!--INDEX_FILE_THUMB(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL) 
INDEX_FILE=INDEX_FILE_MATCH.group(1)

# Find and cache a copy of media file without thumbnail template
INDEX_FILE_NOTHUMB_MATCH=re.search('<!--INDEX_FILE_NOTHUMB(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_FILE_NOTHUMB=INDEX_FILE_NOTHUMB_MATCH.group(1)

# Find index playlist_section completion tag
INDEX_FILES_END_MATCH=re.search('<!--INDEX_FILES_END(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_FILES_END=INDEX_FILES_END_MATCH.group(1)

# File/folder left padding
LEFT_PADDING = 4

# Offset for folder depths in TOC file
FOLDER_DEPTH = 16
   
print( "\nCrawling folders in %s..." % (root_dir) )

#
# Iterate folders & files
#
all_media_folders=[]
all_play_lists=[]
total_media_count = 0
index_toc=[]
player_toc=[]
need_jpeg=[]
have_jpeg={}

for root, dirs, files in os.walk(root_dir):
    
    # Bake some details about this folder
    root = os.path.abspath(root);
    folder_path, folder_name = os.path.split(root)
    
    dirs[:] = [d for d in dirs if not d[0] == '.']

    folder_relative = os.path.relpath(root,root_dir)
    print '    '+folder_relative
    sys.stdout.flush()

    playlist=""

    folder_curr = os.path.relpath(root,root_dir)
    folder_curr_escaped = os.path.join(folder_curr,WEBIFY_PLAYER_INDEX)
    folder_curr_escaped = urllib.quote(folder_curr_escaped.replace('\\', '/')) # Fix any Windows backslashes
    folder_name_escaped = escape(folder_name)
    if '.' == folder_relative:
        folder_depth = 0;
    else:
        folder_depth = 1;
    folder_depth = folder_depth + len(os.path.relpath(root, root_dir).split(os.sep))-1
    folder_depth = LEFT_PADDING + (folder_depth*FOLDER_DEPTH)

    # A folder with content to play

    # Record live link folder for left box index/TOC
    all_media_folders.append(root)

    totalFiles = 0;
    for relPath in sorted(files,compare_natural_filename):

        # Exclude hidden files
        if '.' == relPath[0]:
            continue;

        # Skip files that aren't playable
        fileName, fileExtension = os.path.splitext(relPath)
        fullPath = os.path.join(root, relPath)
        fullPathNoExt,extCurr = os.path.splitext(fullPath)
        extCurr = extCurr.lower();
        if extCurr in FILE_TYPES:
            
            totalFiles = totalFiles + 1;
            
            # Keep track for trivia
            total_media_count = total_media_count + 1;
            
            # Bake some details about this file

            media_path = os.path.relpath(fullPath,root_dir)
            media_path_escaped = urllib.quote(media_path.replace('\\', '/')) # Fix any Windows backslashes
            #media_path_escaped = media_path.encode("ascii", "ignore")
            #media_path_escaped = unicodedata.normalize('NFKD',unicode(media_path,"ISO-8859-1")).encode("utf8","ignore")
            filename_title_escaped=escape(fileName)
            
            if HAVE_THUMBNAILER:
                # We should have a jpg file, named the same as the playable file
                jpegName = fileName + '.jpg'
                jpegPath = fullPathNoExt + '.jpg'
                filename_jpeg_escaped=urllib.quote(os.path.relpath(jpegPath,root_dir))
                need_jpeg.append( (fullPath,jpegPath) )
                pathcurr=str(INDEX_FILE)
                pathcurr=re.sub('MEDIA_IMAGE',filename_jpeg_escaped,pathcurr)
            else:
                # We don't have a thumbnailer.
                pathcurr=str(INDEX_FILE_NOTHUMB)

            # Emit elements for video player
            pathcurr = pathcurr.replace( 'MEDIA_PATH', media_path_escaped)
            pathcurr = pathcurr.replace( 'MEDIA_TITLE', filename_title_escaped)
            pathcurr = pathcurr.replace( 'FILE_STYLE', '')
            playlist = playlist + pathcurr

        if '.jpg' == extCurr:
            # Record existence of a jpeg file we found
            have_jpeg[fullPath] = True
    
    # Record folder for big folder+file TOC
    output = str(INDEX_FOLDER)
    if '.' == folder_relative:
        folder_relative = '___'+folder_name;
    FOLDER_ID = re.sub(r'[^a-zA-Z0-9]', '_', folder_relative )
    output = output.replace( 'FOLDER_ID', FOLDER_ID)
    output = output.replace( 'FOLDER_NAME', folder_name_escaped)
    small_output_style = 'padding-left:' + str(folder_depth) + 'pt;'
    if 0 == totalFiles:
        small_output_style = small_output_style + ' pointer-events: none; opacity: 0.75;'
    output = output.replace( 'FOLDER_STYLE', small_output_style )
    index_toc.append( (root, output) );

    if 0 != totalFiles:
       
        # Manufacture the play list for this folder
        output = str(INDEX_FILES_BEGIN)
        output = output.replace( 'FOLDER_ID', FOLDER_ID)
        output = output.replace( 'FOLDER_STYLE', '' )
        output = output.replace( 'FOLDER_NAME', folder_name_escaped)
        output = output + playlist + INDEX_FILES_END;

        # Add accumulated indexes to list, to defer folder sort
        player_toc.append((folder_curr,output))

# Manufacture index.html for entire run of folders, if there were any
if 0 != len(all_media_folders):
    print "\nBuilding index..."
    sys.stdout.flush()
    
    # Build index file

    folder_path, folder_name = os.path.split(root_dir)
    folder_name_escaped = escape(folder_name)
    output = str(PLAYER_TEMPLATE)
    output = output.replace( '/*INSERT_CSS_HERE*/', CSS_TEMPLATE )
    output = output.replace( 'TITLE_TEXT', folder_name_escaped )
    output = output.replace( 'THUMB_SIZE', str(THUMB_SIZE) )

    # Copy table of contents in, sorted.
    big_indexes=''
    for indexPath, item in sorted(index_toc,compare_natural):
        big_indexes = big_indexes + item + '\n'
    output = output.replace( '<!--INDEX_FOLDERS_HERE-->', big_indexes)
    
    # Add the small index list; Only emit index paths that lead to media 
    indexes=''
    for indexPath, item in sorted(player_toc,compare_natural):
        indexes = indexes + item

    output = output.replace( '<!--INDEX_FILES_HERE-->', indexes)
    
    # Write index file
    with open(os.path.join(root_dir,WEBIFY_INDEX), "w") as text_file:
        text_file.write(output)

    # Build thumbnails from files that need them.
    # Deferred to the end, because it usually isn't needed
    if HAVE_THUMBNAILER:
        print "\nMaking thumbnails..."
        sys.stdout.flush()
        for needs in need_jpeg:
            if needs[1] not in have_jpeg:
                print "Making " + needs[1]
                call([ THUMBNAILER, '-t', str(random.randrange(25, 75))+'%', '-s', str(THUMB_SIZE), '-i', needs[0], '-o', needs[1] ])
            
    print "\nMade %d folders with %d files.\n" %(len(all_media_folders),total_media_count)
else:
    print "\nNo media found.  Nothing written.\n"
