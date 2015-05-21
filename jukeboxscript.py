#!/usr/bin/env python
# shebang for unix-like shells... or type 'python jukeboxscript.py'

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
from xml.sax.saxutils import unescape
import urllib

def PrintHelp():
    print "\n\n" + sys.argv[0] + " /media/path [template | /path2/template]"
    print "Make web pages to play HTML5 compatible audio formats.\n"
    print "/media/path:\tPath to media to make web UI for.\n"
    print "template:\tWhich template to use.\n"
    print "/path2/template:Template in some other folder\n"
    sys.exit(1)

if 1 >= len(sys.argv):
    PrintHelp();

root_dir = os.path.abspath(sys.argv[1])

# Where is this script
SCRIPT_ROOT = os.path.join( os.path.dirname(os.path.realpath(sys.argv[0])), 'templates' );

# Fallback location to get template files
SCRIPT_TEMPLATES = SCRIPT_TEMPLATES_DEFAULT=os.path.join(SCRIPT_ROOT, 'default')

# Where to look for the script templates
if 3 <= len(sys.argv):
    SCRIPT_TEMPLATES = os.path.join(SCRIPT_ROOT, sys.argv[2])
    
    if not os.path.isdir(SCRIPT_TEMPLATES) :
        SCRIPT_TEMPLATES = sys.argv[2]
    
    if not os.path.isdir(SCRIPT_TEMPLATES) :
        print SCRIPT_TEMPLATES + " does not exist."
        PrintHelp()

# What to call the media player files
WEBIFY_PLAYER_INDEX="Jukebox.html"

# What to call the index/table of contents
WEBIFY_INDEX="index.html"

# List of matchable files
FILE_TYPES=['.mp3','.ogg']

# File to suck css out of (exported to be findable in backquotes)
CSS_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, "template.css")
if not os.path.isfile(CSS_TEMPLATE_FILE):
    print CSS_TEMPLATE_FILE + " not found; using default..."
    CSS_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES_DEFAULT, "template.css")

# Cache CSS template
with open (CSS_TEMPLATE_FILE, "r") as myfile:
    CSS_TEMPLATE=myfile.read()

# Which template to use 
PLAYER_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, "audio_template.html")
if not os.path.isfile(PLAYER_TEMPLATE_FILE):
    print PLAYER_TEMPLATE_FILE + " not found; using default..."
    PLAYER_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES_DEFAULT, "audio_template.html")

# Cache player template
with open (PLAYER_TEMPLATE_FILE, "r") as myfile:
    PLAYER_TEMPLATE=myfile.read()

# Find and cache a copy of media file with thumbnail template
INDEX_FILE_MATCH=re.search('<!--INDEX_FILE(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL) 
INDEX_FILE=INDEX_FILE_MATCH.group(1)

# Which template to use 
INDEX_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, "index_template.html")
if not os.path.isfile(INDEX_TEMPLATE_FILE):
    print INDEX_TEMPLATE_FILE + " not found; using default..."
    INDEX_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES_DEFAULT, "index_template.html")

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

# List of various play list formats I could maybe find content in.
PLAY_LISTS=['.asx','.aimppl','.bio','.fpl','.kpl','.m3u','.m3u8','.pla','.plc','.pls','.plist','.smil','.txt','.vlc','.wpl','.xml','.xpl','.xspf','.zpl']

print( "\nCrawling folders in %s..." % (root_dir) )

#
# Iterate folders & files
#
all_play_lists=[]
all_media_folders=[]
all_media_files={}
index_toc_small=[]
playlist_toc_small=[]
need_jpeg= [];
index_toc=[]

