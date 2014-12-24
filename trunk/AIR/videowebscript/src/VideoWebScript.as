
/*
 * Web (HTML5) Video Player Generator
 *
 * Iterate gigantic trees of contents to generate thumbnails, and displays/players
 * in the browser, similar to DLNA photo/music/movie handling.
 *
 * Will work as well as your web browser does... which isn't saying much, in some cases.
 */

package
{
    import flash.system.*;
    import flash.utils.*;
    import flash.geom.*;
    import flash.events.*;
    import flash.display.*;
    import flash.text.*;
    import flash.media.*;
    import flash.filters.*;
    import flash.ui.*;

    import flash.desktop.NativeApplication;
    import flash.filesystem.*;

    public class VideoWebScript extends applet
    {
        internal static const SO_PATH : String = "VideoWebScriptData";
        internal static const SO_SIGN : String = "VIDEOSCRIPT_SIGN_1.1";

CONFIG::MXMLC_BUILD
{
        /** Main SWF */
        [Embed(source="./VideoWebScript_UI.swf", mimeType="application/octet-stream")]
        public static const baMainSwfClass : Class;
}

        /** Where the main UI lives */
        internal var ui : MovieClip;

        /** What to call the 'top level' index file */
        public static var HTML_PLAYER     : String = "VideoPlayer.html";

        /** What to call the 'TOC' file that has all of the index.htmls in it */
        public static var MAIN_TOC        : String = "index.html";

        /** Where to look for script template content */
        public static var SCRIPT_TEMPLATES: String ="templates/"

        /** Start of movie player and available content */
        public static var PLAYER_TEMPLATE : String = SCRIPT_TEMPLATES+"VideoPlayer_template.html";

        /** A movie file link with player logic */
        public static var INDEX_FILE      : String = SCRIPT_TEMPLATES+"index_file.html";

        /** A movie file link with player logic */
        public static var INDEX_NOTHUMB   : String = SCRIPT_TEMPLATES+"index_file_nothumb.html";

        /** Link to folder index */
        public static var INDEX_INDEX     : String = SCRIPT_TEMPLATES+"index_index.html";

        /** Link to folder index */
        public static var INDEX_SMALL     : String = SCRIPT_TEMPLATES+"index_small.html";

        /** Table of contents file */
        public static var TOC_TEMPLATE    : String = SCRIPT_TEMPLATES+"TOC_template.html";

        /** Link to TOC index */
        public static var INDEX_TOC       : String = SCRIPT_TEMPLATES+"index_toc.html";

        /** Play a file in TOC */
        public static var INDEX_TOC_FILE  : String = SCRIPT_TEMPLATES+"index_toc_file.html";

        /** Width of thumbnails for video */
        public static var THUMB_SIZE      : int = 240;

        /** Offset for folder depths in TOC file */
        public static var FOLDER_DEPTH : int = 32;

        /** File/folder left padding*/
        public static var LEFT_PADDING : int = 6;


        /** Regular expressions that we accept as 'MP4 content'
            Lots of synonyms for 'mp4'.  Many of these may have incompatible CODECs
            or DRM, or other proprietary extensions in them.
        **/
        public static var REGEX_MP4        : String = ".(mp4|m4v|m4p|m4r|3gp|3g2)";

        /** Regular expressions that we accept as 'jpeg content'*/
        public static var REGEX_JPEG       : String = ".(jpg|jpeg)";

        /** Path to do the job in */
        internal var root_path_video : File;

        /** Finder while searching files/folders */
        internal var finding : Find;

        internal var found : Array;

        /** Thumbnailer */
        internal var thumbnail : Thumbnail;

        public function VideoWebScript()
        {
            instance = this;

CONFIG::MXMLC_BUILD
{           // Decode+initialize the swf content the UI was made of
            var loader : Loader = LoadFromByteArray(new baMainSwfClass());
            loader.contentLoaderInfo.addEventListener( Event.INIT, UI_Ready );
}
CONFIG::FLASH_AUTHORING
{           // Built in Flash, so it's already loaded+initialized
            UI_Ready();
}

        }

        /**
         * All of the application classes are ready to use
         * Setup UI
        **/
        public function UI_Ready(e:Event=null) : void
        {
            ui = GetMovieClip("UI_Settings");
            addChild(ui);
            SortTabs(ui);

            ui.tfPathVideo.addEventListener( Event.CHANGE, onFolderEdited );
            ui.tfPathVideo.addEventListener( KeyboardEvent.KEY_DOWN, HitEnter );

            CheckSetup(ui.bnDoThumbs);
            ui.tfThumbnailSize.addEventListener( Event.CHANGE, onFolderEdited );
            ui.tfThumbnailSize.maxChars = 3;
            ui.tfThumbnailSize.restrict = "0-9";
            ui.bFindPathVideo.addEventListener( MouseEvent.CLICK, BrowsePathVideo );
            ui.bnFindExplore.addEventListener( MouseEvent.CLICK, OpenFolder );
            CheckSetup(ui.bnTOC);
            CheckSetup(ui.bnCompletionTone);

            ui.bnDoIt.addEventListener( MouseEvent.CLICK, DoVideo );
            ui.bnAbort.addEventListener( MouseEvent.CLICK, Abort );
            LoadSharedData();

            // Build our menu of doom
            if( NativeApplication.supportsMenu )
            {
                // Tools Menu
                var appToolMenu:NativeMenuItem;
                appToolMenu = NativeApplication.nativeApplication.menu.addItem(new NativeMenuItem("Tools"));

                // Tools popup
                var toolMenu:NativeMenu = new NativeMenu();
                var removeThumbs:NativeMenuItem = toolMenu.addItem(new NativeMenuItem("Remove Thumbnails"));
                var removeIndexes:NativeMenuItem = toolMenu.addItem(new NativeMenuItem("Remove "+HTML_PLAYER+" files"));
                removeThumbs.addEventListener(Event.SELECT, RemoveThumbs);
                removeIndexes.addEventListener(Event.SELECT, RemoveIndexes);

                appToolMenu.submenu = toolMenu;
            }

            // Do a few initial things
            ui.gotoAndStop("interactive");
            ui.tfStatus.text = "";
            ui.tabChildren = true;


        }

        internal function FindStatus(e:Event):void
        {
            //var list : Array = Find.FindBlock(root_path_video);
            var found_so_far : int = finding.results.length;
            ui.tfStatus.text = "Finding... "+found_so_far.toString();
        }

        public override function Busy(e:Event=null) : void
        {
            ui.gotoAndStop(2);
            ui.gotoAndStop("working");
            ui.tfStatus.text = "...";
            ui.tabChildren = false;
        }
        public override function Interactive(e:Event=null) : void
        {
            ui.gotoAndStop("interactive");
            ui.tfStatus.text = "";
            ui.tabChildren = true;

            if( CheckGet( ui.bnCompletionTone ) )
            {
                PlaySound("fxBeepBoop");
            }
        }
        public override function isBusy() : Boolean
        {
            return "working" == ui.currentLabel;
        }


        /**
         * Process halted or error
        **/
        internal function Aborted(e:Event):void
        {
            AbortTimeouts();
            Interactive();
        }

        /**
         * Clicked abort button
        **/
        internal function Abort(e:Event):void
        {
            AbortTimeouts();
            if( null != finding )
            {
                finding.Abort();
                finding = null;
            }
            if( null != thumbnail )
            {
                thumbnail.Cleanup();
                thumbnail = null;
            }
        }

        /**
         * Process video tree
        **/
        protected function DoVideo(e:Event=null):void
        {
            trace("DoVideo",root_path_video.nativePath);

            /**
             * Do parameter checks before we launch into processes
            **/
            ui.tfPathVideo.text = root_path_video.nativePath;

            if( !root_path_video.exists || !root_path_video.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathVideo);
                return;
            }
            // Make sure we don't go way out of range on thumb size
            if( THUMB_SIZE < 64 )
            {
                THUMB_SIZE = 64;
                ui.tfThumbnailSize.text = THUMB_SIZE.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfThumbnailSize);
                return;
            }
            if( THUMB_SIZE > 360 )
            {
                THUMB_SIZE = 360;
                ui.tfThumbnailSize.text = THUMB_SIZE.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfThumbnailSize);
                return;
            }

            CommitSharedData();

            // MP4, PNG, folders
            var rxMP4 : RegExp = new RegExp(REGEX_MP4,"i")
            function filter_mp4_png_folders(file:File):Boolean
            {
                // No hidden files/folders
                if( file.isHidden )
                    return true;
                // Yes, folders
                if( file.isDirectory )
                    return false;
                // Files with .png/.mp4 extensions
                var ext : String = Find.File_extension(file);
                return null == ext.match( rxMP4 );
            }

            finding = new Find( root_path_video, filter_mp4_png_folders );
            ui.tfStatus.text = "...";
            finding.addEventListener( Find.ABORT, Aborted );
            finding.addEventListener( Find.MORE, FindStatus );
            finding.addEventListener( Find.FOUND, HaveVideoFiles );

            thumbnail = new Thumbnail(ui.mcThumbnail.mcPlaceholder,THUMB_SIZE);
            Busy();

        }

        /** Folder find is done.  Now decide what to do with it.  */
        protected function HaveVideoFiles(e:Event=null):void
        {
            trace("Tree");
            found = finding.results;//Find.PruneEmpties( finding.results );
            DoVideoFilesTree(found);
        }

        /**
         * Finished exporting video files
        **/
        protected function VideoFilesComplete(e:Event=null):void
        {
            ui.tfStatus.text = "";
            if( CheckGet( ui.bnDoThumbs ) && 0 != thumbnail.queue_length )
            {
                // Wait for thumbnailing to complete
                thumbnail.addEventListener( Event.COMPLETE, ThumbnailsComplete );
                thumbnail.addEventListener( Thumbnail.LOADING, ThumbnailNext );
                //thumbnail.addEventListener( Thumbnail.SNAPSHOT_READY, ThumbnailNext );
                ui.tfStatus.text = "Generate thumbnails...";
                thumbnail.Startup();
            }
            else
            {
                // Jump to audio task
                ThumbnailsComplete();
            }
        }

        /**
         * Clean up after video UI and thumbnail generation
        **/
        protected function ThumbnailsComplete(e:Event=null):void
        {
            if( null != thumbnail )
            {
                thumbnail.Cleanup();
                thumbnail = null;
            }
            Interactive();
        }


        /** Update progress animation with thumbnail status */
        protected function ThumbnailNext(e:Event=null):void
        {
            ui.tfStatus.text = "Thumbnail: " + thumbnail.queue_length.toString() + " " + Find.File_nameext(thumbnail.thumb_file);
        }

        /**
         * Check for thumbnail file
         * @param file MP4 file to check for thumbnail
         * @return Path to thumbnail that exists, or will be generated
        **/
        protected function CheckThumbnail(file:File) : File
        {
            var file_thumb : File;
            file_thumb = Find.File_newExtension( file, '.jpg' );
            if( file.isSymbolicLink )
            {   // Don't chase symlinks, which may be stale, or duplicate effort.
                return file_thumb;
            }
            if( !file_thumb.exists )
            {   // Have NO thumbnail (make a jpeg)
                trace("Needs thumbnail:",file_thumb.url);
                thumbnail.AddTask( file, file_thumb )
            }
            return file_thumb;
        }

        /**
         * Recursively generates files for each folder, and generates a master
         * index for all.
         *
         * This will definitely load individual pages a lot faster, but you'll
         * add some more clutter to your directory tree for all of the VideoPlayer
         * files.
         *
         * Simpler UI without folding folders.  Just one index.html at the root
         * like the other ones, but containing only links to folders containing
         * more content.
        **/
        protected function DoVideoFilesTree(found:Array):void
        {
            try
            {
                // Preload the various template elements we'll be writing for each folder/file
                var player_template : String= LoadText(PLAYER_TEMPLATE);
                var index_template : String = LoadText(TOC_TEMPLATE);
                var index_index : String    = LoadText(INDEX_INDEX);
                var index_small : String    = LoadText(INDEX_SMALL);
                var index_file : String     = LoadText(INDEX_FILE);
                var index_toc_file : String = LoadText(INDEX_TOC_FILE);
                var index_nothumb : String  = LoadText(INDEX_NOTHUMB);

                var index_toc : String = LoadText(INDEX_TOC);
                //var player_template_folders : String = LoadText(TOC_TEMPLATE);

                // Iterate all of the folders
                var folders : Array = Find.GetFolders(found);
                var folder_list_db : Array = new Array();
                var file_list_index : String = "";
                var bExportedLinks : Boolean = false;

                setTimeout( ThreadPassFolder );
                var folder_iteration : int = 0;
                //for( folder_iteration = 0; folder_iteration < folders.length; ++folder_iteration )
                function ThreadPassFolder():void
                {
                    if( folder_iteration < folders.length )
                    {
                        // Do next pass
                        setTimeout( ThreadPassFolder );
                    }
                    else
                    {
                        // Break out of 'threaded' loop
                        // Bottom part of file index file; all done
                        setTimeout( ThreadComplete );
                        return;
                    }

                    var iteration : int;
                    var seded : String
                    var folder : File;
                    var root : File = folders[folder_iteration++];

                    ui.tfStatus.text = "Folder: "+folder_iteration.toString()+"/"+folders.length.toString();

                    // Don't write index files in folders with no video content
                    var total_files_folders_at_this_depth : Array = Find.GetChildren( found, root, int.MAX_VALUE );
                    var total_files_at_this_depth : Array = Find.GetFiles(total_files_folders_at_this_depth);
                    if( total_files_at_this_depth.length > 0 )
                    {
                        // Get a list of folders in this folder, files in this folder
                        var curr_files : Array = Find.GetChildren( found, root );
                        var curr_folders : Array = Find.GetFolders(curr_files);
                        curr_files = Find.GetFiles(curr_files);
//trace("Found Folders:",root.nativePath,curr_folders.length);
//trace("Found Files:",root.nativePath,curr_folders.length);

                        // Create and build top half of index file
                        var curr_title : String = Find.File_nameext(root);
                        seded = player_template;
                        seded = seded.replace(/THUMB_SIZE/g,THUMB_SIZE.toString());
                        seded = seded.replace(/TITLE_TEXT/g,curr_title);
                        var index_content : String = seded;
                        var index_files : String = "";
                        var curr_index_file : File = Find.File_AddPath( root, HTML_PLAYER );

                        // Iterate child folders and generate links to them
                        for( iteration = 0; iteration < curr_folders.length; ++iteration )
                        {
                            var curr_folder : File  = curr_folders[iteration];

                            // Filter folders with no movies in any children from lists
                            total_files_folders_at_this_depth = Find.GetChildren( found, curr_folder, int.MAX_VALUE );
                            total_files_at_this_depth = Find.GetFiles(total_files_folders_at_this_depth);
                            if( total_files_at_this_depth.length > 1 )
                            {
                                var curr_index : File = Find.File_AddPath( curr_folder, HTML_PLAYER );
                                var curr_index_title : String = Find.File_nameext( curr_folder );
                                curr_index_title = Find.FixDecodeURI(curr_index_title);
                                var curr_index_relative : String = Find.File_relative( curr_index, root );
                                var curr_index_absolute : String = Find.File_relative( curr_index, folders[0] );
                                var curr_depth : int = Find.File_Depth(curr_folder,folders[0]);

                                if( 0 == iteration )
                                {
                                    if( folders[0] != curr_folder && 0 != curr_files.length )
                                    {
                                        seded = index_index;
                                        seded = seded.replace(/FOLDER_PATH/g,curr_index_absolute);
                                        seded = seded.replace(/FOLDER_TITLE/g,curr_index_title);
                                        seded = seded.replace(/FOLDER_STYLE/g,"");
                                        file_list_index += seded;
                                    }
                                }
                                else
                                {

                                    // Emit index for child folder
                                    seded = index_index;
                                    seded = seded.replace(/FOLDER_PATH/g,curr_index_relative);
                                    seded = seded.replace(/FOLDER_TITLE/g,curr_index_title);
                                    seded = seded.replace(/FOLDER_STYLE/g,'padding-left:'+LEFT_PADDING+'px;');
                                    index_files += seded;

                                    // Generate indexes for TOC
                                    seded = index_small;
                                    seded = seded.replace(/FOLDER_PATH/g,curr_index_absolute);
                                    seded = seded.replace(/FOLDER_TITLE/g,curr_index_title);
                                    seded = seded.replace(/FOLDER_STYLE/g,'padding-left:'+(LEFT_PADDING+(curr_depth*FOLDER_DEPTH))+'px;');
                                    folder_list_db.push( {name:curr_index_title,item:seded,path:curr_folder,depth:curr_depth} );
                                }
                            }
                        }

                        if( 0 != curr_files.length )
                        {
                            index_files += "<br/>\n";
                        }

                        // Iterate files and generate code + thumbnails
                        for( iteration = 0; iteration < curr_files.length; ++iteration )
                        {
                            var curr_file : File = curr_files[iteration];
                            var curr_file_relative : String = Find.File_relative( curr_file, root );
                            var curr_file_title : String = Find.File_name( curr_file );
                            curr_file_title = Find.FixDecodeURI(curr_file_title);

                            var file_thumb : File = CheckThumbnail(curr_file);
                            var curr_file_thumb : String = Find.File_relative( file_thumb, root );

                            // Emit index+code to play file
                            if( CheckGet( ui.bnDoThumbs ) )
                            {
                                seded = index_file;
                                seded = seded.replace(/MEDIA_IMAGE/g,curr_file_thumb);
                            }
                            else
                            {   // No thumbnail
                                seded = index_nothumb;
                            }
                            seded = seded.replace(/MEDIA_PATH/g,curr_file_relative);
                            seded = seded.replace(/MOVIE_TITLE/g,curr_file_title);
                            seded = seded.replace(/FILE_STYLE/g,'padding-left:'+LEFT_PADDING+'px;');
                            index_files += seded;

                            // Emit absolute index to play from TOC
                            curr_file_relative = Find.File_relative( curr_index_file, folders[0] );
                            var curr_name   : String = Find.FixDecodeURI(Find.File_nameext(curr_file));
                            var curr_path   : String = curr_file_relative + '?' + curr_name;
                            seded = index_toc_file;
                            seded = seded.replace(/MEDIA_PATH/g,curr_path);
                            seded = seded.replace(/MOVIE_TITLE/g,curr_file_title);
                            seded = seded.replace(/FILE_STYLE/g,'padding-left:'+(LEFT_PADDING+FOLDER_DEPTH)+'px;');
                            file_list_index += seded;

                            bExportedLinks = true;
                        }

                        index_content = index_content.replace("<!--INDEXES_HERE-->",index_files);

                        // Now write out index file in one pass
                        WriteAsync( curr_index_file, index_content );
                    }

                }

                function ThreadComplete():void
                {
                    // If user wanted a flattened table of contents, make one.
                    // We already did all the work for it, above
                    if( CheckGet( ui.bnTOC ) )
                    {
                        // Insert folder list for little link table
                        var folder_list : String = "";
                        folder_list_db.sort(bypath);
                        function bypath( p1:Object, p2:Object ) : int
                        {
                            var s1 : String = p1.path.nativePath;
                            var s2 : String = p2.path.nativePath;
                            if( s1 < s2 )
                                return -1;
                            else if( s1 > s2 )
                                return 1;
                            return 0;
                        }
                        var iteration : int;
                        for( iteration = 0; iteration < folder_list_db.length; ++iteration )
                        {
                            var dbCurr : Object = folder_list_db[iteration];
                            //if( 0 == dbCurr.depth && 0 != iteration )
                            //    folder_list += "<br/>";
                            folder_list += dbCurr.item;
                        }

                        var index_content : String = index_template;
                        index_content = index_content.replace(/THUMB_SIZE/g,THUMB_SIZE.toString());
                        //index_content = index_content.replace(/TITLE_TEXT/g,curr_title);
                        index_content = index_content.replace("<!--INDEXES_HERE-->",file_list_index);
                        index_content = index_content.replace("<!--FOLDERS_HERE-->",folder_list);

                        // Now write out index file in one pass
                        var toc_file : File = Find.File_AddPath( folders[0], MAIN_TOC );
                        var fs : FileStream = new FileStream();
                        fs.open( toc_file, FileMode.WRITE );
                        fs.writeUTFBytes(index_content);
                        fs.close();
                    }
                    // Put UI back
                    VideoFilesComplete();
                }
            }
            catch( e:Error )
            {
                trace(e);
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathVideo);
                Interactive();
            }
            // Fall out; timer threads are in charge
        }

        /**
         * Write a file asynchronously
        **/
        protected function WriteAsync(file:File, utf:String):void
        {
            var fs : FileStream = new FileStream();
            fs.openAsync( file, FileMode.WRITE );
            fs.addEventListener(OutputProgressEvent.OUTPUT_PROGRESS, waitToClose);
            fs.writeUTFBytes(utf);
            function waitToClose(e:OutputProgressEvent):void
            {
                if( 0 == e.bytesPending )
                {
                    fs.removeEventListener(OutputProgressEvent.OUTPUT_PROGRESS, waitToClose);
                    fs.close();
                }
            }
        }


        /**
         * Reset persistent settings
        **/
        protected function ResetSharedData() : Object
        {
            root_path_video = File.desktopDirectory;
            onFolderChanged();
            CheckSet( ui.bnTOC, true );
            CheckSet( ui.bnCompletionTone, true );
            CheckSet( ui.bnDoThumbs, true );
            THUMB_SIZE = 240;
            return CommitSharedData();
        }

        /**
         * Load and apply persistent settings
        **/
        protected function LoadSharedData():void
        {
            trace("LoadSharedData");

            var share_data : Object;

            try
            {
                var f:File = File.applicationStorageDirectory.resolvePath(SO_PATH);
                if( !f.exists )
                {
                    trace("NO SETTINGS");
                    ResetSharedData();
                    return;
                }

                // Grab the data object out of the file
                var fs:FileStream = new FileStream();
                fs.open(f, FileMode.READ);
                share_data = fs.readObject();
                fs.close();
            }
            catch( e:Error )
            {
                trace(e,e.getStackTrace());
                ResetSharedData();
            }

            // Verify version compatibility
            if( SO_SIGN != share_data.sign )
            {
                share_data = ResetSharedData();
                return;
            }

            // Decode the saved data
            root_path_video = new File(share_data.url_video);
            if( !root_path_video.exists )
                root_path_video = File.desktopDirectory;
            onFolderChanged();

            CheckSet( ui.bnTOC, share_data.bDoTOC );
            CheckSet( ui.bnCompletionTone, share_data.bPlayTune );
            CheckSet( ui.bnDoThumbs, share_data.bDoThumbs );

            THUMB_SIZE = share_data.thumb_size;
            ui.tfThumbnailSize.text = THUMB_SIZE.toString();

            onFolderChanged();

        }

        /**
         * Save persistent settings
        **/
        public function CommitSharedData() : Object
        {
            var share_data : Object = {};

            // Get file
            var f:File = File.applicationStorageDirectory.resolvePath(SO_PATH);
            var fs:FileStream = new FileStream();
            fs.open(f, FileMode.WRITE);

            // Copy data to our save 'object
            share_data.url_video = root_path_video.url;
            share_data.bDoTOC = CheckGet( ui.bnTOC );
            share_data.bPlayTune = CheckGet( ui.bnCompletionTone );
            share_data.bDoThumbs = CheckGet( ui.bnDoThumbs );
            share_data.thumb_size = THUMB_SIZE;

            share_data.sign = SO_SIGN;

            // Commit file stream
            fs.writeObject(share_data);
            fs.close();

            // Return our object for reference
            return share_data;
        }

        /** Find path to video content */
        internal function BrowsePathVideo(e:Event=null):void
        {
            root_path_video.addEventListener(Event.SELECT, onFolderChanged);
            root_path_video.browseForDirectory("Choose a folder");
        }

        /** Open an OS Finder/Explorer/whatever browser */
        internal function OpenFolder(e:Event=null):void
        {
            root_path_video.openWithDefaultApplication();
        }


        /** Keep track if user hand-tweaked paths, so we can make them into File objects */
        internal function onFolderEdited(e:Event=null):void
        {
            if( '' == ui.tfPathVideo.text )
            {
                root_path_video.nativePath = '/';
            }
            else
            {
                root_path_video.nativePath = ui.tfPathVideo.text;
            }
            THUMB_SIZE = int(ui.tfThumbnailSize.text);
        }

        // Convenience - hit enter in port to start up
        private function HitEnter(event:KeyboardEvent):void
        {
            if(Keyboard.ENTER == event.charCode)
            {
                onFolderEdited();
                DoVideo();
            }
        }


        /** User navigated a different path */
        internal function onFolderChanged(e:Event=null):void
        {
            ui.tfPathVideo.text = root_path_video.nativePath;
        }

        /**
         * Invoke thumbnail nuker
        **/
        private function RemoveThumbs(event:Event):void
        {
            if( !root_path_video.exists || !root_path_video.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathVideo);
                return;
            }

            var warning : String = "Every JPEG from the Video Player path will be wiped out!\n\n" + root_path_video.nativePath;
            AreYouSure( GetMovieClip("UI_AreYouSure"), "Remove Video Thumbnail Images", yeah, warning, "DO IT!", "ABORT!" );
            function yeah():void
            {
                trace("Removing Thumbnail Images");
                function OnlyMP4(file:File):Boolean
                {
                    // No hidden files/folders
                    if( file.isHidden )
                        return true;
                    // Filtering folders HERE would exclude their contents.
                    if( file.isDirectory )
                        return false;
                    var ext : String = Find.File_extension(file);
                    var found:Array = ext.match(REGEX_MP4);
                    return null == found;
                }
                finding = new Find( root_path_video, OnlyMP4 )
                finding.addEventListener( Find.FOUND, doit );
                finding.addEventListener( Find.MORE, FindStatus );
                function doit(e:Event):void
                {
                    // Look for jpg files, like THIS APP would create, and
                    // ignore jpg files that don't have a corresponding MP4
                    // file.
                    var found : Array = Find.GetFiles( finding.results );
                    trace("Erasing up to",found.length,"files...");
                    var i : int;
                    var jpegpath : File;
                    for( i = 0; i < found.length; ++i )
                    {
                        jpegpath = Find.File_newExtension( found[i], ".jpg" );
                        if( jpegpath.exists )
                        {
                            trace(jpegpath.nativePath);
                            try
                            {
                                jpegpath.moveToTrashAsync();
                            }
                            catch(e:Error)
                            {
                                trace(e);
                            }
                        }
                    }
                    Interactive();
                }
            }
        }

        /**
         * Invoke index file nuker
        **/
        private function RemoveIndexes(event:Event):void
        {
            if( !root_path_video.exists || !root_path_video.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathVideo);
                return;
            }

            var warning : String = "Every "+HTML_PLAYER+" from the Video Player path will be wiped out!\n\n" + root_path_video.nativePath;
            AreYouSure( GetMovieClip("UI_AreYouSure"), "Remove Video Index Files", yeah, warning, "DO IT!", "ABORT!" );
            var rxIndex : RegExp = new RegExp(HTML_PLAYER,"i");
            function yeah():void
            {
                trace("Removing Index Files...");
                function OnlyHTML(file:File):Boolean
                {
                    // No hidden files/folders
                    if( file.isHidden )
                        return true;
                    // Filtering folders HERE would exclude their contents.
                    if( file.isDirectory )
                        return false;
                    var filename : String = Find.File_nameext(file);
                    var found:Array = filename.match(rxIndex);
                    return null == found;
                }
                finding = new Find( root_path_video, OnlyHTML );
                finding.addEventListener( Find.FOUND, doit );
                finding.addEventListener( Find.MORE, FindStatus );
                function doit(e:Event):void
                {
                    var found : Array = Find.GetFiles( finding.results );
                    trace("Erasing",found.length,"files...");
                    var i : int;
                    for( i = 0; i < found.length; ++i )
                    {
                        trace(found[i].nativePath);
                        try
                        {
                            found[i].moveToTrashAsync();
                        }
                        catch(e:Error)
                        {
                            trace(e);
                        }
                    }
                    Interactive();
                }
            }
        }

    }
}
