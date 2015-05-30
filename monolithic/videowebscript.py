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
import string

def PrintHelp():
    print "\n\n" + sys.argv[0] + " /media/path [template | /path2/template]"
    print "Make web pages to play HTML5 compatible video formats.\n"
    print "/media/path:\tPath to media to make web UI for.\n"
    print "template:\tWhich template to use.\n"
    print "/path2/template:Template in some other folder\n"
    sys.exit(1)

# I'd like to use 'natsort', but installing dependencies on ALL operating systems is a problem.
regex_strip_punctuation = re.compile('[%s]' % re.escape(string.punctuation))
def decompose(comptext):
    # Tuples converted to string
    comptext = ''.join(comptext)
    # Break up by numbers, include numbers
    comptext = re.split( '([0-9]+)', comptext.lower() )
    # Pad numbers with leading zeroes, re-assemble
    ret=''
    for ss in comptext:
        if 0 != len(ss) and ss[0].isdigit():
            ret = ret + "%010ld"%long(ss);
        else:
            ret = ret + regex_strip_punctuation.sub('', ss)
    return ret

def compare_natural(item1, item2):
    s1=decompose(item1)
    s2=decompose(item2)
    if s1 < s2:
        return -1;
    if s1 > s2:
        return 1;
    return 0;

def compare_natural_filename(item1, item2):
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

# Find and cache a copy of media file with thumbnail template
INDEX_FILE_MATCH=re.search('<!--INDEX_FILE(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL) 
INDEX_FILE=INDEX_FILE_MATCH.group(1)

# Find and cache a copy of media file without thumbnail template
INDEX_FILE_NOTHUMB_MATCH=re.search('<!--INDEX_FILE_NOTHUMB(.*?)-->', PLAYER_TEMPLATE, re.MULTILINE|re.DOTALL)
INDEX_FILE_NOTHUMB=INDEX_FILE_NOTHUMB_MATCH.group(1)

# Which template to use 
INDEX_TEMPLATE_FILE=os.path.join(SCRIPT_TEMPLATES, "index_template.html")
if not os.path.isfile(INDEX_TEMPLATE_FILE):
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
   
print( "\nCrawling folders in %s..." % (root_dir) )

#
# Iterate folders & files
#
all_paths_with_media=[]
total_media_count = 0
index_toc_small=[]
index_toc=[]
need_jpeg=[]
have_jpeg={}

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
    folder_depth = folder_depth + len(os.path.relpath(root, root_dir).split(os.sep))-1
    folder_depth = LEFT_PADDING + (folder_depth*FOLDER_DEPTH)

    # A folder with content to play

    # Record live link folder for left box index/TOC
    all_paths_with_media.append(root)

    playlist=""
    index_list=""

    print '    '+folder_relative
    sys.stdout.flush()

    # Record folder for big folder+file TOC
    output = str(INDEX_TOC_FOLDER)
    output = output.replace( 'FOLDER_TITLE', folder_name_escaped)
    output = output.replace( 'FOLDER_PATH',  folder_curr_escaped)
    output = output.replace( 'FOLDER_STYLE', '')
    index_list = index_list + output

    totalFiles = 0;
    for relPath in sorted(files,compare_natural_filename):

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
            media_path = os.path.relpath(fullPath,root)
            media_path_escaped = urllib.quote(media_path.replace('\\', '/')) # Fix any Windows backslashes
            filename_title_escaped=escape(fileName)
            
            if HAVE_THUMBNAILER:
                # We should have a jpg file, named the same as the playable file
                jpegName = fileName + '.jpg'
                jpegPath = fullPathNoExt + '.jpg'
                filename_jpeg_escaped=urllib.quote(os.path.relpath(jpegPath,root))
                need_jpeg.append( (fullPath,jpegPath) )
                pathcurr=str(INDEX_FILE)
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
            index_list = index_list + pathcurr
        if '.jpg' == extCurr:
            # Record existence of a jpeg file we found
            have_jpeg[fullPath] = True
            
    # Record folder for left box index/TOC
    small_output = str(INDEX_SMALL)
    small_output = small_output.replace( 'FOLDER_TITLE', folder_name_escaped)
    small_output_style = 'padding-left:' + str(folder_depth) + 'px;'
    if 0 != totalFiles:
        small_output = small_output.replace( 'FOLDER_PATH',  folder_curr_escaped)
        small_output = small_output.replace( 'FOLDER_STYLE', small_output_style )
        index_toc_small.append( (root,small_output) );

        # Add accumulated indexes to list, to defer sort
        index_toc.append( (root, index_list) );
        
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

    folder_path, folder_name = os.path.split(root_dir)
    folder_name_escaped = escape(folder_name)
    output = str(INDEX_TEMPLATE)
    output = output.replace( 'TITLE_TEXT', folder_name_escaped )
    output = output.replace( '/*INSERT_CSS_HERE*/', CSS_TEMPLATE )

    # Copy table of contents in, sorted.
    big_indexes=''
    for indexPath, item in sorted(index_toc,compare_natural):
        big_indexes = big_indexes + item + '\n'
    output = output.replace( '<!--INDEXES_HERE-->', big_indexes)
    
    # Add the small index list; Only emit index paths that lead to media 
    small_indexes=''
    for indexPath, item in sorted(index_toc_small,compare_natural):
        for apath in all_paths_with_media:
            if 0 == apath.find(indexPath):
                small_indexes = small_indexes + item + '\n'
                break;
    output = output.replace( '<!--FOLDERS_HERE-->', small_indexes)
    
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
            
    print "\nMade %d folders with %d files.\n" %(len(all_paths_with_media),total_media_count)
else:
    print "\nNo media found.  Nothing written.\n"