for root, dirs, files in os.walk(root_dir):
    files = [f for f in files if not f[0] == '.']
    dirs[:] = [d for d in dirs if not d[0] == '.']

    # Bake some details about this folder
    root = os.path.abspath(root);
    folder_path, folder_name = os.path.split(root)
    folder_relative = os.path.relpath(root,root_dir)
    folder_curr = os.path.relpath(root,root_dir)
    folder_curr_escaped = os.path.join(folder_curr,WEBIFY_PLAYER_INDEX)
    folder_curr_escaped = urllib.quote(folder_curr_escaped.replace('\\', '/')) # Fix any Windows backslashes
    folder_name_escaped = escape(folder_name)
    if '.' == folder_relative:
        folder_depth = 0;
    else:
        folder_depth = 1;
    folder_depth = folder_depth+len(os.path.relpath(root, root_dir).split(os.sep))-1
    folder_depth = LEFT_PADDING + (folder_depth*FOLDER_DEPTH)

    # How many media files in this folder?
    totalFiles = 0

    # Record folder for left box index/TOC
    small_output = str(INDEX_SMALL)
    small_output = small_output.replace( 'FOLDER_TITLE', folder_name_escaped)
    small_output_style = 'padding-left:' + str(folder_depth) + 'px;'

    playlist=""
    index_toc_pass=""

    print "    " + folder_relative
    sys.stdout.flush()

    for relPath in sorted(files):

        # Skip files that aren't playable
        fullPath = os.path.join(root, relPath)
        fileName, fileExtension = os.path.splitext(relPath)
        if fileExtension.lower() in FILE_TYPES:

            # Keep track for trivia
            all_media_files[fileName] = fullPath;
            
            # Bake some details about this file
            media_path = os.path.relpath(fullPath,root)
            media_path_escaped = urllib.quote(media_path.replace('\\', '/')) # Fix any Windows backslashes
            filename_title_escaped=escape(fileName)
            
            # Emit elements for media player
            pathcurr=str(INDEX_FILE)
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
            index_toc_pass = index_toc_pass + pathcurr
            
            totalFiles = totalFiles + 1
            
        elif fileExtension.lower() in PLAY_LISTS:
            # We can't search for play list contents, until we have all files
            all_play_lists.append( fullPath )
    
    if 0 != totalFiles:
        # Record folder for big folder+file TOC
        output = str(INDEX_TOC_FOLDER)
        output = output.replace( 'FOLDER_TITLE', folder_name_escaped)
        output = output.replace( 'FOLDER_PATH',  folder_curr_escaped)
        output = output.replace( 'FOLDER_STYLE', '')
        index_toc.append( (root, output + index_toc_pass) );

        # Manufacture a VideoPlayer.html for folder
        folder_path, folder_name=os.path.split(root)
        output = str(PLAYER_TEMPLATE)
        output = output.replace( 'TITLE_TEXT', escape(folder_name))
        output = output.replace( '/*INSERT_CSS_HERE*/', CSS_TEMPLATE)
        output = output.replace( '<!--INDEXES_HERE-->', playlist)
        with open(os.path.join(root,WEBIFY_PLAYER_INDEX), "w") as text_file:
            text_file.write(output)

        all_media_folders.append(root)
        small_output = small_output.replace( 'FOLDER_PATH',  folder_curr_escaped)
        small_output = small_output.replace( 'FOLDER_STYLE', small_output_style )
        index_toc_small.append( (root,small_output) );

    else:
        # Record dead link folder for left box index/TOC
        small_output = small_output.replace( 'FOLDER_PATH', '')
        small_output = small_output.replace( 'FOLDER_STYLE', small_output_style + ' pointer-events: none; opacity: 0.75;' )
        index_toc_small.append( (root,small_output) );

