
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
        protected static const SO_SIGN : String = "VIDEOSCRIPT_SIGN_1.2";

CONFIG::MXMLC_BUILD
{
        /** Main SWF */
        [Embed(source="./VideoWebScript_UI.swf", mimeType="application/octet-stream")]
        public static const baMainSwfClass : Class;
}

        /** Where the main UI lives */
        protected var ui : MovieClip;
        
        /** What to call the 'top level' index file */
        public static const HTML_PLAYER     : String = "VideoPlayer.html";

        /** What to call the 'TOC' file that has all of the index.htmls in it */
        public static const MAIN_TOC        : String = "index.html";

        /** Where to look for script template content */
        public static const SCRIPT_TEMPLATES: String ="kiosk"

        /** Start of movie player and available content */
        public static const PLAYER_TEMPLATE : String = "player_template.html";

        /** A movie file link with player logic */
        public static const INDEX_TEMPLATE  : String = "index_template.html";
        
        /** A css file with theming details */
        public static const CSS_TEMPLATE  : String = "template.css";

        /** Width of thumbnails for video */
        public static const THUMB_SIZE_DEFAULT : int = 240;

        /** Offset for folder depths in TOC file */
        public static const FOLDER_DEPTH : int = 32;

        /** File/folder left padding*/
        public static const LEFT_PADDING : int = 0;

        /** Regular expressions that we accept as 'MP4 content'
            Lots of synonyms for 'mp4'.  Many of these may have incompatible CODECs
            or DRM, or other proprietary extensions in them.
        **/
        public static const REGEX_MP4        : String = ".(mp4|m4v|m4p|m4r|3gp|3g2)";

        /** Regular expressions that we accept as 'jpeg content'*/
        public static const REGEX_JPEG       : String = ".(jpg|jpeg)";

        /** Path to do the job in */
        protected var root_path_media : File;
        
        /** Path to get templates from */
        protected var root_path_template : File;

        /** Path to file containing player template */
        protected var player_template_file : File;

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
            var root : File = Find.File_AddPath( File.applicationDirectory, SCRIPT_TEMPLATES );
            css_template_file   = Find.File_AddPath( root, CSS_TEMPLATE );
            player_template_file= Find.File_AddPath( root, PLAYER_TEMPLATE );
            index_template_file = Find.File_AddPath( root, INDEX_TEMPLATE );
            if( CheckGet( ui.bnTempate ) )
            {
                try
                {
                    css_template_file   = Find.File_AddPath( root_path_template, CSS_TEMPLATE );
                    player_template_file= Find.File_AddPath( root_path_template, PLAYER_TEMPLATE );
                    index_template_file = Find.File_AddPath( root_path_template, INDEX_TEMPLATE );
                }
                catch( e:Error )
                {
                    trace(e.getStackTrace());
                    ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate );
                    return;
                }
                if( !player_template_file.exists )
                {
                    player_template_file= Find.File_AddPath( root, PLAYER_TEMPLATE );
                    trace("Could not find player template file.  Using default.");
                }
                if( !index_template_file.exists )
                {
                    index_template_file = Find.File_AddPath( root, INDEX_TEMPLATE );
                    trace("Could not find index template file.  Using default.");
                }
                if( !css_template_file.exists )
                {
                    css_template_file   = Find.File_AddPath( root, CSS_TEMPLATE );
                    trace("Could not find CSS template file.  Using default.");
                }
            }

            // Configuration looks kosher.  Go ahead and save it.            
            CommitSharedData();

            // MP4, PNG, folders
            var rxMP4 : RegExp = new RegExp(REGEX_MP4,"i");
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

            finding = new Find( root_path_media, filter_mp4_png_folders );
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
                thumbnail.AddTask( file, file_thumb );
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
                // CSS
                var css_template : String = LoadText(css_template_file);
            }
            catch( e:Error )
            {
                trace( "Missing or malformed CSS", css_template_file.nativePath );
                trace(e.getStackTrace());
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate);
                Interactive();
                return;
            }
            
            try
            {
                // Preload the various template elements we'll be writing for each folder/file
                var player_template : String    = LoadText(player_template_file);

                const rxFolder : RegExp = /\<\!\-\-INDEX_INDEX(.*?)\-\-\>/ms;
                var index_index : String = player_template.match( rxFolder )[0];
                index_index = index_index.replace(rxFolder,"$1");

                const rxFileThumb : RegExp = /\<\!\-\-INDEX_FILE(.*?)\-\-\>/ms;
                var index_file : String = player_template.match( rxFileThumb )[0];
                index_file = index_file.replace( rxFileThumb, "$1");

                const rxFileNoThumb : RegExp = /\<\!\-\-INDEX_FILE_NOTHUMB(.*?)\-\-\>/ms;
                var index_file_nothumb : String = player_template.match( rxFileNoThumb )[0];
                index_file_nothumb = index_file_nothumb.replace(rxFileNoThumb,"$1");
            }
            catch( e:Error )
            {
                trace( "Missing or malformed INDEX_INDEX or INDEX_FILE or INDEX_FILE_NOTHUMB in", player_template_file.nativePath );
                trace(e.getStackTrace());
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate);
                Interactive();
                return;
            }
                
            try
            {
                // TOC pieces
                var index_template : String = LoadText(index_template_file);

                const rxIndexToc_Small : RegExp = /\<\!\-\-INDEX_SMALL(.*?)\-\-\>/ms;
                var index_small : String  = index_template.match( rxIndexToc_Small )[0];
                index_small = index_small.replace( rxIndexToc_Small, "$1" );
                
                const rxIndexToc_File : RegExp = /\<\!\-\-INDEX_TOC_FILE(.*?)\-\-\>/ms;
                var index_toc_file : String = index_template.match( rxIndexToc_File )[0];
                index_toc_file = index_toc_file.replace( rxIndexToc_File, "$1" );
                
                const rxIndexToc_Folder : RegExp = /\<\!\-\-INDEX_TOC_FOLDER(.*?)\-\-\>/ms;
                var index_toc_folder : String  = index_template.match( rxIndexToc_Folder )[0];
                index_toc_folder = index_toc_folder.replace( rxIndexToc_Folder, "$1" );
            }
            catch( e:Error )
            {
                trace( "Missing or malformed INDEX_SMALL or INDEX_TOC_FILE or INDEX_TOC_FOLDER in", index_template_file.nativePath );
                trace(e.getStackTrace());
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate);
                Interactive();
                return;
            }
            
            
            try
            {
                
                var folder_list_db : Array = new Array();
                var file_list_index : String = "";
                var bExportedLinks : Boolean = false;

                // Iterate all of the folders
                var folders : Array = Find.GetFolders(found);
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

                        // Create and build top half of index file
                        var curr_title : String = Find.File_nameext(root);
                        curr_title = Find.FixDecodeURI(curr_title);

                        seded = player_template;
                        seded = seded.replace(/THUMB_SIZE/g,thumb_size.toString());
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
                                    // Generate index folder name heading for toc main list, if folder contains playable files
                                    if( 0 != curr_files.length )
                                    {
                                        seded = index_toc_folder;
                                        seded = seded.replace(/FOLDER_PATH/g,Find.FixEncodeURI(curr_index_absolute));
                                        seded = seded.replace(/FOLDER_TITLE/g,Find.EscapeQuotes(curr_index_title));
                                        seded = seded.replace(/FOLDER_STYLE/g,"");
                                        file_list_index += seded;
                                    }
                                }
                                else
                                {

                                    // Emit index for child folder
                                    seded = index_index;
                                    seded = seded.replace(/FOLDER_PATH/g,Find.FixEncodeURI(curr_index_relative));
                                    seded = seded.replace(/FOLDER_TITLE/g,Find.EscapeQuotes(curr_index_title));
                                    seded = seded.replace(/FOLDER_STYLE/g,'');
                                    index_files += seded;

                                    // Generate indexes for TOC
                                    seded = index_small;
                                    seded = seded.replace(/FOLDER_PATH/g,Find.FixEncodeURI(curr_index_absolute));
                                    seded = seded.replace(/FOLDER_TITLE/g,Find.EscapeQuotes(curr_index_title));
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
                                seded = index_file_nothumb;
                            }
                            seded = seded.replace(/MEDIA_PATH/g,Find.FixEncodeURI(curr_file_relative));
                            seded = seded.replace(/MEDIA_TITLE/g,Find.EscapeQuotes(curr_file_title));
                            seded = seded.replace(/FILE_STYLE/g,'');
                            index_files += seded;

                            // Emit absolute index to play from TOC
                            curr_file_relative = Find.File_relative( curr_index_file, folders[0] );
                            var curr_name   : String = Find.FixDecodeURI(Find.File_nameext(curr_file));
                            var curr_path   : String = curr_file_relative + '?' + curr_name;
                            seded = index_toc_file;
                            seded = seded.replace(/MEDIA_PATH/g,Find.FixEncodeURI(curr_path));
                            seded = seded.replace(/MEDIA_TITLE/g,Find.EscapeQuotes(curr_file_title));
                            seded = seded.replace(/FILE_STYLE/g,'');
                            file_list_index += seded;

                            bExportedLinks = true;
                        }

                        index_content = index_content.replace("/*INSERT_CSS_HERE*/",css_template);
                        index_content = index_content.replace("<!--INDEXES_HERE-->",index_files);

                        // Pack output file a bit
                        index_content = PackOutput(index_content);
                        
                        // Now write out index file in one pass
                        WriteAsync( curr_index_file, index_content );
                    }

                }

                function ThreadComplete():void
                {
                    // If user wanted a flattened table of contents, make one.
                    // We already did all the work for it, above
                    // Don't generate the TOC if there's only one folder
                    if( CheckGet( ui.bnTOC ) && folder_list_db.length > 1 )
                    {
                        // Insert folder list for little link table
                        var folder_list : String = "";
                        folder_list_db.sort(byNativePath);
                        function byNativePath( p1:Object, p2:Object ) : int
                        {
                            return Find.SortOnNative( p1.path, p2.path );
                        }
                        var iteration : int;
                        for( iteration = 0; iteration < folder_list_db.length; ++iteration )
                        {
                            var dbCurr : Object = folder_list_db[iteration];
                            folder_list += dbCurr.item;
                        }

                        var index_content : String = index_template;
                        index_content = index_content.replace(/THUMB_SIZE/g,thumb_size.toString());
                        //index_content = index_content.replace(/TITLE_TEXT/g,curr_title);
                        index_content = index_content.replace("/*INSERT_CSS_HERE*/",css_template);
                        index_content = index_content.replace("<!--INDEXES_HERE-->",file_list_index);
                        index_content = index_content.replace("<!--FOLDERS_HERE-->",folder_list);

                        // Pack output file a bit
                        index_content = PackOutput(index_content);
                        
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
            CheckSet( ui.bnTOC, true );
            CheckSet( ui.bnCompletionTone, true );
            CheckSet( ui.bnDoThumbs, true );

            CheckSet( ui.bnTempate, false );
            ChangeTemplateEnable();
            root_path_template = Find.File_AddPath( File.applicationDirectory, SCRIPT_TEMPLATES );
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

            CheckSet( ui.bnTOC, share_data.bDoTOC );
            CheckSet( ui.bnCompletionTone, share_data.bPlayTune );
            CheckSet( ui.bnDoThumbs, share_data.bDoThumbs );

            thumb_size = share_data.thumb_size;
            ui.tfThumbnailSize.text = thumb_size.toString();

            onFolderChanged();

            CheckSet( ui.bnTempate, share_data.bTemplate );

            root_path_template = new File(share_data.url_template);
            if( !root_path_template.isDirectory )
            {
                root_path_template = Find.File_AddPath( File.applicationDirectory, SCRIPT_TEMPLATES );
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
            share_data.bDoTOC = CheckGet( ui.bnTOC );
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
         * Invoke index file nuker
        **/
        private function RemoveIndexes(event:Event):void
        {
            if( !root_path_media.exists || !root_path_media.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathVideo);
                return;
            }

            var warning : String = "Every "+HTML_PLAYER+" from the Video Player path will be wiped out!\n\n" + root_path_media.nativePath;
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
                finding = new Find( root_path_media, OnlyHTML );
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
                        catch( e:Error )
                        {
                            trace(e.getStackTrace());
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
