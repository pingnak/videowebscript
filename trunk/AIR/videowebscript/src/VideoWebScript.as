
/*
 * Web (HTML5) Contact Sheet Generator
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

    import flash.desktop.NativeApplication; 
    import flash.filesystem.*;
    
    public class VideoWebScript extends MovieClip
    {
        internal static const SO_PATH : String = "VideoWebScriptData";
        internal static const SO_SIGN : String = "VIDEOSCRIPT_SIGN_01";

CONFIG::MXMLC_BUILD
{
        /** Main SWF */
        [Embed(source="./VideoWebScript_UI.swf", mimeType="application/octet-stream")]
        public static const baMainSwfClass : Class;
}

        /** A global instance to keep track of */
        internal static var instance : VideoWebScript = null;

        /** Where the main UI lives */
        internal var ui : MovieClip;
        
        /** What to call the 'top level' index file */
        public static var MAIN_INDEX      : String = "index.html";

        /** What to call the 'TOC' file that has all of the index.htmls in it */
        public static var MAIN_TOC        : String = "TOC.html";
        
        /** Where to look for script template content */
        public static var SCRIPT_TEMPLATES: String ="templates/"

        /** Top few lines of html files */
        public static var INDEX_TOPMOST   : String = SCRIPT_TEMPLATES+"index_topmost.html";

        /** CSS as its own stand-alone css file (concatenated in for easy house-keeping) */
        public static var INDEX_CSS       : String = SCRIPT_TEMPLATES+"webified.css";
        
        /** Start of movie player and available content */
        public static var MOVIE_PROLOG    : String = SCRIPT_TEMPLATES+"index_prolog.html";
        
        /** Table of contents file */
        public static var TOC_PROLOG      : String = SCRIPT_TEMPLATES+"TOC_prolog.html";
        
        /** A movie file link with player logic */
        public static var INDEX_FILE      : String = SCRIPT_TEMPLATES+"index_file.html";

        /** Link to folder index */
        public static var INDEX_INDEX     : String = SCRIPT_TEMPLATES+"index_index.html";

        /** End of movie player html file */
        public static var INDEX_EPILOG    : String = SCRIPT_TEMPLATES+"index_epilog.html";

        /** Width of thumbnails for video */
        public static var THUMB_SIZE      : int = 240;
        
        /** Offset for folder depths in TOC file */
        public static var FOLDER_DEPTH : int = 32;
        
        
        /** Regular expressions that we accept as 'MP4 content' 
            Lots of synonyms for 'mp4'.  Many of these may have incompatible CODECs 
            or DRM, or other proprietary extensions in them.   
        **/
        public static var REGEX_MP4        : String = ".(mp4|m4v|m4p|m4r|3gp|3g2)";

        /** Regular expressions that we accept as 'MP4 content'*/
        public static var REGEX_JPEG       : String = ".(jpg|jpeg)";
        
        /** Path to do the job in */
        internal static var root_path_video : File;

        /** Finder while searching files/folders */
        internal static var finding : Find;

        /** Thumbnailer */        
        internal static var thumbnail : Thumbnail;
        
        public function VideoWebScript()
        {
            instance = this;
            
CONFIG::MXMLC_BUILD
{           // Decode+initialize the swf content the UI was made of
            var loader : Loader = LoadSwfFromByteArray(baMainSwfClass);
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

            ui.tfPathVideo.addEventListener( Event.CHANGE, onFolderEdited );
            ui.tfThumbnailSize.addEventListener( Event.CHANGE, onFolderEdited );
            ui.bFindPathVideo.addEventListener( MouseEvent.CLICK, BrowsePathVideo );
            CheckSetup(ui.bnTOC);
            CheckSetup(ui.bnCompletionTone);
            
            ui.bnDoIt.addEventListener( MouseEvent.CLICK, DoVideo );
            ui.bnAbort.addEventListener( MouseEvent.CLICK, Abort );
            LoadSharedData();

            // A nice disabler helper
            function DisableIt(dobj:DisplayObject):void
            {
                if( dobj is InteractiveObject )
                {
                    var iobj : InteractiveObject = dobj as InteractiveObject;
                    iobj.tabEnabled = iobj.mouseEnabled = false; 
                    if( iobj is DisplayObjectContainer )
                        ( iobj as DisplayObjectContainer ).mouseChildren = false;
                }
                dobj.alpha = 0.5;
            }
            
            // Make tab order match depth of objects
            var i : int;
            var dobj : InteractiveObject;
            for( i = 0; i < ui.numChildren; ++i )
            {
                dobj = ui.getChildAt(i) as InteractiveObject;
                if( null != dobj )
                {
                    dobj.tabIndex = i;
                }
            }

            // Build our menu of doom
            if( NativeApplication.supportsMenu )
            { 
                // Tools Menu
                var appToolMenu:NativeMenuItem; 
                appToolMenu = NativeApplication.nativeApplication.menu.addItem(new NativeMenuItem("Tools")); 

                // Tools popup
                var toolMenu:NativeMenu = new NativeMenu(); 
                var removeThumbs:NativeMenuItem = toolMenu.addItem(new NativeMenuItem("Remove Thumbnails")); 
                var removeIndexes:NativeMenuItem = toolMenu.addItem(new NativeMenuItem("Remove index.html files")); 
                removeThumbs.addEventListener(Event.SELECT, RemoveThumbs); 
                removeIndexes.addEventListener(Event.SELECT, RemoveIndexes); 
                
                appToolMenu.submenu = toolMenu;
            }             

            // Do a few initial things
            ui.gotoAndStop("interactive");
            ui.tfStatus.text = "";
            ui.tabChildren = true;
            
            // Keep kicking the random number generator
            addEventListener( Event.ENTER_FRAME, Entropy );
        }

        /**
         * Keep random output inconsistent
        **/
        internal function Entropy(e:Event=null):void
        {
            Math.random();
        }
        

        internal function FindStatus(e:Event):void
        {
            //var list : Array = Find.FindBlock(root_path_video);
            var found_so_far : int = finding.results.length;
            ui.tfStatus.text = found_so_far.toString();
        }
        
        private function Busy() : void
        {
            ui.gotoAndStop(2);
            ui.gotoAndStop("working");
            ui.tfStatus.text = "...";
            ui.tabChildren = false;
        }
        private function Interactive() : void
        {
            ui.gotoAndStop("interactive");
            ui.tfStatus.text = "";
            ui.tabChildren = true;
            
            if( CheckGet( ui.bnCompletionTone ) )
            {
                PlaySound("fxBeepBoop");
            }
        }

        /**
         * Process halted or error
        **/
        internal function Aborted(e:Event):void
        {
            Interactive();
        }

        /**
         * Clicked abort button
        **/
        internal function Abort(e:Event):void
        {
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
                ErrorIndicate(ui.tfPathVideo);
                return;
            }
            // Make sure we don't go way out of range on thumb size
            if( THUMB_SIZE < 64 )
            {
                THUMB_SIZE = 64;
                ui.tfThumbnailSize.text = THUMB_SIZE.toString();
                ErrorIndicate(ui.tfThumbnailSize);
                return;
            }
            if( THUMB_SIZE > 360 )
            {
                THUMB_SIZE = 360;
                ui.tfThumbnailSize.text = THUMB_SIZE.toString();
                ErrorIndicate(ui.tfThumbnailSize);
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
            DoVideoFilesTree(finding.results);
        }

        /**
         * Finished exporting video files
        **/
        protected function VideoFilesComplete(e:Event=null):void
        {
            ui.tfStatus.text = "";
            if( 0 != thumbnail.queue_length )
            {
                // Wait for thumbnailing to complete
                thumbnail.addEventListener( Event.COMPLETE, ThumbnailsComplete );
                thumbnail.addEventListener( Thumbnail.SNAPSHOT_READY, ThumbnailNext );
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
            ui.tfStatus.text = thumbnail.queue_length.toString() + " " + Find.File_nameext(thumbnail.thumb_file);
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
         * add some more clutter to your directory tree for all of the index.html
         * files.  
         *
         * Simpler UI without folding folders.  Just one index.html at the root
         * like the other one, but containing only links to folders containing 
         * more content.
        **/
        protected function DoVideoFilesTree(found:Array):void
        {
            try
            {
                // Preload the various template elements we'll be writing for each folder/file
                var index_top : String      = LoadText(INDEX_TOPMOST) + LoadText(INDEX_CSS);
                var index_prolog : String   = index_top + LoadText(MOVIE_PROLOG); 
                var index_index : String    = LoadText(INDEX_INDEX); 
                var index_file : String     = LoadText(INDEX_FILE); 
                var index_epilog : String   = LoadText(INDEX_EPILOG); 
                
                // Iterate all of the folders
                var folders : Array = Find.GetFolders(found);
                var threadTimer : Timer = new Timer( 1,1 );
                threadTimer.addEventListener( TimerEvent.TIMER, ThreadPassFolder );
                threadTimer.start();

                var folder_iteration : int = 0;
                //for( folder_iteration = 0; folder_iteration < folders.length; ++folder_iteration )
                function ThreadPassFolder(e:Event):void
                {
                    if( folder_iteration < folders.length )
                    {
                        // Do next pass
                        threadTimer.reset();
                        threadTimer.start();
                    }
                    else
                    {
                        // Break out of 'threaded' loop
                        // Bottom part of file index file; all done
                        threadTimer = new Timer( 1,1 );
                        threadTimer.addEventListener( TimerEvent.TIMER, ThreadComplete );
                        threadTimer.start();
                        return;
                    }
                    
                    var iteration : int;
                    var seded : String
                    var folder : File;
                    var root : File = folders[folder_iteration++];

                    ui.tfStatus.text = folder_iteration.toString()+"/"+folders.length.toString();

                    // Don't write index files in folders with no video content
                    var total_files_folders_at_this_depth : Array = Find.GetChildren( found, root, int.MAX_VALUE );
                    var total_files_at_this_depth : Array = Find.GetFiles(total_files_folders_at_this_depth);
                    if( total_files_at_this_depth.length > 1 )
                    {
                        // Get a list of folders in this folder, files in this folder
                        var curr_files : Array = Find.GetChildren( found, root );
                        var curr_folders : Array = Find.GetFolders(curr_files);
                        curr_files = Find.GetFiles(curr_files);
                        
                        // Create and build top half of index file
                        var curr_title : String = Find.File_nameext(root);
                        seded = index_prolog;
                        seded = seded.replace(/THUMB_SIZE/g,THUMB_SIZE.toString());
                        seded = seded.replace(/TITLE_TEXT/g,curr_title);
                        var index_content : String = seded;
    
                        // Iterate child folders and generate links to them
                        for( iteration = 1; iteration < curr_folders.length; ++iteration )
                        {
                            var curr_folder : File  = curr_folders[iteration];
    
                            // Filter folders with no movies in any children from lists
                            total_files_folders_at_this_depth = Find.GetChildren( found, curr_folder, int.MAX_VALUE );
                            total_files_at_this_depth = Find.GetFiles(total_files_folders_at_this_depth);
                            if( total_files_at_this_depth.length > 1 )
                            {
                                var curr_index : File = Find.File_AddPath( curr_folder, MAIN_INDEX );
                                var curr_index_title : String = Find.File_nameext( curr_folder );
                                var curr_index_relative : String = Find.File_relative( curr_index, root );
        
                                // Emit index for child folder
                                seded = index_index;
                                seded = seded.replace(/FOLDER_PATH/g,curr_index_relative);
                                seded = seded.replace(/FOLDER_TITLE/g,curr_index_title);                      
                                seded = seded.replace(/FOLDER_STYLE/g,'');
                                index_content += seded;
                            }
                        }
                        
                        // Iterate files and generate code + thumbnails
                        for( iteration = 0; iteration < curr_files.length; ++iteration )
                        {
                            var curr_file : File = curr_files[iteration];
                            var curr_file_relative : String = Find.File_relative( curr_file, root );
                            var curr_file_title : String = Find.File_name( curr_file );
                            
                            var file_thumb : File = CheckThumbnail(curr_file);
                            var curr_file_thumb : String = Find.File_relative( file_thumb, root );
    
                            // Emit index+code to play file
                            seded = index_file;
                            seded = seded.replace(/MEDIA_IMAGE/g,curr_file_thumb);
                            seded = seded.replace(/MEDIA_PATH/g,curr_file_relative);
                            seded = seded.replace(/MOVIE_TITLE/g,curr_file_title);
                            seded = seded.replace(/FILE_STYLE/g,'');
                            index_content += seded;
                            
                        }
    
                        index_content += index_epilog;
                        
                        // Now write out index file in one pass
                        var curr_index_file : File = Find.File_AddPath( root, MAIN_INDEX );
                        var fs : FileStream = new FileStream();
                        fs.open( curr_index_file, FileMode.WRITE );
                        fs.writeUTFBytes(index_content);
                        fs.close();
                    }
                    
                }

                function ThreadComplete(e:Event=null):void
                {
                    // If user wanted a flattened table of contents, make one.
                    if( CheckGet( ui.bnTOC ) )
                    {
                        DoTOC(found);
                    }
                    VideoFilesComplete();
                }
            }
            catch( e:Error )
            {
                trace(e);
                ErrorIndicate(ui.tfPathVideo);
                Interactive();
            }
            // Fall out; timer threads are in charge
        }

        /**
         * Iterate through folders and generate a flattened Table of Contents 
         * of index.html files, throughout the tree.
         *
        **/
        protected function DoTOC(found:Array):void
        {
            var index_top : String      = LoadText(INDEX_TOPMOST) + LoadText(INDEX_CSS);
            var TOC_prolog : String     = index_top + LoadText(TOC_PROLOG); 
            var index_index : String    = LoadText(INDEX_INDEX); 
            var index_epilog : String   = LoadText(INDEX_EPILOG); 

            var folders : Array = Find.GetFolders(found);
            var root : File = folders[0];
            var curr_title : String = Find.File_nameext(root);
            var seded : String;
            seded = TOC_prolog;
            seded = seded.replace(/THUMB_SIZE/g,THUMB_SIZE.toString());
            seded = seded.replace(/TITLE_TEXT/g,curr_title);
            var index_content : String = seded;
            var folder_iteration : int;
            for( folder_iteration = 1; folder_iteration < folders.length; ++folder_iteration )
            {
                // Create and build top half of index file
                var curr_folder : File  = folders[folder_iteration];
                var curr_index_file : File = Find.File_AddPath( curr_folder, MAIN_INDEX );
                if( curr_index_file.exists )
                {
                    var curr_depth : int = Find.File_Depth(curr_folder,root);
                    var curr_index : File = Find.File_AddPath( curr_folder, MAIN_INDEX );
                    var curr_index_title : String = Find.File_nameext( curr_folder );
                    var curr_index_relative : String = Find.File_relative( curr_index, root );

                    // Emit index for child folder
                    seded = index_index;
                    seded = seded.replace(/FOLDER_PATH/g,curr_index_relative);
                    seded = seded.replace(/FOLDER_TITLE/g,curr_index_title);                      
                    seded = seded.replace(/FOLDER_STYLE/g,'padding-left:'+(curr_depth*FOLDER_DEPTH)+'px;');
                    index_content += seded;
                }
            }
            
            index_content += index_epilog;
            
            // Now write out index file in one pass
            var toc_file : File = Find.File_AddPath( root, MAIN_TOC );
            var fs : FileStream = new FileStream();
            fs.open( toc_file, FileMode.WRITE );
            fs.writeUTFBytes(index_content);
            fs.close();
        }

        /**
         * Reset persistent settings
        **/
        protected function ResetSharedData() : Object
        {
            root_path_video = File.userDirectory;
            CheckSet( ui.bnTOC, true );
            CheckSet( ui.bnCompletionTone, true );
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
            CheckSet( ui.bnTOC, share_data.bDoTOC );
            CheckSet( ui.bnCompletionTone, share_data.bPlayTune );

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

        /** Keep track if user hand-tweaked paths, so we can make them into File objects */
        internal function onFolderEdited(e:Event=null):void
        {
            root_path_video.nativePath = ui.tfPathVideo.text;
            THUMB_SIZE = int(ui.tfThumbnailSize.text);
        }

        /** User navigated a different path */
        internal function onFolderChanged(e:Event=null):void
        {
            ui.tfPathVideo.text = root_path_video.nativePath; 
        }
        
        /** Get check box state */
        internal static function CheckGet(mc:MovieClip):Boolean
        {
            return "on" == mc.currentLabel;
        }
        
        /** Get check box state */
        internal static function CheckSet(mc:MovieClip,state:Boolean):void
        {
            mc.gotoAndStop( state ? "on" : "off" );
        }

        /** Get check box state */
        internal static function CheckSetup(mc:MovieClip, initialState : Boolean = false):void
        {
            mc.addEventListener( MouseEvent.CLICK, HandleCheck );
            mc.gotoAndStop( initialState ? "on" : "off" );
            function HandleCheck(e:MouseEvent):void
            {
                mc.gotoAndStop("on" == mc.currentLabel ? "off" : "on" ); 
            }
        }

        /**
         * Invoke thumbnail nuker
        **/
        private function RemoveThumbs(event:Event):void 
        { 
            if( !root_path_video.exists || !root_path_video.isDirectory )
            {
                ErrorIndicate(ui.tfPathVideo);
                return;
            }

            var warning : String = "Every JPEG from the Video Player path will be wiped out!\n\n" + root_path_video.nativePath;
            AreYouSure( "Remove Video Thumbnail Images", yeah, warning, "DO IT!", "ABORT!" );
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
                            jpegpath.deleteFileAsync();
                        }
                    }
                    instance.Interactive();
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
                ErrorIndicate(ui.tfPathVideo);
                return;
            }

            var warning : String = "Every "+MAIN_INDEX+" from the Video Player path will be wiped out!\n\n" + root_path_video.nativePath;
            AreYouSure( "Remove Video Index Files", yeah, warning, "DO IT!", "ABORT!" );
            var rxIndex : RegExp = new RegExp(MAIN_INDEX,"i");
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
                        found[i].deleteFileAsync();
                    }
                    instance.Interactive();
                }
            }
        } 
        
        /**
         * Do a confirmation dialog for dangerous-looking stunts
         * @param title Window title
         * @param body  Body text explaining why we're stopping
         * @param yes   Yes button text
         * @param no    No button text
        **/
        internal static function AreYouSure( title:String, onYes : Function, body:String="Keep going?", yes:String="Yes", no:String="No" ) : void
        {
            var bYes : Boolean = false;
            
            if( "working" == instance.ui.currentLabel )
                return;
            instance.Busy();
            
            // create NativeWindowInitOptions
            var windowInitOptions:NativeWindowInitOptions = new NativeWindowInitOptions();
            windowInitOptions.type = NativeWindowType.NORMAL;
            windowInitOptions.minimizable = false;
            windowInitOptions.resizable = false;
            windowInitOptions.maximizable = false;
            windowInitOptions.systemChrome = NativeWindowSystemChrome.STANDARD;
            windowInitOptions.transparent = false;

            // create new NativeWindow
            var popupWindow:NativeWindow = new NativeWindow(windowInitOptions);
            
            // create your class
            var ui:MovieClip = GetMovieClip("UI_AreYouSure");

            // Text
            ui.tfBody.text = body;
            ui.tfYES.text = yes;
            ui.tfNO.text = no;
            popupWindow.title = title;
            
            ui.bnYES.addEventListener(MouseEvent.CLICK, onConfirm);
            ui.bnNO.addEventListener(MouseEvent.CLICK, onDeny);
            popupWindow.addEventListener( Event.CLOSE, onClose );
            
            function onClose(e:Event):void
            {
                if( !bYes )
                    instance.Interactive();
            }
            function onConfirm(e:Event):void
            {
                bYes = true;
                popupWindow.close();
                onYes.call(instance);
            }
            function onDeny(e:Event):void
            {
                popupWindow.close();
                instance.Interactive();
            }
            
            
            // for a popup it might be nice to have it activated and on top
            // resize
            //popupWindow.width = ui.width;
            //popupWindow.height = ui.height;

            // add
            popupWindow.stage.addChild(ui);
            popupWindow.stage.align = StageAlign.TOP_LEFT;
            popupWindow.stage.scaleMode = StageScaleMode.NO_SCALE;

            popupWindow.alwaysInFront = true;
            popupWindow.activate();
            
        }
        
        /**
         * Flash an error indicator
        **/
        internal function ErrorIndicate(whereXY:Object) : void
        {
            var mc : MovieClip = GetMovieClip("ErrorIndicator");
            if( whereXY is DisplayObject )
            {
                var bounds : Rectangle = whereXY.getBounds(this);
                mc.x = 0.5*(bounds.left+bounds.right);
                mc.y = 0.5*(bounds.top+bounds.bottom);
            }
            else
            {
                mc.x = whereXY.x;
                mc.y = whereXY.y;
            }
            addChild(mc);
            PlaySound("fxBeepBoop");
        }

        
        /**
         * Load a resource that's embedded 
        **/