# Manufacture index.html for entire run of folders... if there were any with media in them
if 0 != len(all_media_folders):
    
    # Import and generate play list content, evil, brute-force style
    # The strength is that it works for almost anything.
    # The weakness is that identical file names in different paths are 'the same'
    # This will be a bit slow, but will import virtually anything you throw at it that's based on text (m3u/xml-based/etc.)
    # The results of 'find', 'ls' or or 'dir /s /b' or 'dir /b' will all work fine with this 
    if 0 != len(all_play_lists):
        print "\nSearching Play List Files..."
        sys.stdout.flush()
        for playlist_file in all_play_lists:
            print "    "+playlist_file;
            sys.stdout.flush()

            # We want the text all lower-case, with forward-slashes, for matching, no encoding/escaping
            with open (playlist_file, "r") as myfile:
                playlist_curr=myfile.read()
                
            # Eat XML &entities;
            playlist_curr = unescape(playlist_curr)

            # Lower-case, no backslashes in paths
            playlist_curr = playlist_curr.lower().replace('\\', '/')
            
            # At this point, our image of the play list is utterly ruined, except as something to search 

            files = []

            # Treat play list file as raw text, and look for literal matches of file names that we have.
            for filename, path in all_media_files.iteritems():
                # Stick the '/' and '.' on (but not extension), to set the 'end' of the file, in our dirty searches
                if -1 != playlist_curr.find( '/'+filename.lower()+'.' ):
                    files.append( (filename, path) )

            # We found files in the play list
            if 0 != len(files):
                uniquefiles = set(files)
                sorted_uniquefiles = sorted(uniquefiles)
    
                playlist = ""
    
                # Make play list items from the found files
                for fileName, fullPath in sorted_uniquefiles:
    
                    media_path = os.path.relpath(fullPath,root_dir)
                    media_path_escaped = urllib.quote(media_path.replace('\\', '/')) # Fix any Windows backslashes
                    filename_title_escaped=escape(fileName)
                    pathcurr=str(INDEX_FILE)
                    pathcurr = pathcurr.replace( 'MEDIA_TITLE', filename_title_escaped)
                    pathcurr = pathcurr.replace( 'MEDIA_PATH', media_path_escaped)
                    pathcurr = pathcurr.replace( 'FILE_STYLE', '')
                    playlist = playlist + pathcurr
                    
                # Make the player
                fileName, fileExtension = os.path.splitext(playlist_file)
                folder_path, fileName = os.path.split(fileName)
                file_name_escaped = escape(fileName)
                output = str(PLAYER_TEMPLATE)
                output = output.replace( 'TITLE_TEXT', file_name_escaped)
                output = output.replace( '/*INSERT_CSS_HERE*/', CSS_TEMPLATE)
                output = output.replace( '<!--INDEXES_HERE-->', playlist)
                file_path=os.path.join(root_dir,fileName)+'.html'
                with open(file_path, "w") as text_file:
                    text_file.write(output)
                file_path_escaped = os.path.relpath(file_path,root_dir)
                file_path_escaped = urllib.quote(file_path_escaped.replace('\\', '/')) # Fix any Windows backslashes
                small_output = str(INDEX_SMALL)
                small_output = small_output.replace( 'FOLDER_TITLE', file_name_escaped)
                small_output_style = 'padding-left:' + str(LEFT_PADDING+FOLDER_DEPTH) + 'px;'
                small_output = small_output.replace( 'FOLDER_PATH', file_path_escaped)
                small_output = small_output.replace( 'FOLDER_STYLE', small_output_style )
                playlist_toc_small.append( (fileName,small_output) );

    print "\nBuilding index..."
    sys.stdout.flush()
    folder_path, folder_name = os.path.split(root_dir)
    folder_name_escaped = escape(folder_name)
    output = str(INDEX_TEMPLATE)
    output = output.replace( 'TITLE_TEXT', folder_name_escaped )
    output = output.replace( '/*INSERT_CSS_HERE*/', CSS_TEMPLATE)
    
    # Copy table of contents in, sorted.
    big_indexes=''
    for indexPath, item in sorted(index_toc):
        big_indexes = big_indexes + item + '\n'
    output = output.replace( '<!--INDEXES_HERE-->', big_indexes)

    # Add the small index list; Only emit index paths that lead to media 
    small_indexes=''
    
    if 0 != len(playlist_toc_small):
        small_indexes = small_indexes + "Play Lists:"
                        
    for indexPath, item in sorted(playlist_toc_small):
        small_indexes = small_indexes + item + '\n'

    if 0 != len(playlist_toc_small):
        small_indexes = small_indexes + "<br/><br/>Folders:"

    for indexPath, item in sorted(index_toc_small):
        for apath in all_media_folders:
            if 0 == apath.find(indexPath):
                small_indexes = small_indexes + item + '\n'
                break;
    output = output.replace( '<!--FOLDERS_HERE-->', small_indexes)

    # Write index file
    with open(os.path.join(root_dir,WEBIFY_INDEX), "w") as text_file:
        text_file.write(output)
            
    print "\nMade %d folders with %d unique files.\n" %(len(all_media_folders),len(all_media_files))
else:
    print "\nNo media found.  Nothing written.\n"

