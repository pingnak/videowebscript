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

# What to call the index/table of contents
WEBIFY_INDEX="index.html"

# Template file to make WEBIFY_INDEX from
WEBIFY_TEMPLATE="video_template.html"

# Common css data for templates
CSS_TEMPLATE="template.css"

# List of matchable media files
MEDIA_TYPES=['.mp4','.m4v','.m4p','.m4r','.3gp','.3g2','.ogg','.ogv']

# List of various play list formats I could maybe find content in.
PLAY_LISTS=['.asx','.aimppl','.bio','.fpl','.kpl','.m3u','.m3u8','.pla','.plc','.pls','.plist','.smil','.txt','.vlc','.wpl','.xml','.xpl','.xspf','.zpl']

# What our thumbnailer is called.  Dike out if you don't want thumbnails.
THUMBNAILER='ffmpegthumbnailer'

# Thumbnail image width (height determined by video size)
THUMB_SIZE=240

# Reject small (blank/blurred) jpeg files.  Adjust if you change 'THUMB_SIZE'
MIN_THUMB_FILE_SIZE=4096

# How many times to try to make a 'big enough' thumbnail, before giving up
THUMB_TRIES=3

# Check if the specifiec thumbnailer exists.  Enables thumbnail generation.
HAVE_THUMBNAILER = distutils.spawn.find_executable(THUMBNAILER) is not None

# File extension of thumbnails
THUMBNAIL_EXTENSION='.jpg'

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
    # Break up by numbers, include numbers in list
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
        return -1
    if s1 > s2:
        return 1
    return 0

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

# Where this script exists
root_dir = os.path.abspath(sys.argv[1])

# Where are the script templates, relative to script 
SCRIPT_ROOT = os.path.join( os.path.dirname(os.path.realpath(sys.argv[0])), 'templates' )

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

# File to suck css out of (exported to be findable in backquotes)
CSS_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, CSS_TEMPLATE)
if not os.path.isfile(CSS_TEMPLATE_FILE):
    print CSS_TEMPLATE_FILE + " not found; using default..."
    CSS_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES_DEFAULT, CSS_TEMPLATE)

# Cache CSS template
with open (CSS_TEMPLATE_FILE, "r") as myfile:
    CSS_TEMPLATE=myfile.read()

# Which template to use 
PLAYER_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, WEBIFY_TEMPLATE)
if not os.path.isfile(PLAYER_TEMPLATE_FILE):
    print PLAYER_TEMPLATE_FILE + " not found; using default..."
    PLAYER_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES_DEFAULT, WEBIFY_TEMPLATE)

# Cache player template
with open (PLAYER_TEMPLATE_FILE, "r") as myfile:
    PLAYER_TEMPLATE=myfile.read()

