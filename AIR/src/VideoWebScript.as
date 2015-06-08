
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
        protected static const SO_PATH : String = "VideoWebScriptData";
        protected static const SO_SIGN : String = "VIDEOSCRIPT_SIGN_2.0";

CONFIG::MXMLC_BUILD
{
        /** Main SWF */
        [Embed(source="./VideoWebScript_UI.swf", mimeType="application/octet-stream")]
        public static const baMainSwfClass : Class;
}

        /** Where the main UI lives */
        protected var ui : MovieClip;

        /** What to call the 'TOC' file that has all of the index.htmls in it */
        public static const MAIN_TOC        : String = "index.html";

        /** Start of movie player and available content */
        public static const INDEX_TEMPLATE  : String = "video_template.html";

        /** A css file with theming details */
        public static const CSS_TEMPLATE  : String = "template.css";

        /** Width of thumbnails for video */
        public static const THUMB_SIZE_DEFAULT : int = 240;

        /** Offset for folder depths in TOC file */
        public static const FOLDER_DEPTH : int = 16;

        /** File/folder left padding*/
        public static const LEFT_PADDING : int = 4;

        /** Regular expressions that we accept as 'MP4 content'
            Lots of synonyms for 'mp4'.  Many of these may have incompatible CODECs
            or DRM, or other proprietary extensions in them.
        **/
        public static const REGEX_MP4        : RegExp = /.(mp4|m4v|m4p|m4r|3gp|3g2)/;

        /** Regular expressions that we accept as 'jpeg content'*/
        public static const REGEX_JPEG       : RegExp = /.(jpg|jpeg)/;

        /** Path to do the job in */
        protected var root_path_media : File;
        
        /** Path to get templates from */
        protected var root_path_template : File;

        /** Path to file containing index template */
        protected var index_template_file : File;

        /** Path to file containing common css */
        protected var css_template_file : File;
        
        /** Finder while searching files/folders */
        protected var finding : Find;

        protected var found : Array;

        /** Thumbnailer */
        protected var thumbnail : Thumbnail;

        /** Set width of thumbnails */
        protected var thumb_size : int;

        /** CSS template file, loaded */
        protected var css_template : String

        /** Player template file, loaded */
        protected var index_template : String;

        /** Top level folder template */
        protected var index_folder : String;

        /** Start of folder group */
        protected var index_begin : String;

        /** Index file with thumbnail */
        protected var index_file : String;

        /** Index file without thumbnail */
        protected var index_file_nothumb : String;

        /** End of folder group */
        protected var index_end : String;
        
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
            CheckSetup(ui.bnCompletionTone);

            ui.bnDoIt.addEventListener( MouseEvent.CLICK, DoVideo );
            ui.bnAbort.addEventListener( MouseEvent.CLICK, Abort );
            
            
            CheckSetup(ui.bnTempate);
            ui.bnTempate.addEventListener( MouseEvent.CLICK, ChangeTemplateEnable );
            ui.bFindTemplate.addEventListener( MouseEvent.CLICK, BrowsePathTemplate );
            ui.tfPathTemplate.addEventListener( Event.CHANGE, onTemplateEdited );
            
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
                removeThumbs.addEventListener(Event.SELECT, RemoveThumbs);

                appToolMenu.submenu = toolMenu;
            }

            // Do a few initial things
            ui.gotoAndStop("interactive");
            ui.tfStatus.text = "";
            ui.tabChildren = true;


        }

        /** Update find status on status bar */
        protected function FindStatus(e:Event):void
        {
            //var list : Array = Find.FindBlock(root_path_media);
            var found_so_far : int = finding.results.length;
            ui.tfStatus.text = "Finding... "+found_so_far.toString();
        }

        /**
         * App is busy working.  Lock out most user controls.
        **/
        public override function Busy(e:Event=null) : void
        {
            ui.gotoAndStop(2);
            ui.gotoAndStop("working");
            ui.tfStatus.text = "...";
            ui.tabChildren = false;
        }

        /**
         * App is interactive.  User can change things again.
        **/
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

        /** Poll whether app is 'busy' or not */
        public override function isBusy() : Boolean
        {
            return "working" == ui.currentLabel;
        }


        /**
         * Process halted or error
        **/
        protected function Aborted(e:Event):void
        {
            AbortTimeouts();
            Interactive();
        }

        /**
         * Clicked abort button
        **/
        protected function Abort(e:Event):void
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
            trace("DoVideo",root_path_media.nativePath);

            /**
             * Do parameter checks before we launch into processes
            **/
            ui.tfPathVideo.text = root_path_media.nativePath;

            if( !root_path_media.exists || !root_path_media.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathVideo);
                return;
            }
            // Make sure we don't go way out of range on thumb size
            if( thumb_size < 64 )
            {
                thumb_size = 64;
                ui.tfThumbnailSize.text = THUMB_SIZE_DEFAULT.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfThumbnailSize);
                return;
            }
            if( thumb_size > 360 )
            {
                thumb_size = 360;
                ui.tfThumbnailSize.text = THUMB_SIZE_DEFAULT.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfThumbnailSize);
                return;
            }

            if( !root_path_media.exists || !root_path_media.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathVideo);
                return;
            }
            
            // If we are using external template files...
            var root : File = File.applicationDirectory;
            css_template_file   = Find.File_AddPath( root, CSS_TEMPLATE );
            index_template_file = Find.File_AddPath( root, INDEX_TEMPLATE );
            if( CheckGet( ui.bnTempate ) )
            {
                try
                {
                    css_template_file   = Find.File_AddPath( root_path_template, CSS_TEMPLATE );
                    index_template_file = Find.File_AddPath( root_path_template, INDEX_TEMPLATE );
                }
                catch( e:Error )
                {
                    trace(e.getStackTrace());
                    ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate );
                    return;
                }
                if( !index_template_file.exists )
                {
                    index_template_file = Find.File_AddPath( root, INDEX_TEMPLATE );
                    trace("Could not find index template file.  Using default.",index_template_file.nativePath);
                }
                if( !css_template_file.exists )
                {
                    css_template_file   = Find.File_AddPath( root, CSS_TEMPLATE );
                    trace("Could not find CSS template file.  Using default.",css_template_file.nativePath);
                }
            }
            if( !css_template_file.exists )
            {
                trace("Could not find default css template file.",css_template_file.nativePath);
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate );
                return;
            }
            if( !index_template_file.exists )
            {
                trace("Could not find default index template file.",index_template_file.nativePath);
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate );
                return;
            }

            // Load CSS file
            try
            {
                // CSS
                css_template = LoadText(css_template_file);
            }
            catch( e:Error )
            {
                trace( "Missing or malformed CSS", css_template_file.nativePath );
                trace(e.getStackTrace());
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate);
                Interactive();
                return;
            }

            // Load and parse player template file
            try
            {
                // Preload the various template elements we'll be writing for each folder/file
                index_template = LoadText(index_template_file);
                
                const rxFolder : RegExp = /\<\!\-\-INDEX_FOLDER(.*?)\-\-\>/ms;
                index_folder = index_template.match( rxFolder )[0];
                index_folder = index_folder.replace(rxFolder,"$1");

                const rxIndexBegin : RegExp = /\<\!\-\-INDEX_FILES_BEGIN(.*?)\-\-\>/ms;
                index_begin = index_template.match( rxIndexBegin )[0];
                index_begin = index_begin.replace(rxIndexBegin,"$1");

                const rxFileThumb : RegExp = /\<\!\-\-INDEX_FILE_THUMB(.*?)\-\-\>/ms;
                index_file = index_template.match( rxFileThumb )[0];
                index_file = index_file.replace( rxFileThumb, "$1");

                const rxFileNoThumb : RegExp = /\<\!\-\-INDEX_FILE_NOTHUMB(.*?)\-\-\>/ms;
                index_file_nothumb = index_template.match( rxFileNoThumb )[0];
                index_file_nothumb = index_file.replace( rxFileNoThumb, "$1");

                const rxIndexEnd : RegExp = /\<\!\-\-INDEX_FILES_END(.*?)\-\-\>/ms;
                index_end = index_template.match( rxIndexEnd )[0];
                index_end = index_end.replace(rxIndexEnd,"$1");
            }
            catch( e:Error )
            {
                trace( "Missing or malformed INDEX_FOLDER, INDEX_FILES_BEGIN, INDEX_FILE_THUMB, INDEX_FILE_THUMB or INDEX_FILE_NOTHUMB in", index_template_file.nativePath );
                trace(e.getStackTrace());
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate);
                Interactive();
                return;
            }
            
            // Configuration looks kosher.  Go ahead and save it.            
            CommitSharedData();

            finding = new Find( root_path_media );
            ui.tfStatus.text = "...";
            finding.addEventListener( Find.ABORT, Aborted );
            finding.addEventListener( Find.MORE, FindStatus );
            finding.addEventListener( Find.FOUND, HaveVideoFiles );

            thumbnail = new Thumbnail(ui.mcThumbnail.mcPlaceholder,thumb_size);
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
            var root_dir : File = found[0];
            try
            {
                var folder_list_db : Array = new Array();
                var file_list_db : Array = new Array();
                var thumbnail_db : Dictionary = new Dictionary();
                
                // Iterate all of the folders
                var folders : Array = Find.GetFolders(found);
                folders = folders.sort(Find.SortOnNative);

                setTimeout( ThreadPassFolder );
                var folder_iteration : int = 0;

                //for( folder_iteration = 0; folder_iteration < folders.length; ++folder_iteration )
                function ThreadPassFolder():void
                {
                    var media_files_db : Array = new Array();
                    
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
                    ui.tfStatus.text = "Folder: "+folder_iteration.toString()+"/"+folders.length.toString();
                    trace( ui.tfStatus.text );

                    var root : File = folders[folder_iteration];
                    var relPath_root : String = Find.File_relative(root,root_dir);

                    var total_files_at_this_depth : Array = Find.GetChildren( found, root );
                    var sortedFiles : Array = total_files_at_this_depth.sort(Find.SortOnNative);

                    var iteration : int;
                    var seded : String
                    var folder : File;

                    // Make folder index and start folder 
                    var relPath : String = Find.File_relative(root,root_dir);
                    var curr_depth : int = Find.File_Depth(root,root_dir) + (0 != folder_iteration);

                    // Create and build top half of index file
                    var curr_title : String = Find.File_nameext(root);
                    curr_title = Find.FixDecodeURI(curr_title);
                    curr_title = Find.EscapeQuotes(curr_title);
                    
                    var FOLDER_ID : String = relPath.replace(/[^a-zA-Z0-9]/g, '_' );

                    var index_files : String = "";
                    
                    var iFile : int;
                    var curr_file : File;
                    for( iFile = 0; iFile < sortedFiles.length; ++iFile )
                    {
                        curr_file = sortedFiles[iFile];
                        var extCurr : String = Find.File_extension(curr_file);
                        if( extCurr.match(REGEX_MP4) )
                        {
                            media_files_db.push(curr_file);

                            var curr_file_relative : String = Find.File_relative( curr_file, root_dir );
                            var curr_file_title : String = Find.File_name( curr_file );
                            curr_file_title = Find.FixDecodeURI(curr_file_title);
                            curr_file_title = Find.EscapeQuotes(curr_file_title);

                            // Thumb to-do list
                            var file_thumb : File = Find.File_newExtension(curr_file,'.jpg');
                            var curr_file_thumb : String = Find.File_relative( file_thumb, root_dir );

                            // Emit index+code to play file
                            if( CheckGet( ui.bnDoThumbs ) )
                            {
                                seded = index_file;
                                seded = seded.replace(/MEDIA_IMAGE/g,Find.FixEncodeURI(curr_file_thumb));
                            }
                            else
                            {   // No thumbnail
                                seded = index_file_nothumb;
                            }
                            seded = seded.replace(/MEDIA_PATH/g,Find.FixEncodeURI(curr_file_relative));
                            seded = seded.replace(/MEDIA_TITLE/g,Find.EscapeQuotes(curr_file_title));
                            seded = seded.replace(/FILE_STYLE/g,'');
                            index_files += seded;
                            
                        }
                        else if( extCurr.toLowerCase() == '.jpg' )
                        {
                            thumbnail_db[curr_file.nativePath] = 'true';
                        }
                    }

                    // Add missing thumbnails to 'to do' list.
                    var curr_thumb : File;
                    for( iFile = 0; iFile < media_files_db.length; ++iFile )
                    {
                        curr_file = media_files_db[iFile];
                        curr_thumb = Find.File_newExtension(curr_file,'.jpg');
                        if( !(curr_thumb.nativePath in thumbnail_db) )
                        {
                            thumbnail.AddTask( curr_file, curr_thumb );
                        }
                    }
                    
                    // Emit folder
                    seded = index_folder;
                    seded = seded.replace(/FOLDER_ID/g, FOLDER_ID);
                    var indent : String = 'padding-left:'+(LEFT_PADDING+(curr_depth*FOLDER_DEPTH))+'pt;';
                    seded = seded.replace(/FOLDER_NAME/g,curr_title);
                    if( 0 == media_files_db.length )
                    {
                        // Indent and emit disabled folder
                        const folder_disabled : String = ' pointer-events: none; opacity: 0.75;';
                        seded = seded.replace(/FOLDER_STYLE/g,indent+folder_disabled);
                        folder_list_db.push( {root:root,index:seded} );
                    }
                    else
                    {
                        // Indent enabled folder
                        seded = seded.replace(/FOLDER_STYLE/g,indent);
                        folder_list_db.push( {root:root,index:seded} );
                        
                        // Add file list div
                        seded = index_begin;
                        seded = seded.replace(/FOLDER_ID/g, FOLDER_ID);
                        seded = seded.replace(/FOLDER_STYLE/g, '');
                        seded = seded.replace(/FOLDER_NAME/g,curr_title);
                        index_files = seded + index_files + index_end;
                        file_list_db.push( {root:root,index:index_files} );
                    }
                    ++folder_iteration;
                }
                
                // Generate index.html file...
                function ThreadComplete():void
                {
                    if( folder_list_db.length > 1 )
                    {
                        // Insert folder list for little link table
                        var folder_list : String = "";
                        var iteration : int;
                        var dbCurr : Object;
                        for( iteration = 0; iteration < folder_list_db.length; ++iteration )
                        {
                            dbCurr = folder_list_db[iteration];
                            folder_list += dbCurr.index;
                        }
                        
                        var file_list : String = "";
                        for( iteration = 0; iteration < file_list_db.length; ++iteration )
                        {
                            dbCurr = file_list_db[iteration];
                            file_list += dbCurr.index;
                        }

                        var curr_title : String = Find.File_name( folders[0] );
                        var curr_title_escaped : String = Find.EscapeQuotes(curr_title);
                        
                        var index_content : String = index_template;
                        index_content = index_content.replace("/*INSERT_CSS_HERE*/",css_template);
                        index_content = index_content.replace(/TITLE_TEXT/g,curr_title_escaped);
                        index_content = index_content.replace(/THUMB_SIZE/g,thumb_size.toString());
                        index_content = index_content.replace("<!--INDEX_FOLDERS_HERE-->", folder_list);
                        index_content = index_content.replace("<!--INDEX_FILES_HERE-->",   file_list);

                        // Pack output file a bit
                        //index_content = PackOutput(index_content);
                        
                        // Now write out index file in one pass
                        var toc_file : File = Find.File_AddPath( root_dir, MAIN_TOC );
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
                trace(e.getStackTrace());
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
            root_path_media = File.desktopDirectory;
            onFolderChanged();
            CheckSet( ui.bnCompletionTone, true );
            CheckSet( ui.bnDoThumbs, true );

            CheckSet( ui.bnTempate, false );
            ChangeTemplateEnable();
            root_path_template = File.desktopDirectory;
            onTemplateChanged();
            
            thumb_size = THUMB_SIZE_DEFAULT;
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
                trace(e.getStackTrace());
                ResetSharedData();
            }

            // Verify version compatibility
            if( SO_SIGN != share_data.sign )
            {
                share_data = ResetSharedData();
                return;
            }

            // Decode the saved data
            root_path_media = new File(share_data.url_video);
            if( !root_path_media.exists )
                root_path_media = File.desktopDirectory;
            onFolderChanged();

            CheckSet( ui.bnCompletionTone, share_data.bPlayTune );
            CheckSet( ui.bnDoThumbs, share_data.bDoThumbs );

            thumb_size = share_data.thumb_size;
            ui.tfThumbnailSize.text = thumb_size.toString();

            onFolderChanged();

            CheckSet( ui.bnTempate, share_data.bTemplate );

            root_path_template = new File(share_data.url_template);
            if( !root_path_template.isDirectory )
            {
                root_path_template = File.desktopDirectory;
                CheckSet( ui.bnTempate, false );
            }
            onTemplateChanged();
            ChangeTemplateEnable();
            
            
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
            share_data.url_video = root_path_media.url;
            share_data.bPlayTune = CheckGet( ui.bnCompletionTone );
            share_data.bDoThumbs = CheckGet( ui.bnDoThumbs );
            share_data.thumb_size = thumb_size;
            share_data.bTemplate = CheckGet( ui.bnTempate );
            share_data.url_template = root_path_template.url;

            share_data.sign = SO_SIGN;

            // Commit file stream
            fs.writeObject(share_data);
            fs.close();

            // Return our object for reference
            return share_data;
        }

        /** Find path to video content */
        protected function BrowsePathVideo(e:Event=null):void
        {
            root_path_media.addEventListener(Event.SELECT, onFolderChanged);
            root_path_media.browseForDirectory("Choose a folder");
        }

        /** Open an OS Finder/Explorer/whatever browser */
        protected function OpenFolder(e:Event=null):void
        {
            root_path_media.openWithDefaultApplication();
        }


        /** Keep track if user hand-tweaked paths, so we can make them into File objects */
        protected function onFolderEdited(e:Event=null):void
        {
            if( '' == ui.tfPathVideo.text )
            {
                root_path_media.nativePath = '/';
            }
            else
            {
                try
                {
                    root_path_media.nativePath = ui.tfPathVideo.text;
                }
                catch( e:Error )
                {
                    trace(e.getStackTrace());
                }
            }
            thumb_size = int(ui.tfThumbnailSize.text);
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
        protected function onFolderChanged(e:Event=null):void
        {
            if( !root_path_media.isDirectory )
            {
                root_path_media = File.userDirectory;
            }
            ui.tfPathVideo.text = root_path_media.nativePath;
        }

        /** Enable/disable template controls */
        protected function ChangeTemplateEnable( e: MouseEvent = null ) : void
        {
            if( CheckGet( ui.bnTempate ) )
            {
                ui.bFindTemplate.mouseEnabled = true;
                ui.tfPathTemplate.mouseEnabled = true;
                ui.bFindTemplate.alpha = 1;
                ui.tfPathTemplate.alpha = 1;
            }
            else
            {
                ui.bFindTemplate.mouseEnabled = false;
                ui.tfPathTemplate.mouseEnabled = false;
                ui.bFindTemplate.alpha = 0.5;
                ui.tfPathTemplate.alpha = 0.5;
            }
            
        }
        
        /** Look for template with file browser */
        protected function BrowsePathTemplate( e: MouseEvent ) : void
        {
            root_path_template.addEventListener(Event.SELECT, onTemplateChanged );
            root_path_template.browseForDirectory("Choose a template folder");
        }
        
        /** Refresh hand edits into File */
        protected function onTemplateEdited( e: Event ) : void
        {
            if( '' == ui.tfPathTemplate.text )
            {
                root_path_template.nativePath = '/';
            }
            else
            {
                try
                {
                    root_path_template.nativePath = ui.tfPathTemplate.text;
                }
                catch( e:Error )
                {
                    trace(e.getStackTrace());
                }
            }
        }

        /** Change template path text, when something else changes it */
        protected function onTemplateChanged( e: Event = null ) : void
        {
            if( !root_path_template.isDirectory )
            {
                root_path_template = File.userDirectory;
            }
            ui.tfPathTemplate.text = root_path_template.nativePath;
        }
        
        
        /**
         * Invoke thumbnail nuker
        **/
        private function RemoveThumbs(event:Event):void
        {
            if( !root_path_media.exists || !root_path_media.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathVideo);
                return;
            }

            var warning : String = "Every JPEG from the Video Player path will be wiped out!\n\n" + root_path_media.nativePath;
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
                finding = new Find( root_path_media, OnlyMP4 )
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
                            catch( e:Error )
                            {
                                trace(e.getStackTrace());
                            }
                        }
                    }
                    Interactive();
                }
            }
        }

        /**
         * Keep file 'legible', but remove excess comments and whitespace
         * Like all such hackish regex toys, caveat emptor.
        **/
        private function PackOutput(outputFile:String):String
        {
            /* Regular expressions to eat spaces around operators */ 
            const notInQuotes : String = "";

            // Eat html multiline comments
            outputFile = outputFile.replace(/\<\!\-\-.*?\-\-\>/msg,"");

            // Eat C multiline comments (ignore '//' comments)
            outputFile = outputFile.replace(/\/\*.*?\*\//msg,"");
            
            // Eat white space around operators, not in strings
            // Doing this to html+js is a little too complex for regex.
            // It skips quoted text nicely, but html has text that's not in quotes.  Like in links.
            // List of operators...   ([/\>\<\!\=\+\*\&\|\(\)\{\}\:\;]+)[ \t]+
            // Not between quotes...  (?=(?:[^\r\n"\\]++|\\.)*+[^\r\n"\\]*+$)
            const regexOperatorSpace : RegExp = /([/\>\<\!\=\+\*\&\|\(\)\{\}\:\;]+)[ \t]+(?=(?:[^\r\n"\\]++|\\.)*+[^\r\n"\\]*+$)/msg;
            const regexSpaceOperator : RegExp = /[ \t]+([/\>\<\!\=\+\*\&\|\(\)\{\}\:\;]+)(?=(?:[^\r\n"\\]++|\\.)*+[^\r\n"\\]*+$)/msg;
            //outputFile = outputFile.replace(regexOperatorSpace,'$1');
            //outputFile = outputFile.replace(regexSpaceOperator,'$1');

            // Eat spaces at starts of lines
            outputFile = outputFile.replace(/^[ \t]+/mg,"");

            // Eat spaces at ends of lines
            outputFile = outputFile.replace(/[ \t]+$/mg,"");

            // Eat excess runs of newlines
            outputFile = outputFile.replace(/[\r\n]+/msg,"\n");
            
            return outputFile;
        }
        
    }
}