CONFIG::MXMLC_BUILD
{
        public static function LoadSwfFromByteArray( baClass : Class ) : Loader
        {
            var ba : ByteArray = new baClass();
            var loader : Loader = new Loader();
            var loaderContext:LoaderContext = new LoaderContext(false);
            loaderContext.checkPolicyFile = false;
            loaderContext["allowCodeImport"] = true;
            loaderContext.applicationDomain = ApplicationDomain.currentDomain;
            loader.loadBytes(ba,loaderContext);
            return loader;
        }
}
        /**
         * Resolve a class that may have been loaded
        **/
        public static function GetClass( id : String ) : Class
        {
            return ApplicationDomain.currentDomain.getDefinition(id) as Class;
        }

        /**
         * Get a DisplayObject from class name
        **/
        public static function GetDisplayObject( id : String ) : DisplayObject
        {
            var cls : Class = ApplicationDomain.currentDomain.getDefinition(id) as Class;
            return new cls();
        }

        /**
         * Get a MovieClip from class name
        **/
        public static function GetMovieClip( id : String ) : MovieClip
        {
            var cls : Class = ApplicationDomain.currentDomain.getDefinition(id) as Class;
            return new cls();
        }
        
        /**
         * Load a text file (e.g. HTML template parts)
        **/
        protected function LoadText( path:String ) : String
        {
            try
            {
                var root : File = File.applicationDirectory;
                var f : File = Find.File_AddPath(root,path);
                if( f.exists && !f.isDirectory )
                {
                    var fs:FileStream = new FileStream();
                    fs.open(f, FileMode.READ);
                    var ret : String = fs.readUTFBytes(fs.bytesAvailable);
                    fs.close();
                    return ret;
                }
            }
            catch(e:Error)
            {
                trace(e);
            }
            return "";
        }
        
        /**
         * Play a Sound
         * @param id What sound to play (matches export in Flash)
         * @params... Parameters to pass to Sound.Play
         * @return SoundChannel from play()
        **/
        public static function PlaySound( id : String, ...params ) : SoundChannel
        {
            var cls : Class = ApplicationDomain.currentDomain.getDefinition(id) as Class;
            var sound : Sound = new cls();
            return sound.play.apply(id,params);
        }
    }
}
    
