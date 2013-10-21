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
    
    /**
     * Contact sheet generator
     *
     * Build a preview frame of little images, that link to the full-sized ones.
     *
     * Add some means of viewing selected exif details, if present
    **/
    public class ContactSheet extends applet
    {
        internal static const SO_PATH : String = "ContactSheetData";
        internal static const SO_SIGN : String = "CONTACT_SIGN_00";

CONFIG::MXMLC_BUILD
{
        /** Main SWF */
        [Embed(source="./ContactSheet_UI.swf", mimeType="application/octet-stream")]
        public static const baMainSwfClass : Class;
}

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

        /** Width of thumbnails for image */
        public static var THUMB_SIZE      : int = 240;

        /** Width of thumbnails for image */
        public static var COLUMNS         : int = 4;
        
        /** Offset for folder depths in TOC file */
        public static var FOLDER_DEPTH : int = 32;
        
        /** Regular expressions that we accept as 'JPEG content'*/
        public static var REGEX_JPEG       : String = ".(jpg|jpeg)";
        
        /** Path to do the job in */
        internal var root_path_image : File;

        /** Finder while searching files/folders */
        internal var finding : Find;

        public function ContactSheet()
        {
            super();

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

            ui.tfPathImages.addEventListener( Event.CHANGE, onFolderEdited );
            ui.tfThumbnailSize.addEventListener( Event.CHANGE, onFolderEdited );
            ui.tfThumbnailSize.maxChars = 3;
            ui.tfThumbnailSize.restrict = "0-9";
            ui.tfColumns.addEventListener( Event.CHANGE, onFolderEdited );
            ui.tfColumns.maxChars = 3;
            ui.tfColumns.restrict = "0-9";
            ui.bFindPathImages.addEventListener( MouseEvent.CLICK, BrowsePathVideo );
            ui.bnFindExplore.addEventListener( MouseEvent.CLICK, OpenFolder );
            CheckSetup(ui.bnTOC);
            CheckSetup(ui.bnCompletionTone);
            
            ui.bnDoIt.addEventListener( MouseEvent.CLICK, DoImages );
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
                var removeIndexes:NativeMenuItem = toolMenu.addItem(new NativeMenuItem("Remove index.html files")); 
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
            //var list : Array = Find.FindBlock(root_path_image);
            var found_so_far : int = finding.results.length;
            ui.tfStatus.text = found_so_far.toString();
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
        }
        
        /**
         * Process image tree
        **/
        protected function DoImages(e:Event=null):void
        {
            trace("DoImages",root_path_image.nativePath);

            /**
             * Do parameter checks before we launch into processes
            **/
            ui.tfPathImages.text = root_path_image.nativePath;

            if( !root_path_image.exists || !root_path_image.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathImages);
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
            
            if( COLUMNS < 1 )
            {
                COLUMNS = 1;
                ui.tfColumns.text = COLUMNS.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfColumns);
                return;
            }
            if( COLUMNS * THUMB_SIZE > 8192 )
            {
                COLUMNS = int(8192 / THUMB_SIZE);
                ui.tfColumns.text = COLUMNS.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfColumns);
                return;
            }
                
            CommitSharedData();
            
            // JPEG images and folders containing them
            var rxMP4 : RegExp = new RegExp(REGEX_JPEG,"i")
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
            
            finding = new Find( root_path_image, filter_mp4_png_folders );
            ui.tfStatus.text = "...";
            finding.addEventListener( Find.ABORT, Aborted );
            finding.addEventListener( Find.MORE, FindStatus );
            finding.addEventListener( Find.FOUND, HaveImageFiles );

            Busy();

        }
        
        /** Folder find is done.  Now decide what to do with it.  */
        protected function HaveImageFiles(e:Event=null):void
        {
            trace("Tree");
            DoImageFileTree(finding.results);
        }

        /**
         * Finished exporting image files
        **/
        protected function ImageFilesComplete(e:Event=null):void
        {
            ui.tfStatus.text = "";
            Interactive();
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
        protected function DoImageFileTree(found:Array):void
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
                applet.setTimeout(ThreadPassFolder);

                var folder_iteration : int = 0;
                //for( folder_iteration = 0; folder_iteration < folders.length; ++folder_iteration )
                function ThreadPassFolder():void
                {
                    if( folder_iteration < folders.length )
                    {
                        // Do next pass
                        applet.setTimeout(ThreadPassFolder);
                    }
                    else
                    {
                        // Break out of 'threaded' loop
                        // Bottom part of file index file; all done
                        applet.setTimeout(ThreadComplete);
                        return;
                    }
                    
                    var iteration : int;
                    var seded : String
                    var folder : File;
                    var root : File = folders[folder_iteration++];

                    ui.tfStatus.text = folder_iteration.toString()+"/"+folders.length.toString();

                    // Don't write index files in folders with no image content
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
                    ImageFilesComplete();
                }
            }
            catch( e:Error )
            {
                trace(e);
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathImages);
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
            root_path_image = File.desktopDirectory;
            onFolderChanged();
            CheckSet( ui.bnTOC, true );
            CheckSet( ui.bnCompletionTone, true );
            
            THUMB_SIZE = 240;
            COLUMNS = 4;
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
            root_path_image = new File(share_data.url_image);
            if( !root_path_image.exists )
                root_path_image = File.desktopDirectory;
            onFolderChanged();
            CheckSet( ui.bnTOC, share_data.bDoTOC );
            CheckSet( ui.bnCompletionTone, share_data.bPlayTune );

            THUMB_SIZE = share_data.thumb_size;
            ui.tfThumbnailSize.text = THUMB_SIZE.toString();
            COLUMNS = share_data.columns;
            ui.tfColumns.text = COLUMNS.toString();
            
            //onFolderChanged();

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
            share_data.url_image = root_path_image.url;
            share_data.bDoTOC = CheckGet( ui.bnTOC );
            share_data.bPlayTune = CheckGet( ui.bnCompletionTone );
            share_data.thumb_size = THUMB_SIZE;
            share_data.columns = COLUMNS;
            share_data.sign = SO_SIGN;

            // Commit file stream
            fs.writeObject(share_data);
            fs.close();
            
            // Return our object for reference
            return share_data;
        }
        
        /** Find path to image content */
        internal function BrowsePathVideo(e:Event=null):void
        {
            root_path_image.addEventListener(Event.SELECT, onFolderChanged);
            root_path_image.browseForDirectory("Choose a folder");
        }
        
        /** Open an OS Finder/Explorer/whatever browser */
        internal function OpenFolder(e:Event=null):void
        {
            root_path_image.openWithDefaultApplication();
        }
        

        /** Keep track if user hand-tweaked paths, so we can make them into File objects */
        internal function onFolderEdited(e:Event=null):void
        {
            root_path_image.nativePath = ui.tfPathImages.text;
            THUMB_SIZE = int(ui.tfThumbnailSize.text);
            COLUMNS = int(ui.tfColumns.text);
        }

        /** User navigated a different path */
        internal function onFolderChanged(e:Event=null):void
        {
            ui.tfPathImages.text = root_path_image.nativePath; 
        }

        /**
         * Invoke index file nuker
        **/
        private function RemoveIndexes(event:Event):void 
        { 
            if( !root_path_image.exists || !root_path_image.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathImages);
                return;
            }

            var warning : String = "Every "+MAIN_INDEX+" from the Video Player path will be wiped out!\n\n" + root_path_image.nativePath;
            AreYouSure( GetMovieClip("UI_AreYouSure"), "Remove Video Index Files", yeah, warning, "DO IT!", "ABORT!" );
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
                finding = new Find( root_path_image, OnlyHTML );
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
        
        
    }
}
    
