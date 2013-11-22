
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
    
    public class JukeboxScript extends applet
    {
        internal static const SO_PATH : String = "JukeboxScriptData";
        internal static const SO_SIGN : String = "JUKEBOXSCRIPT_SIGN_00";

CONFIG::MXMLC_BUILD
{
        /** Main SWF */
        [Embed(source="./Jukebox_UI.swf", mimeType="application/octet-stream")]
        public static const baMainSwfClass : Class;
}

        /** Where the main UI lives */
        internal var ui : MovieClip;
        
        /** What to call the 'top level' index file */
        public static var HTML_PLAYER     : String = "Jukebox.html";

        /** What to call the 'TOC' file that has all of the index.htmls in it */
        public static var MAIN_TOC        : String = "index.html";
        
        /** Where to look for script template content */
        public static var SCRIPT_TEMPLATES: String ="templates/"

        /** Start of movie player and available content */
        public static var PLAYER_TEMPLATE : String = SCRIPT_TEMPLATES+"index_template.html";
        
        /** Table of contents file */
        public static var TOC_TEMPLATE    : String = SCRIPT_TEMPLATES+"TOC_template.html";
        
        /** A movie file link with player logic */
        public static var INDEX_FILE      : String = SCRIPT_TEMPLATES+"index_file.html";

        /** Link to folder index */
        public static var INDEX_INDEX     : String = SCRIPT_TEMPLATES+"index_index.html";

        /** Offset for folder depths in TOC file */
        public static var FOLDER_DEPTH : int = 32;
        
        
        /** 
         * Regular expressions that we accept as 'MP3 content' 
        **/
        public static var REGEX_MP3        : String = ".(mp3|ogg)";
        
        /** Path to do the job in */
        internal var root_path_audio : File;

        /** Finder while searching files/folders */
        internal var finding : Find;
        
        public function JukeboxScript()
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

            ui.tfPathAudio.addEventListener( Event.CHANGE, onFolderEdited );
            ui.bFindPathAudio.addEventListener( MouseEvent.CLICK, BrowsePathAudio );
            ui.bnFindExplore.addEventListener( MouseEvent.CLICK, OpenFolder );
            CheckSetup(ui.bnTOC);
            CheckSetup(ui.bnCompletionTone);
            
            ui.bnDoIt.addEventListener( MouseEvent.CLICK, DoAudio );
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
                var removeIndexes:NativeMenuItem = toolMenu.addItem(new NativeMenuItem("Remove "+HTML_PLAYER+" files")); 
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
            //var list : Array = Find.FindBlock(root_path_audio);
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
         * Process audio tree
        **/
        protected function DoAudio(e:Event=null):void
        {
            trace("DoAudio",root_path_audio.nativePath);

            /**
             * Do parameter checks before we launch into processes
            **/
            ui.tfPathAudio.text = root_path_audio.nativePath;

            if( !root_path_audio.exists || !root_path_audio.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathAudio);
                return;
            }

            CommitSharedData();
            
            // MP3, PNG, folders
            var rxMP3 : RegExp = new RegExp(REGEX_MP3,"i")
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
                return null == ext.match( rxMP3 );
            }
            
            finding = new Find( root_path_audio, filter_mp4_png_folders );
            ui.tfStatus.text = "...";
            finding.addEventListener( Find.ABORT, Aborted );
            finding.addEventListener( Find.MORE, FindStatus );
            finding.addEventListener( Find.FOUND, HaveAudioFiles );

            Busy();

        }
        
        /** Folder find is done.  Now decide what to do with it.  */
        protected function HaveAudioFiles(e:Event=null):void
        {
            trace("Tree");
            DoAudioFilesTree(finding.results);
        }

        /**
         * Finished exporting audio files
        **/
        protected function AudioFilesComplete(e:Event=null):void
        {
            ui.tfStatus.text = "";
            Interactive();
        }

        
        /**
         * Recursively generates files for each folder, and generates a master
         * index for all.
         *
         * This will definitely load individual pages a lot faster, but you'll
         * add some more clutter to your directory tree for all of the AudioPlayer
         * files.  
         *
         * Simpler UI without folding folders.  Just one index.html at the root
         * like the other ones, but containing only links to folders containing 
         * more content.
        **/
        protected function DoAudioFilesTree(found:Array):void
        {
            try
            {
                // Preload the various template elements we'll be writing for each folder/file
                var index_template : String = LoadText(PLAYER_TEMPLATE);
                var index_index : String    = LoadText(INDEX_INDEX); 
                var index_file : String     = LoadText(INDEX_FILE); 
                
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

                    ui.tfStatus.text = folder_iteration.toString()+"/"+folders.length.toString();

                    // Don't write index files in folders with no audio content
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
                        seded = index_template;
                        seded = seded.replace(/TITLE_TEXT/g,curr_title);
                        var index_content : String = seded;
                        var index_files : String = "";
    
                        // Iterate child folders and generate links to them
                        for( iteration = 1; iteration < curr_folders.length; ++iteration )
                        {
                            var curr_folder : File  = curr_folders[iteration];
    
                            // Filter folders with no movies in any children from lists
                            total_files_folders_at_this_depth = Find.GetChildren( found, curr_folder, int.MAX_VALUE );
                            total_files_at_this_depth = Find.GetFiles(total_files_folders_at_this_depth);
                            if( total_files_at_this_depth.length > 0 )
                            {
                                var curr_index : File = Find.File_AddPath( curr_folder, HTML_PLAYER );
                                var curr_index_title : String = Find.File_nameext( curr_folder );
                                var curr_index_relative : String = Find.File_relative( curr_index, root );
        
                                // Emit index for child folder
                                seded = index_index;
                                seded = seded.replace(/FOLDER_PATH/g,curr_index_relative);
                                seded = seded.replace(/FOLDER_TITLE/g,curr_index_title);                      
                                seded = seded.replace(/FOLDER_STYLE/g,'');
                                index_files += seded;
                            }
                        }
                        
                        if( 0 != curr_files.length )
                        {
                            index_files += "<br/><br/>\n";
                        }
                        
                        // Iterate files and generate code 
                        for( iteration = 0; iteration < curr_files.length; ++iteration )
                        {
                            var curr_file : File = curr_files[iteration];
                            var curr_file_relative : String = Find.File_relative( curr_file, root );
                            var curr_file_title : String = Find.File_name( curr_file );
                            
                            // Emit index+code to play file
                            seded = index_file;
                            seded = seded.replace(/MEDIA_PATH/g,curr_file_relative);
                            seded = seded.replace(/MUSIC_TITLE/g,curr_file_title);
                            seded = seded.replace(/FILE_STYLE/g,'');
                            index_files += seded;
                            
                        }
    
                        index_content = index_content.replace("<!--INDEXES_HERE-->",index_files);

                        // Now write out index file in one pass
                        var curr_index_file : File = Find.File_AddPath( root, HTML_PLAYER );
                        var fs : FileStream = new FileStream();
                        fs.open( curr_index_file, FileMode.WRITE );
                        fs.writeUTFBytes(index_content);
                        fs.close();
                    }
                    
                }

                function ThreadComplete():void
                {
                    // If user wanted a flattened table of contents, make one.
                    if( CheckGet( ui.bnTOC ) )
                    {
                        DoTOC(found);
                    }
                    AudioFilesComplete();
                }
            }
            catch( e:Error )
            {
                trace(e);
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathAudio);
                Interactive();
            }
            // Fall out; timer threads are in charge
        }

        /**
         * Iterate through folders and generate a flattened Table of Contents 
         * of AudioPlayer.html files, throughout the tree.
        **/
        protected function DoTOC(found:Array):void
        {
            var index_template : String = LoadText(TOC_TEMPLATE);
            var index_index : String    = LoadText(INDEX_INDEX); 

            var folders : Array = Find.GetFolders(found);
            var root : File = folders[0];
            var curr_title : String = Find.File_nameext(root);
            var seded : String;
            var bExportedLinks : Boolean = false;
            
            seded = index_template;
            seded = seded.replace(/TITLE_TEXT/g,curr_title);
            
            var index_content : String = seded;
            var folder_list : String = "";
            
            var folder_iteration : int;
            for( folder_iteration = 1; folder_iteration < folders.length; ++folder_iteration )
            {
                // Create and build top half of index file
                var curr_folder : File  = folders[folder_iteration];
                var curr_index_file : File = Find.File_AddPath( curr_folder, HTML_PLAYER );
                if( curr_index_file.exists )
                {
                    var curr_depth : int = Find.File_Depth(curr_folder,root);
                    var curr_index : File = Find.File_AddPath( curr_folder, HTML_PLAYER );
                    var curr_index_title : String = Find.File_nameext( curr_folder );
                    var curr_index_relative : String = Find.File_relative( curr_index, root );

                    // Emit index for child folder
                    seded = index_index;
                    seded = seded.replace(/FOLDER_PATH/g,curr_index_relative);
                    seded = seded.replace(/FOLDER_TITLE/g,curr_index_title);                      
                    seded = seded.replace(/FOLDER_STYLE/g,'padding-left:'+(curr_depth*FOLDER_DEPTH)+'px;');
                    bExportedLinks = true;
                    folder_list += seded;
                }
            }
            
            // Insert folder list into file template
            index_content = index_content.replace("<!--INDEXES_HERE-->",folder_list);
            
            var toc_file : File = Find.File_AddPath( root, MAIN_TOC );
            if( bExportedLinks )
            {
                // Now write out index file in one pass
                var fs : FileStream = new FileStream();
                fs.open( toc_file, FileMode.WRITE );
                fs.writeUTFBytes(index_content);
                fs.close();
            }
            else
            {
                if( toc_file.exists )
                    toc_file.moveToTrashAsync();
            }
        }

        /**
         * Reset persistent settings
        **/
        protected function ResetSharedData() : Object
        {
            root_path_audio = File.desktopDirectory;
            onFolderChanged();
            CheckSet( ui.bnTOC, true );
            CheckSet( ui.bnCompletionTone, true );
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
            root_path_audio = new File(share_data.url_audio);
            if( !root_path_audio.exists )
                root_path_audio = File.desktopDirectory;
            onFolderChanged();

            CheckSet( ui.bnTOC, share_data.bDoTOC );
            CheckSet( ui.bnCompletionTone, share_data.bPlayTune );
            
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
            share_data.url_audio = root_path_audio.url;
            share_data.bDoTOC = CheckGet( ui.bnTOC );
            share_data.bPlayTune = CheckGet( ui.bnCompletionTone );
            
            share_data.sign = SO_SIGN;

            // Commit file stream
            fs.writeObject(share_data);
            fs.close();
            
            // Return our object for reference
            return share_data;
        }
        
        /** Find path to audio content */
        internal function BrowsePathAudio(e:Event=null):void
        {
            root_path_audio.addEventListener(Event.SELECT, onFolderChanged);
            root_path_audio.browseForDirectory("Choose a folder");
        }
        
        /** Open an OS Finder/Explorer/whatever browser */
        internal function OpenFolder(e:Event=null):void
        {
            root_path_audio.openWithDefaultApplication();
        }
        

        /** Keep track if user hand-tweaked paths, so we can make them into File objects */
        internal function onFolderEdited(e:Event=null):void
        {
            root_path_audio.nativePath = ui.tfPathAudio.text;
        }

        /** User navigated a different path */
        internal function onFolderChanged(e:Event=null):void
        {
            ui.tfPathAudio.text = root_path_audio.nativePath; 
        }


        /**
         * Invoke index file nuker
        **/
        private function RemoveIndexes(event:Event):void 
        { 
            if( !root_path_audio.exists || !root_path_audio.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathAudio);
                return;
            }

            var warning : String = "Every "+HTML_PLAYER+" from the Audio Player path will be wiped out!\n\n" + root_path_audio.nativePath;
            AreYouSure( GetMovieClip("UI_AreYouSure"), "Remove Audio Index Files", yeah, warning, "DO IT!", "ABORT!" );
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
                finding = new Find( root_path_audio, OnlyHTML );
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
                        found[i].moveToTrashAsync();
                    }
                    Interactive();
                }
            }
        } 
        
    }
}
    
