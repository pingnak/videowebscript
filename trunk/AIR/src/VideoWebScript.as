
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
        internal static const SO_SIGN : String = "VIDEOSCRIPT_SIGN_00";

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

        /** Where to look for script template content */
        public static var SCRIPT_TEMPLATES: String ="templates/"

        /** Top few lines of html files */
        public static var INDEX_TOPMOST   : String = SCRIPT_TEMPLATES+"index_topmost.html";

        /** CSS as its own stand-alone css file (concatenated in for easy house-keeping) */
        public static var INDEX_CSS       : String = SCRIPT_TEMPLATES+"webified.css";
        
        /** Start of movie player and available content */
        public static var MOVIE_PROLOG    : String = SCRIPT_TEMPLATES+"index_prolog.html";
        
        /** End of movie player html file */
        public static var INDEX_EPILOG    : String = SCRIPT_TEMPLATES+"index_epilog.html";
        
        /** A movie file link with player logic */
        public static var INDEX_FILE      : String = SCRIPT_TEMPLATES+"index_file.html";

        /** Accordion movie folder link */
        public static var INDEX_FOLDER    : String = SCRIPT_TEMPLATES+"index_folder.html";

        /** Link to folder index */
        public static var INDEX_INDEX     : String = SCRIPT_TEMPLATES+"index_index.html";

        /** Where to find the contact sheet viewer */
        public static var VIDEOSCRIPT_PROLOG  : String = SCRIPT_TEMPLATES+"index_contact_prolog.html";
        
        /** Width of thumbnails for video */
        public static var THUMB_SIZE      : int = 240;
        
        /** Regular expressions that we accept as 'MP4 content' 
            Lots of synonyms for 'mp4'.  Many of these may have incompatible CODECs 
            or DRM, or other proprietary extensions in them.   
        **/
        public static var REGEX_MP4        : String = ".(mp4|m4v|m4p|m4r|3gp|3g2)";

        /** Regular expressions that we accept as 'MP4 content'*/
        public static var REGEX_JPEG       : String = ".(jpg|jpeg)";
        
        internal static var root_path_video : File;
        
        internal static var finding : Find;
        
        internal static var thumbnail : Thumbnail;
        
        public function VideoWebScript()
        {
            instance = this;
            
CONFIG::MXMLC_BUILD
{
            var loader : Loader = LoadSwfFromByteArray(baMainSwfClass);
            loader.contentLoaderInfo.addEventListener( Event.INIT, UI_Ready );
}
CONFIG::FLASH_AUTHORING
{
            UI_Ready();
}

        }

        /** 
         * All of the application classes are ready to use
         * Setup UI
        **/        
        public function UI_Ready(e:Event=null) : void
        {
            var cls : Class = GetClass("UI_Settings");
            ui = new cls();
            addChild(ui);

            ui.tfPathVideo.addEventListener( Event.CHANGE, onFolderEdited );
            ui.tfThumbnailSize.addEventListener( Event.CHANGE, onFolderEdited );
            ui.bFindPathVideo.addEventListener( MouseEvent.CLICK, BrowsePathVideo );
            CheckSetup(ui.bnVideoAllInOne);
            CheckSetup(ui.bnCompletionTone);
            
            ui.bnDoIt.addEventListener( MouseEvent.CLICK, DoIt );
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
        
        /**
         * Do the stuff.
        **/
        internal function DoIt(e:Event=null):void
        {
            trace("Doit",root_path_video.nativePath);

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
            
            DoVideo();
            
            
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
        
        /** Folder find is done.  Now decide what to do with it.  */
        protected function HaveVideoFiles(e:Event=null):void
        {
            if( CheckGet( ui.bnVideoAllInOne ) )
            {
                trace("Monolithic");
                DoVideoFilesMonolithic(finding.results);
            }
            else
            {
                trace("Tree");
                DoVideoFilesTree(finding.results);
            }
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
         * One index.html file for the whole tree
         *
         * Tidy, but if there's a lot of files, especially over network, the 
         * load time for the page could suffer.
         *
         * UI is a big list of folders, that 'open' to reveal files.
        **/
        protected function DoVideoFilesMonolithic(found:Array):void
        {
            try
            {
                var j : int;
                var file : File;
                var folder : File;
                var root : File = found[0];
                var root_string : String = Find.File_name(root);

                var folders : Array = Find.GetFolders(found);

                // Top part of file
                var main_index_content : String = LoadText(INDEX_TOPMOST); 
                var seded : String
                seded = LoadText(INDEX_CSS);
                seded = seded.replace(/THUMB_SIZE/g,THUMB_SIZE.toString());
                main_index_content += seded;
                
                seded = LoadText(MOVIE_PROLOG);
                seded = seded.replace(/TITLE_TEXT/g,root_string);
                main_index_content += seded;

                var index_file : String = LoadText(INDEX_FILE); 
                var index_folder : String = LoadText(INDEX_FOLDER); 
                var need_sdiv : Boolean = false;
                
                // Iterate files + folders
                var rxMP4 : RegExp = new RegExp(REGEX_MP4,"i");

                // Break outer loop up into timed passes, to keep this from blocking
                var threadTimer : Timer = new Timer( 1,1 );
                threadTimer.addEventListener( TimerEvent.TIMER, ThreadOnce );
                threadTimer.start();
                var folder_iteration : int = 0;

                //for( folder_iteration = 0; folder_iteration < folders.length; ++folder_iteration )
                function ThreadOnce(e:Event):void
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
                        main_index_content += LoadText(INDEX_EPILOG);
                        var main_index_file : File = Find.File_AddPath( root, MAIN_INDEX );
                        var fs:FileStream = new FileStream();
                        // Now write out index file in one pass
                        fs.open( main_index_file, FileMode.WRITE );
                        fs.writeUTFBytes(main_index_content);
                        fs.close();
                        VideoFilesComplete();
                        return;
                    }
                    folder = folders[folder_iteration++];
                    ui.tfStatus.text = folder_iteration.toString()+"/"+folders.length.toString();
                    
                    var files : Array = Find.GetChildren( found, folder );
                    var mp4files : Array = Find.Filter( files, justmp4 );
                    function justmp4(file:File):Boolean
                    {
                        var ext : String = Find.File_extension(file);
                        var amatch : Array = ext.match( rxMP4 );
                        return null == amatch ? false : 0 == ext.match( rxMP4 ).length;
                    }
                    
                    // Skip over folders that don't have mp4 files.
                    //trace(mp4files.length, folder.nativePath);
                    if( 1 < mp4files.length ) 
                    {
                        var relative_path : String;
                        var folderparent : String;
                        var foldername : String;
                        var folderstyle : String;
                        if( 0 == folder_iteration )
                        {   // Special case for root path
                            relative_path = "";
                            folderparent = "";
                            foldername = root_string;
                            folderstyle='';
                        }
                        else if( 0 == Find.File_Depth( folder, root ) )
                        {
                            relative_path = Find.File_relative( folder, root );
                            folderparent = ""; 
                            foldername = relative_path.slice(1+relative_path.lastIndexOf('/'));
                            folderstyle='style="display:none;"';
                        }
                        else
                        {
                            relative_path = Find.File_relative( folder, root );
                            folderparent = Find.File_relative(Find.File_parent( folder ), root )+'/';
                            foldername = relative_path.slice(1+relative_path.lastIndexOf('/'));
                            folderstyle='style="display:none;"';
                        }
    
                        // Parse folder name depth to indent?
                        seded = index_folder.replace(/FOLDER_PARENT/g,folderparent);
                        seded = seded.replace(/FOLDER_TITLE/g,foldername);
                        seded = seded.replace(/FOLDER_STYLE/g,folderstyle);
                        main_index_content += seded;
                        
                        for( j = 1; j < mp4files.length; ++j )
                        {
                            file = mp4files[j];
    
                            var file_relative_path : String = Find.File_relative( file, root );
                            var filename : String = file_relative_path.slice(1+file_relative_path.lastIndexOf('/'));
                            var lastdot : int = filename.lastIndexOf('.');
                            var ext : String = lastdot<0?'':filename.slice(lastdot);
                            if( null != ext.match(rxMP4) )
                            {   // Video file
                                var filename_noext : String = -1 == lastdot ? filename : filename.slice(0,lastdot);
                                
                                var file_thumb : File = CheckThumbnail(file);
                                var filename_thumb : String = Find.File_relative( file_thumb, root );
                                
                                seded = index_file.replace(/MEDIA_IMAGE/g,filename_thumb);
                                seded = seded.replace(/MEDIA_PATH/g,file_relative_path);
                                seded = seded.replace(/MOVIE_TITLE/g,filename_noext);
                                main_index_content += seded;
                            }
                            else
                            {
                                // Thumbnail files are mixed in with the mp4, so we don't
                                // do extra directory tree searches through the file system
                                // to check for thumbnails' existence
                            }
                        }
                        main_index_content += "</div>\n";
                    }
                }
    
            }
            catch( e:Error )
            {
                trace(e);
                ErrorIndicate(ui.tfPathVideo);
            }
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
                var folder_iteration : int;
                var iteration : int;
                var seded : String
                var folder : File;

                // Preload the various template elements we'll be writing for each folder/file
                var index_prolog : String = LoadText(INDEX_TOPMOST) + LoadText(INDEX_CSS) + LoadText(MOVIE_PROLOG); 
                var index_index : String = LoadText(INDEX_INDEX); 
                var index_file : String = LoadText(INDEX_FILE); 
                var index_epilog : String = LoadText(INDEX_EPILOG); 

                
                // Iterate all of the folders
                var folders : Array = Find.GetFolders(found);
                var threadTimer : Timer = new Timer( 1,1 );
                threadTimer.addEventListener( TimerEvent.TIMER, ThreadOnce );
                threadTimer.start();
                folder_iteration = 0;

                //for( folder_iteration = 0; folder_iteration < folders.length; ++folder_iteration )
                function ThreadOnce(e:Event):void
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
                        VideoFilesComplete();
                        return;
                    }
                    
                    var root : File = folders[folder_iteration++];
                    var curr_index_file : File = Find.File_AddPath( root, MAIN_INDEX );

                    ui.tfStatus.text = folder_iteration.toString()+"/"+folders.length.toString();
                    
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
                        var curr_index : File = Find.File_AddPath( curr_folder, MAIN_INDEX );
                        var curr_index_title : String = Find.File_nameext( curr_folder );
                        var curr_index_relative : String = Find.File_relative( curr_index, root );

                        // Emit index for child folder
                        seded = index_index;
                        seded = seded.replace(/FOLDER_PATH/g,curr_index_relative);
                        seded = seded.replace(/FOLDER_TITLE/g,curr_index_title);                      
                        index_content += seded;
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
                        index_content += seded;
                    }

                    // Now write out index file in one pass
                    var fs : FileStream = new FileStream();
                    fs.open( curr_index_file, FileMode.WRITE );
                    fs.writeUTFBytes(index_content);
                    fs.close();
                    
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
         * Reset persistent settings
        **/
        protected function ResetSharedData() : Object
        {
            root_path_video = File.userDirectory;
            CheckSet( ui.bnVideoAllInOne, false );
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
            CheckSet( ui.bnVideoAllInOne, share_data.bDoVideoAllInOne );
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
            share_data.bDoVideoAllInOne = CheckGet( ui.bnVideoAllInOne );
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
            var cls : Class = GetClass("UI_AreYouSure");
            var ui:MovieClip = new cls();

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
            var cls : Class = GetClass("ErrorIndicator");
            var mc : MovieClip = new cls();
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
         * Get a display object
        **/
        public static function GetDisplayObject( id : String ) : DisplayObject
        {
            var cls : Class = ApplicationDomain.currentDomain.getDefinition(id) as Class;
            return new cls();
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
    
