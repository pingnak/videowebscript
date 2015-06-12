
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
    import flash.ui.*;
    import flash.globalization.*;

    import flash.desktop.NativeApplication; 
    import flash.filesystem.*;
    
    public class JukeboxScript extends applet
    {
        protected static const SO_PATH : String = "JukeboxScriptData";
        protected static const SO_SIGN : String = "MEDIASCRIPT_SIGN_2.2";

CONFIG::MXMLC_BUILD
{
        /** Main SWF */
        [Embed(source="./Jukebox_UI.swf", mimeType="application/octet-stream")]
        public static const baMainSwfClass : Class;
}

        /** Where the main UI lives */
        protected var ui : MovieClip;
        
        /** What to call the 'top level' index file */
        public static const HTML_PLAYER     : String = "Jukebox.html";

        /** What to call the 'TOC' file that has all of the index.htmls in it */
        public static const MAIN_TOC        : String = "index.html";

        /** Start of movie player and available content */
        public static const INDEX_TEMPLATE  : String = "audio_template.html";
        
        /** A css file with theming details */
        public static const CSS_TEMPLATE  : String = "template.css";
        
        /** Offset for folder depths in TOC file */
        public static const FOLDER_DEPTH : int = 16;

        /** File/folder left padding*/        
        public static const LEFT_PADDING : int = 4;
        
        /** Regex to match media files */
        public static const rxMEDIA : RegExp = /\.(aac|mp3|ogg|oga|m4a)$/i;

        /** Regex to match play list files */
        public static const rxPLAY_LISTS : RegExp = /\.(asx|aimppl|bio|fpl|kpl|m3u|m3u8|pla|plc|pls|plist|smil|txt|vlc|wpl|xml|xpl|xspf|zpl)$/i;
        
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

        /** CSS template file, loaded */
        protected var css_template : String

        /** Player template file, loaded */
        protected var index_template : String;

        /** Top level folder template */
        protected var index_folder : String;

        /** Play list folder item */
        protected var index_playlist : String;

        /** Start of folder group */
        protected var index_begin : String;
        
        /** Index file with thumbnail */
        protected var index_file : String;

        /** Index file without thumbnail */
        protected var index_file_nothumb : String;

        /** End of folder group */
        protected var index_end : String;
        
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

            ui.tfPathMedia.addEventListener( Event.CHANGE, onFolderEdited );
            ui.tfPathMedia.addEventListener( KeyboardEvent.KEY_DOWN, HitEnter );
            ui.bFindPathMedia.addEventListener( MouseEvent.CLICK, BrowsePathMedia );
            ui.bnFindExplore.addEventListener( MouseEvent.CLICK, OpenFolder );
            CheckSetup(ui.bnCompletionTone);

            ui.bnDoIt.addEventListener( MouseEvent.CLICK, DoMedia );
            ui.bnAbort.addEventListener( MouseEvent.CLICK, Abort );

            CheckSetup(ui.bnTempate);
            ui.bnTempate.addEventListener( MouseEvent.CLICK, ChangeTemplateEnable );
            ui.bFindTemplate.addEventListener( MouseEvent.CLICK, BrowsePathTemplate );
            ui.tfPathTemplate.addEventListener( Event.CHANGE, onTemplateEdited );
            
            LoadSharedData();

            // Do a few initial things
            ui.gotoAndStop("interactive");
            ui.tfStatus.text = "";
            ui.tabChildren = true;
            
        }

        protected function FindStatus(e:Event):void
        {
            //var list : Array = Find.FindBlock(root_path_media);
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
        }
        
        /**
         * Process media tree
        **/
        protected function DoMedia(e:Event=null):void
        {
            trace("DoMedia",root_path_media.nativePath);

            /**
             * Do parameter checks before we launch into processes
            **/
            ui.tfPathMedia.text = root_path_media.nativePath;

            if( !root_path_media.exists || !root_path_media.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathMedia);
                return;
            }

            var root : File = File.applicationDirectory;
            css_template_file   = Find.File_AddPath( root, CSS_TEMPLATE );
            index_template_file = Find.File_AddPath( root, INDEX_TEMPLATE );

            // If we are using external template files...
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
                if( !index_template_file.exists && !css_template_file.exists )
                {
                    ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate );
                    trace("Could not find expected files in",css_template_file.nativePath);
                    return;
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

            try
            {
                // TOC pieces
                index_template = LoadText(index_template_file);

                const rxIndexToc_Folder : RegExp = /\<\!\-\-INDEX_FOLDER(.*?)\-\-\>/ms;
                index_folder = index_template.match( rxIndexToc_Folder )[0];
                index_folder = index_folder.replace( rxIndexToc_Folder, "$1" );

                const rxIndexToc_Playlist : RegExp = /\<\!\-\-INDEX_PLAYLIST(.*?)\-\-\>/ms;
                index_playlist = index_template.match( rxIndexToc_Playlist )[0];
                index_playlist = index_playlist.replace( rxIndexToc_Playlist, "$1" );
                
                const rxIndexToc_Files : RegExp = /\<\!\-\-INDEX_FILES_BEGIN(.*?)\-\-\>/ms;
                index_begin = index_template.match( rxIndexToc_Files )[0];
                index_begin = index_begin.replace( rxIndexToc_Files, "$1" );

                const rxFileThumb : RegExp = /\<\!\-\-INDEX_ITEM_THUMB(.*?)\-\-\>/ms;
                index_file = index_template.match( rxFileThumb )[0];
                index_file = index_file.replace( rxFileThumb, "$1");

                const rxFileNoThumb : RegExp = /\<\!\-\-INDEX_ITEM_NOTHUMB(.*?)\-\-\>/ms;
                index_file_nothumb = index_template.match( rxFileNoThumb )[0];
                index_file_nothumb = index_file_nothumb.replace( rxFileNoThumb, "$1");
                
                const rxIndexToc_FilesEnd : RegExp = /\<\!\-\-INDEX_FILES_END(.*?)\-\-\>/ms;
                index_end = index_template.match( rxIndexToc_FilesEnd )[0];
                index_end = index_end.replace( rxIndexToc_FilesEnd, "$1" );
            }
            catch( e:Error )
            {
                trace( "Missing or malformed INDEX_SMALL or INDEX_TOC_FILE or INDEX_TOC_FOLDER in", index_template_file.nativePath );
                trace(e.getStackTrace());
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate);
                Interactive();
                return;
            }
            
            CommitSharedData();
           
            finding = new Find( root_path_media );
            ui.tfStatus.text = "...";
            finding.addEventListener( Find.ABORT, Aborted );
            finding.addEventListener( Find.MORE, FindStatus );
            finding.addEventListener( Find.FOUND, HaveMediaFiles );

            Busy();

        }
        
        /** Folder find is done.  Now decide what to do with it.  */
        protected function HaveMediaFiles(e:Event=null):void
        {
            trace("Tree");
            DoMediaFilesTree(finding.results);
        }

        /**
         * Finished exporting media files
        **/
        protected function MediaFilesComplete(e:Event=null):void
        {
            ui.tfStatus.text = "";
            Interactive();
        }

        
        /**
         * Recursively generates files for each folder, and generates a master
         * index for all.
         *
         * This will definitely load individual pages a lot faster, but you'll
         * add some more clutter to your directory tree for all of the MediaPlayer
         * files.  
         *
         * Simpler UI without folding folders.  Just one index.html at the root
         * like the other ones, but containing only links to folders containing 
         * more content.
        **/
        protected function DoMediaFilesTree(found:Array):void
        {
            var root_dir : File = found[0];
            //try
            {
                var play_list_db : Array = new Array();
                var media_files_db : Array = [];
                var all_play_lists : Array = new Array();
                
                var folder_list_db : Array = new Array();
                var file_list_db : Array = new Array();
                var file_list_index : String = "";

                // Iterate all of the folders
                var folders : Array = Find.GetFolders(found);

                setTimeout( ThreadPassFolder );
                ui.tfStatus.text = "Generating Folders...";
                var folder_iteration : int = 0;

                //for( folder_iteration = 0; folder_iteration < folders.length; ++folder_iteration )
                function ThreadPassFolder():void
                {
                    if( folder_iteration < folders.length )
                    {
                        // Do next pass
                        ui.tfStatus.text = "Folder: "+folder_iteration.toString()+"/"+folders.length.toString();
                        setTimeout( ThreadPassFolder );
                    }
                    else
                    {
                        // Break out of 'threaded' loop
                        // Bottom part of file index file; all done
                        ui.tfStatus.text = "Generating Play Lists...";
                        setTimeout( MakePlaylists, 34 );
                        return;
                    }

                    var root : File = folders[folder_iteration];
                    var relPath_root : String = Find.File_relative(root,root_dir);
                    var total_files_at_this_depth : Array = Find.GetChildren( found, root );
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

                    var curr_files_list : Array = [];
                    for( iFile = 0; iFile < total_files_at_this_depth.length; ++iFile )
                    {
                        curr_file = total_files_at_this_depth[iFile];
                        var extCurr : String = Find.File_extension(curr_file);
                        if( extCurr.match(rxMEDIA) )
                        {
                            media_files_db.push(curr_file);
                            curr_files_list.push(curr_file);
                        }
                        else if( extCurr.match(rxPLAY_LISTS) )
                        {
                            all_play_lists.push(curr_file);
                        }
                    }
                    folder_list_db.push( { root:root, index:curr_files_list } );
                    
                    ++folder_iteration;
                }
                
                /* 
                    Ultra-evil brute force play list import function
                    Search the whole file versus every file we know about; if
                    there are matches, make a 'fake' folder out of it.
                */
                var playlist_iteration : int = 0;

                function MakePlaylists():void
                {
                    ui.tfStatus.text = "Play Lists...";
                    setTimeout( ThreadPassPlayList, 34 );
                }
                    
                //for( playlist_iteration = 0; playlist_iteration < all_play_lists.length; ++playlist_iteration )
                function ThreadPassPlayList():void
                {
                    if( playlist_iteration < all_play_lists.length )
                    {
                        // Do next pass
                        ui.tfStatus.text = "Play List: "+playlist_iteration.toString()+"/"+all_play_lists.length.toString();
                        setTimeout( ThreadPassPlayList, 34 );
                    }
                    else
                    {
                        // Break out of 'threaded' loop
                        // Bottom part of file index file; all done
                        ui.tfStatus.text = "Generating index...";
                        setTimeout( ThreadComplete, 34 );
                        return;
                    }
                
                    //for each( curr_file in all_play_lists )
                    var curr_file : File = all_play_lists[playlist_iteration];
                    {
                        var curr_file_text : String = LoadText( curr_file );
                        // Eat up XML/HTML entities
                        curr_file_text = new XML(curr_file_text).toString();
                        // Get rid of URI escapes
                        //curr_file_text = Find.FixDecodeURI(curr_file_text);
                        // All lower-case for case-insensitivity
                        curr_file_text = curr_file_text.toLowerCase(); 
                        
                        // At this point, our image of the play list is utterly ruined, except as something to search as a block of text
                        
                        var files : Array = [];
            
                        // Treat play list file as raw text, and look for literal matches of file names that we have.
                        var media_curr : File;
                        var name_curr : String;
                        
                        for each (media_curr in media_files_db)
                        {
                            name_curr = Find.File_name(media_curr);
                            name_curr = name_curr.toLowerCase();
                            name_curr = '/' + name_curr + '.';
                            if( -1 != curr_file_text.indexOf( name_curr ) )
                                files.push( media_curr );
                        }
                        
                        // We found file names in our collection in that play list, so we will treat it like a real one.
                        if( 0 != files.length )
                        {
                            // Make sure we have only unique files.
                            var uniquefiles : Dictionary = new Dictionary();
                            for each (media_curr in files)
                                uniquefiles[media_curr] = 'true';
                            files = [];
                            for(media_curr in uniquefiles)
                                files.push(media_curr);
                                
                            // Add play list file like a folder
                            var newpath : File = new File( Find.GetPathWithoutExt(curr_file) );
                            folder_list_db.push( { root:newpath, index:files } );
                        }
                    }
                    ++playlist_iteration;
                }
                    

                function ThreadComplete():void
                {
                    if( 0 != media_files_db.length )
                    {
                        // Insert folder list for little link table
                        var folder_list : String = "";
                        var player_list : String = "";
                        
                        function byNativePath( p1:Object, p2:Object ) : int
                        {
                            return Find.SortOnNative( p1.root, p2.root );
                        }
                        folder_list_db = folder_list_db.sort(byNativePath);
                        
                        var folder_iteration : int;
                        for( folder_iteration = 0; folder_iteration < folder_list_db.length; ++folder_iteration )
                        {
                            var curr_folder : Object = folder_list_db[folder_iteration];
                            var root : File = curr_folder.root;
                            var curr_index : Array = curr_folder.index;

                            var seded : String
        
                            // Make folder index and start folder 
                            var relPath : String = Find.File_relative(root,root_dir);
                            var curr_depth : int = Find.File_Depth(root,root_dir) + (0 != folder_iteration);
        
                            // Create and build top half of index file
                            var curr_title : String = Find.File_nameext(root);
                            curr_title = Find.FixDecodeURI(curr_title);
                            curr_title = Find.EscapeQuotes(curr_title);
                           
                            var FOLDER_ID : String = relPath.replace(/[^a-zA-Z0-9]/g, '_' );

                            // Differentiate play list and folder of real files
                            if( root.isDirectory )
                                seded = index_folder;
                            else
                                seded = index_playlist;
                            
                            seded = seded.replace(/FOLDER_ID/g, FOLDER_ID);
                            var indent : String = 'padding-left:'+(LEFT_PADDING+(curr_depth*FOLDER_DEPTH))+'pt;';
                            seded = seded.replace(/FOLDER_NAME/g,curr_title);
                            
                            if( 0 == curr_index.length )
                            {
                                // Add disabled link for folder list
                                const folder_disabled : String = ' pointer-events: none; opacity: 0.75;';
                                seded = seded.replace(/FOLDER_STYLE/g,indent+folder_disabled);
                                folder_list += seded;
                            }
                            else
                            {
                                // Add active link for folder list
                                seded = seded.replace(/FOLDER_STYLE/g,indent);
                                folder_list += seded;
                                
                                // Now build the file index for this folder and add it to the list
                                var index_files : String = "";
                                var media_iteration : int;
                                curr_index = curr_index.sort(Find.SortOnNative);
                                for( media_iteration = 0; media_iteration < curr_index.length; ++media_iteration )
                                {
                                    var curr_file : File = curr_index[media_iteration];
                                    var curr_file_relative : String = Find.File_relative( curr_file, root_dir );
                                    var curr_file_title : String = Find.File_name( curr_file );
                                    curr_file_title = Find.FixDecodeURI(curr_file_title);
                                    curr_file_title = Find.EscapeQuotes(curr_file_title);
                                    
                                    seded = index_file_nothumb;//index_file;
                                    seded = seded.replace(/MEDIA_PATH/g,Find.FixEncodeURI(curr_file_relative));
                                    seded = seded.replace(/MEDIA_TITLE/g,Find.EscapeQuotes(curr_file_title));
                                    seded = seded.replace(/MEDIA_STYLE/g,'');
                                    index_files += seded;
                                }
                                seded = index_begin;
                                seded = seded.replace(/FOLDER_ID/g, FOLDER_ID);
                                // Differentiate play list and folder of real files
                                if( root.isDirectory )
                                    seded = seded.replace(/FOLDER_CLASS/g, 'folder_page');
                                else
                                    seded = seded.replace(/FOLDER_CLASS/g, 'playlist_page');
                                seded = seded.replace(/FOLDER_STYLE/g, '');
                                seded = seded.replace(/FOLDER_NAME/g,curr_title);
                                index_files = seded + index_files + index_end;
                                player_list += index_files;
                            }
                        }
                        
                        var TITLE_TEXT : String = Find.File_name( root_dir );
                        TITLE_TEXT = Find.EscapeQuotes(TITLE_TEXT);
                        var index_content : String = index_template;
                        index_content = index_content.replace("/*INSERT_CSS_HERE*/",css_template);
                        index_content = index_content.replace(/TITLE_TEXT/g,TITLE_TEXT);
                        index_content = index_content.replace("<!--INDEX_FOLDERS_HERE-->", folder_list);
                        index_content = index_content.replace("<!--INDEX_FILES_HERE-->", player_list);
                        
                        //index_content = PackOutput(index_content);
                        
                        // Now write out index file in one pass
                        var toc_file : File = Find.File_AddPath( root_path_media, MAIN_TOC );
                        var fs : FileStream = new FileStream();
                        fs.open( toc_file, FileMode.WRITE );
                        fs.writeUTFBytes(index_content);
                        fs.close();
                    }
                    MediaFilesComplete();
                }
            }
            /*
            catch( e:Error )
            {
                trace(e.getStackTrace());
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathMedia);
                Interactive();
            }
            */

            // Fall out; timer threads are in charge
        }


        /**
         * Reset persistent settings
        **/
        protected function ResetSharedData() : Object
        {
            root_path_media = File.desktopDirectory;
            onFolderChanged();
            CheckSet( ui.bnCompletionTone, true );
            
            CheckSet( ui.bnTempate, false );
            ChangeTemplateEnable();
            root_path_template = File.desktopDirectory;
            onTemplateChanged();
            
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
            root_path_media = new File(share_data.url_media);
            if( !root_path_media.exists )
                root_path_media = File.desktopDirectory;

            CheckSet( ui.bnCompletionTone, share_data.bPlayTune );
            
            onFolderChanged();
            
            CheckSet( ui.bnTempate, share_data.bTemplate );
            root_path_template = new File(share_data.url_template);
            if( !root_path_template.isDirectory )
            {
                root_path_template = File.desktopDirectory;
                CheckSet( ui.bnTempate, false );
            }
            ChangeTemplateEnable();
            onTemplateChanged();
            
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
            share_data.url_media = root_path_media.url;

            share_data.bPlayTune = CheckGet( ui.bnCompletionTone );
            share_data.bTemplate = CheckGet( ui.bnTempate );
            share_data.url_template = root_path_template.url;
            
            share_data.sign = SO_SIGN;

            // Commit file stream
            fs.writeObject(share_data);
            fs.close();
            
            // Return our object for reference
            return share_data;
        }
        
        /** Find path to media content */
        protected function BrowsePathMedia(e:Event=null):void
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
            root_path_media.nativePath = ui.tfPathMedia.text;
        }
        
        // Convenience - hit enter in port to start up
        private function HitEnter(event:KeyboardEvent):void
        {
            if(Keyboard.ENTER == event.charCode)
            {
                onFolderEdited();
                DoMedia();
            }
        }
        

        /** User navigated a different path */
        protected function onFolderChanged(e:Event=null):void
        {
            ui.tfPathMedia.text = root_path_media.nativePath; 
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
         * Keep file 'legible', but remove excess comments and whitespace
         * Like all such hackish regex toys, caveat emptor.
        **/
        private function PackOutput(outputFile:String):String
        {
            /* Regular expressions to eat spaces around operators */ 
            const notInQuotes : String = "";

            // Eat html multiline comments
            outputFile = outputFile.replace(/\<\!\-\-.*?\-\-\>/msg,"");

            // Eat C-style multiline comments (ignore '//' comments)
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
    