# Find and cache a copy of folder template
INDEX_FOLDER_MATCH=re.search('<!--INDEX_FOLDER(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL) 
INDEX_FOLDER=INDEX_FOLDER_MATCH.group(1)

# Find and cache a copy of folder template
INDEX_PLAYLIST_MATCH=re.search('<!--INDEX_PLAYLIST(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL) 
INDEX_PLAYLIST=INDEX_PLAYLIST_MATCH.group(1)

# Find index playlist_section completion tag
INDEX_FILES_BEGIN_MATCH=re.search('<!--INDEX_FILES_BEGIN(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_FILES_BEGIN=INDEX_FILES_BEGIN_MATCH.group(1)

# Find and cache a copy of media file 
INDEX_FILE_MATCH=re.search('<!--INDEX_ITEM_NOTHUMB(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL) 
INDEX_FILE=INDEX_FILE_MATCH.group(1)

# Find and cache a copy of media file 
INDEX_FILE_THUMB_MATCH=re.search('<!--INDEX_ITEM_THUMB(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL) 
INDEX_FILE_THUMB=INDEX_FILE_THUMB_MATCH.group(1)

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
all_folders=[]
all_media_files={}
need_thumb={}
have_thumb={}

total_play_lists=0

# Build a list of folders and their files
for root, dirs, files in os.walk(root_dir):
    # I don't want hidden files/folders.

    # Bake some details about this folder
    root = os.path.abspath(root)
    folder_path, folder_name = os.path.split(root)
    folder_curr = os.path.relpath(root,root_dir)

    # Hidden folders are a bane on NAS
    dirs[:] = [d for d in dirs if not d[0] == '.']

    print "    " + folder_curr

    # How many media files in this folder?
    media_files_this_folder = []

    for relPath in sorted(files,compare_natural_filename):

        file_name, fileExtension = os.path.splitext(relPath)
        if '.' == file_name[0]:
            continue

        fileExtension = fileExtension.lower();

        # Skip files that aren't playable
        fullPath = os.path.join(root, relPath)
        
        if fileExtension in MEDIA_TYPES:

            # Keep track for trivia
            all_media_files[file_name] = fullPath
            media_files_this_folder.append(fullPath)

        elif fileExtension in PLAY_LISTS:
            # We can't search for play list contents, until we have all files
            all_play_lists.append( fullPath )
            
        elif THUMBNAIL_EXTENSION == fileExtension:
            # Record that we have a possible thumbnail to match 
            have_thumb[fullPath] = True
    
    all_folders.append((root,media_files_this_folder))
    if 0 != len(media_files_this_folder):
        all_media_folders.append((root,media_files_this_folder))

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
            print "    "+playlist_file
            sys.stdout.flush()

            # We want the text all lower-case, with forward-slashes, for matching, no encoding/escaping
            with open (playlist_file, "r") as myfile:
                playlist_curr=myfile.read()
                
            # Eat XML &entities
            playlist_curr = unescape(playlist_curr)

            # Lower-case, no backslashes in paths
            playlist_curr = playlist_curr.lower().replace('\\', '/')
            
            # At this point, our image of the play list is utterly ruined, except as something to search 

            files = []

            # Treat play list file as raw text, and look for literal matches of file names that we have.
            for filename, path in all_media_files.iteritems():
                # Stick the '/' and '.' on (but not extension), to set the 'end' of the file, in our dirty searches
                if -1 != playlist_curr.find( '/'+filename.lower()+'.' ) or -1 != playlist_curr.find( '/'+urllib.quote(filename.lower())+'.' ):
                    files.append( (filename, path) )

            # We found files in the play list
            if 0 != len(files):
                total_play_lists = total_play_lists + 1
                uniquefiles = set(files)
                sorted_uniquefiles = sorted(uniquefiles,compare_natural)
    
                playlist = []
    
                # Make play list items from the found files
                for file_name, fullPath in sorted_uniquefiles:
                    playlist.append(fullPath)
                    
                file_name, fileExtension = os.path.splitext(playlist_file)

                all_folders.append((file_name,playlist))

    print "\nBuilding index..."
    sys.stdout.flush()
    folder_path, folder_name = os.path.split(root_dir)
    folder_name_escaped = escape(folder_name)
    output = str(PLAYER_TEMPLATE)
    output = output.replace( '/*INSERT_CSS_HERE*/', CSS_TEMPLATE)
    output = output.replace( 'TITLE_TEXT', folder_name_escaped )
    index_section=""
    playlist_section=""
    all_folders_sorted = sorted(all_folders, compare_natural)
    for folder, files in all_folders_sorted:
        folder_depth = len(os.path.relpath(folder, root_dir).split(os.sep))
        if root_dir == folder:
            folder_depth = 0
        folder_depth = LEFT_PADDING + (folder_depth*FOLDER_DEPTH)
        folder_output_style = 'padding-left:' + str(folder_depth) + 'pt;'

        isPlaylist = not os.path.isdir(folder)
        if isPlaylist:
            index_section_entry = INDEX_PLAYLIST
        else:
            index_section_entry = INDEX_FOLDER

        if 0 == len(files):
            index_section_entry = index_section_entry.replace('FOLDER_STYLE', folder_output_style + ' pointer-events: none; opacity: 0.75;' )
        else:
            index_section_entry = index_section_entry.replace('FOLDER_STYLE', folder_output_style )

        scratch, FOLDER_NAME = os.path.split(folder)
        index_section_entry = index_section_entry.replace( 'FOLDER_NAME', escape(FOLDER_NAME) )
        folder = os.path.relpath(folder,root_dir)
        FOLDER_ID = re.sub(r'[^a-zA-Z0-9]', '_', folder )
        index_section_entry = index_section_entry.replace( 'FOLDER_ID', FOLDER_ID )
        index_section = index_section + index_section_entry
        
        if 0 != len(files):
            playlist_section_folder=INDEX_FILES_BEGIN
            playlist_section_folder = playlist_section_folder.replace( "FOLDER_NAME", FOLDER_NAME )
            playlist_section_folder = playlist_section_folder.replace( "FOLDER_ID", FOLDER_ID )
            playlist_section_folder = playlist_section_folder.replace( "FOLDER_STYLE", '' )
            if isPlaylist:
                playlist_section_folder = playlist_section_folder.replace( "FOLDER_CLASS", 'playlist_page' )
            else:
                playlist_section_folder = playlist_section_folder.replace( "FOLDER_CLASS", 'folder_page' )
            playlist_section += playlist_section_folder
            for file in files:
                
                media_path = os.path.relpath(file,root_dir)
                media_path_escaped = urllib.quote(media_path.replace('\\', '/')) # Fix any Windows backslashes
                #media_path_escaped = media_path.encode("ascii", "ignore")
                #media_path_escaped = unicodedata.normalize('NFKD',unicode(media_path,"ISO-8859-1")).encode("utf8","ignore")
                
                file_path, file_name = os.path.split(file)
                file_name,ext = os.path.splitext(file_name)

                filename_title_escaped=escape(file_name)

                playlist_section_file=INDEX_FILE

                # This is only needed for video, right now; though some audio files have cover art.
                if HAVE_THUMBNAILER:
                    # We should have an image file, named the same as the playable file
                    playlist_section_file=INDEX_FILE_THUMB
                    fullPathNoExt,extCurr = os.path.splitext(file)
                    thumbPath = fullPathNoExt + THUMBNAIL_EXTENSION
                    filename_jpeg_escaped=urllib.quote(os.path.relpath(thumbPath,root_dir))
                    playlist_section_file=playlist_section_file.replace('MEDIA_IMAGE',filename_jpeg_escaped)
                    need_thumb[file] = thumbPath;
                    
                playlist_section_file = playlist_section_file.replace('MEDIA_TITLE', filename_title_escaped ) 
                playlist_section_file = playlist_section_file.replace('MEDIA_PATH',  media_path_escaped )
                playlist_section_file = playlist_section_file.replace('MEDIA_STYLE', '' )
                
                playlist_section = playlist_section + playlist_section_file
            playlist_section = playlist_section + INDEX_FILES_END

    output = output.replace( '<!--INDEX_FOLDERS_HERE-->', index_section)
    output = output.replace( '<!--INDEX_FILES_HERE-->', playlist_section)

    # Write index file
    with open(os.path.join(root_dir,WEBIFY_INDEX), "w") as text_file:
        text_file.write(output)

    # Build thumbnails from files that need them.
    # Deferred to the end, because it usually isn't needed, and it may take a long time if it is
    if HAVE_THUMBNAILER:
        print "\nMaking thumbnails..."
        sys.stdout.flush()
        for needs in need_thumb:
            # If file doesn't exist, or it's 'too small'
            if need_thumb[needs] not in have_thumb: # or MIN_THUMB_FILE_SIZE >= os.stat(need_thumb[needs]).st_size: <-- This last bit can take forever over LAN
                # Try making random frame until one looks big enough to have content
                tries = THUMB_TRIES;
                while 0 < tries:
                    print "Making " + need_thumb[needs]
                    tries = tries - 1
                    call([ THUMBNAILER, '-t', str(random.randrange(25, 75))+'%', '-s', str(THUMB_SIZE), '-i', needs, '-o', need_thumb[needs] ])
                    if os.stat(need_thumb[needs]).st_size >= MIN_THUMB_FILE_SIZE:
                        break

    print "\nMade %d folders and %d play lists with %d unique files.\n" %(len(all_media_folders),total_play_lists,len(all_media_files))
else:
    print "\nNo media found.  Nothing written.\n"

