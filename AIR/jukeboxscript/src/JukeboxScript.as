
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
        protected static const SO_SIGN : String = "JUKEBOXSCRIPT_SIGN_02";

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
        public static const PLAYER_TEMPLATE : String = "player_template.html";
        
        /** Table of contents file */
        public static const INDEX_TEMPLATE  : String = "index_template.html";

        /** A css file with theming details */
        public static const CSS_TEMPLATE  : String = "template.css";
        
        /** Where to look for script template content */
        public static const SCRIPT_TEMPLATES: String ="default"
        
        /** Offset for folder depths in TOC file */
        public static const FOLDER_DEPTH : int = 32;

        /** File/folder left padding*/        
        public static const LEFT_PADDING : int = 0;
        
        /** 
         * Regular expressions that we accept as 'Playable content' 
        **/
        public static const rxMP3 : RegExp = /\.(mp3|ogg|m4a)$/i;
        // Straight text formats of play lists
        public static const rxTXT : RegExp = /\.(m3u|m3u8|m4u|bio|txt)$/i;
        // XML formats of play lists
        public static const rxXML : RegExp = /\.(xspf|xml|wpl|smil|plist|kpl)$/i;
        
        
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
            ui.tfPathAudio.addEventListener( KeyboardEvent.KEY_DOWN, HitEnter );
            ui.bFindPathAudio.addEventListener( MouseEvent.CLICK, BrowsePathAudio );
            ui.bnFindExplore.addEventListener( MouseEvent.CLICK, OpenFolder );
            CheckSetup(ui.bnTOC);
            CheckSetup(ui.bnPlaylist);
            CheckSetup(ui.bnCompletionTone);
            
            ui.bnDoIt.addEventListener( MouseEvent.CLICK, DoAudio );
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
                var removeIndexes:NativeMenuItem = toolMenu.addItem(new NativeMenuItem("Remove "+HTML_PLAYER+" files")); 
                removeIndexes.addEventListener(Event.SELECT, RemoveIndexes); 
                
                appToolMenu.submenu = toolMenu;
            }             

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
         * Process audio tree
        **/
        protected function DoAudio(e:Event=null):void
        {
            trace("DoAudio",root_path_media.nativePath);

            /**
             * Do parameter checks before we launch into processes
            **/
            ui.tfPathAudio.text = root_path_media.nativePath;

            if( !root_path_media.exists || !root_path_media.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathAudio);
                return;
            }

            var root : File = Find.File_AddPath( File.applicationDirectory, SCRIPT_TEMPLATES );
            css_template_file   = Find.File_AddPath( root, CSS_TEMPLATE );
            player_template_file= Find.File_AddPath( root, PLAYER_TEMPLATE );
            index_template_file = Find.File_AddPath( root, INDEX_TEMPLATE );

            // If we are using external template files...
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
                if( !player_template_file.exists && !index_template_file.exists && !css_template_file.exists )
                {
                    ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate );
                    trace("Could not find expected files in",css_template_file.nativePath);
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

            CommitSharedData();
           
            function filter_mp3_playlist_folders(file:File):Boolean
            {
                // No hidden files/folders
                if( file.isHidden )
                    return true;
                // Yes, folders
                if( file.isDirectory )
                    return false;
                // Files with .png/.mp4 extensions
                var ext : String = Find.File_extension(file);
                return null == ext.match( rxMP3 ) && null == ext.match( rxTXT ) && null == ext.match( rxXML );
            }
            
            finding = new Find( root_path_media, filter_mp3_playlist_folders );
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

                const rxFile : RegExp = /\<\!\-\-INDEX_FILE(.*?)\-\-\>/ms;
                var index_file : String = player_template.match( rxFile )[0];
                index_file = index_file.replace( rxFile, "$1");

            }
            catch( e:Error )
            {
                trace( "Missing or malformed INDEX_INDEX or INDEX_FILE in", player_template_file.nativePath );
                trace(e.getStackTrace());
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate);
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
            }


            //try
            {
                var play_list_db : Array = new Array();
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
                        if( CheckGet( ui.bnPlaylist ) )
                        {
                            ui.tfStatus.text = "Generating Play Lists...";
                            setTimeout( MakePlaylists, 34 );
                        }
                        else
                        {
                            setTimeout( ThreadComplete );
                        }
                        return;
                    }
                    
                    var iteration : int;
                    var seded : String
                    var folder : File;
                    var root : File = folders[folder_iteration++];
                    var curr_index_file : File = Find.File_AddPath( root, HTML_PLAYER );

                    ui.tfStatus.text = "Folder: "+folder_iteration.toString()+"/"+folders.length.toString();

                    // Don't write index files in folders with no audio content
                    var total_files_folders_at_this_depth : Array = Find.GetChildren( found, root, int.MAX_VALUE );
                    var total_files_at_this_depth : Array = Find.GetFiles(total_files_folders_at_this_depth);
                    function just_music(file:File) : Boolean
                    {
                        var ext : String = Find.File_extension(file);
                        return null == ext.match( rxMP3 );
                    }
                    total_files_at_this_depth = Find.Filter( total_files_at_this_depth, just_music );

                    if( total_files_at_this_depth.length > 0 )
                    {
                        // Get a list of folders in this folder, files in this folder
                        var curr_files : Array = Find.GetChildren( found, root );
                        var curr_folders : Array = Find.GetFolders(curr_files);
                        curr_files = Find.GetFiles(curr_files);
                        curr_files = Find.Filter( curr_files, just_music );

                        // Create and build top half of index file
                        var curr_title : String = Find.File_nameext(root);
                        curr_title = Find.FixDecodeURI(curr_title);

                        // Build jukebox file
                        
                        var index_files : String = "";
                        var dbnew : Object;
    
                        // Iterate child folders and generate links to them
                        for( iteration = 0; iteration < curr_folders.length; ++iteration )
                        {
                            var curr_folder : File  = curr_folders[iteration];
    
                            // Filter folders with no movies in any children from lists
                            total_files_folders_at_this_depth = Find.GetChildren( found, curr_folder, int.MAX_VALUE );
                            total_files_at_this_depth = Find.GetFiles(total_files_folders_at_this_depth);
                            total_files_at_this_depth = Find.Filter( total_files_at_this_depth, just_music );
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
                                    // Make index entry if folder has contents
                                    if( 0 != curr_files.length )
                                    {
                                        seded = index_toc_folder;
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
                                    seded = seded.replace(/FOLDER_STYLE/g,'');
                                    index_files += seded;

                                    // Generate indexes for TOC
                                    seded = index_small;
                                    seded = seded.replace(/FOLDER_PATH/g,curr_index_absolute);
                                    seded = seded.replace(/FOLDER_TITLE/g,curr_index_title);
                                    seded = seded.replace(/FOLDER_STYLE/g,'padding-left:'+(LEFT_PADDING+(curr_depth*FOLDER_DEPTH))+'px;');
                                    dbnew = {name:curr_index_title,item:seded,path:curr_folder,depth:curr_depth};
                                    folder_list_db.push( dbnew );
                                }
                            }
                        }
                        
                        if( 0 != curr_files.length )
                        {
                            index_files += "<br/>\n";
                        }
                        
                        // Iterate files and generate code 
                        for( iteration = 0; iteration < curr_files.length; ++iteration )
                        {
                            var curr_file : File = curr_files[iteration];
                            var curr_file_relative : String = Find.File_relative( curr_file, root );
                            var curr_file_title : String = Find.File_name( curr_file );
                            curr_file_title = Find.FixDecodeURI(curr_file_title);
                            
                            // Emit index+code to play file
                            seded = index_file;
                            seded = seded.replace(/MEDIA_PATH/g,curr_file_relative);
                            seded = seded.replace(/MUSIC_TITLE/g,curr_file_title);
                            seded = seded.replace(/FILE_STYLE/g,'');
                            index_files += seded;
    
                            // Emit absolute index to play from TOC
                            curr_file_relative = Find.File_relative( curr_index_file, folders[0] );
                            var curr_name   : String = Find.FixDecodeURI(Find.File_nameext(curr_file));
                            var curr_path   : String = curr_file_relative + '?' + curr_name;
                            seded = index_toc_file;
                            seded = seded.replace(/MEDIA_PATH/g,curr_path);
                            seded = seded.replace(/MEDIA_TITLE/g,curr_file_title);
                            seded = seded.replace(/FILE_STYLE/g,'');
                            file_list_index += seded;

                            bExportedLinks = true;
                        }
    
                        if( bExportedLinks )
                        {
                            bExportedLinks = false;
                            var index_content : String = player_template;
                            index_content = index_content.replace(/TITLE_TEXT/g,curr_title);
                            index_content = index_content.replace("/*INSERT_CSS_HERE*/",css_template);
                            index_content = index_content.replace("<!--INDEXES_HERE-->",index_files);
                            index_content = PackOutput(index_content);
    
                            // Now write out index file in one pass
                            var fs : FileStream = new FileStream();
                            fs.open( curr_index_file, FileMode.WRITE );
                            fs.writeUTFBytes(index_content);
                            fs.close();
                        }
                    }
                    
                }

                // Database of filenames->File
                var database : Dictionary;
                // Iteration 'thread' details
                var playlist_iteration : int = 0;
                var aPlaylists : Array;
                // List of generated play list titles
                var aPlayListsAvailable : Array = new Array();
                /**
                 * Scan for playlists and poop 'em out as folders
                 * Should probably appear in main index table of contents, at top.
                 * We need to do this *before* the index/TOC is generated, because
                 * I want them in the index.html TOC box
                **/
                function BorkedFile(sz:String) : String
                {
                    sz = Find.FixDecodeURI(sz);
                    sz = escape(sz);
                    return sz;
                }
                
                function MakePlaylists():void
                {
                    database = new Dictionary();
                    
                    function filter_playable(file:File):Boolean
                    {
                        // Play list files with recognizeable file extensions
                        var ext : String = Find.File_extension(file);
                        return null == ext.match( rxMP3 );
                    }
                    aPlaylists = Find.GetFiles(finding.results);
                    aPlaylists = Find.Filter( aPlaylists, filter_playable );

                    // Make a quicker index for potential play list members
                    var i : int;
                    var curr : File;
                    var currname : String;
                    for( i = 1; i < aPlaylists.length; ++i )
                    {
                        curr = aPlaylists[i];
                        currname = Find.File_name(curr);
                        Find.FixDecodeURI(currname);
                        currname = currname.toLowerCase();
                        currname = BorkedFile(currname);
                        if( null != database[currname] )
                        {
                            // Tell us about bothersome conflicts in trace output
                            trace( "Playlist DB:", database[currname].nativePath, "conflicts with", curr.nativePath );
                        }
                        else
                        {
                            database[currname] = curr;
                            trace("Added '"+currname+"' to database from",curr.nativePath);
                        }
                    }

                    // Get play list files, to iterate and parse
                    aPlaylists = Find.GetFiles(finding.results);
                    function filter_playlists(file:File):Boolean
                    {
                        // Play list files with recognizeable file extensions
                        var ext : String = Find.File_extension(file);
                        return null == ext.match( rxTXT ) && null == ext.match( rxXML );
                    }
                    
                    // Build a list of potential play lists
                    playlist_iteration = 1;
                    aPlaylists = Find.Filter( aPlaylists, filter_playlists );

                    if( aPlaylists.length > 1 )
                    {
                        setTimeout( ThreadPassPlaylist );
                    }
                    else
                    {
                        setTimeout( ThreadComplete );
                    }
                }

                function ThreadPassPlaylist():void
                {
                    if( playlist_iteration < aPlaylists.length )
                    {
                        // Do next pass
                        setTimeout( ThreadPassPlaylist );
                        ui.tfStatus.text = "Generating Play Lists " + (playlist_iteration) + " / " + (aPlaylists.length-1);
                        trace( ui.tfStatus.text );
                    }
                    else
                    {
                        // Break out of 'threaded' loop
                        // Bottom part of file index file; all done
                        ui.tfStatus.text = "Writing index...";
                        setTimeout( ThreadComplete );
                        return;
                    }
                    var playListCurr : File = aPlaylists[playlist_iteration++];
                    var contents : String = LoadText(playListCurr);
                    var ext : String = Find.File_extension( playListCurr );
                    var found_paths : Array = new Array();

                    function IsItAPath(line:String) : Boolean
                    {
                        // Line ends with a recognized file extension?
                        // eat messy leading/trailing white space, including DOS '\r'
                        var lastSlash : int;
                        var lastDot : int;
                        line=line.replace(/^\s+|\s+$/g,'');
                        if( null != line.match( rxMP3 ) )
                        {
                            lastSlash = line.lastIndexOf('/');
                            if( -1 == lastSlash )
                                lastSlash = line.lastIndexOf('\\');
                            lastDot = line.lastIndexOf('.');
                            if( lastDot > lastSlash )
                            {
                                var path : String = line.substr(lastSlash+1,-1+lastDot-lastSlash);
                                path = Find.FixDecodeURI(path);
                                path = path.toLowerCase();
                                path = BorkedFile(path);
                                foundFile = database[path];
                                if( null != foundFile )
                                {
                                    trace("Found: ", path);
                                    found_paths.push(foundFile);
                                    return true;
                                }
                                else
                                {
                                    trace("Not found: '"+path+"'");
                                }
                            }
                        }
                        return false;
                    }

                    if( ext.match( rxTXT ) )
                    {   //
                        // Go through this line-by-line, looking for lines that 
                        // end with a playable file extension, and if it looks
                        // like a 'path', see if it's in our database, and if so,
                        // emit it.
                        //
                        var lines : Array = contents.split( '\n' );
                        if( 1 == lines.length ) // DOS-ish
                            lines = contents.split( '\r' );
                        var line : String;
                        var i : int;
                        for( i = 0; i < lines.length; ++i )
                        {
                            line = lines[i];
                            if( '#' != line.substr(0,1) )
                            {
                                IsItAPath(line);
                            }
                        }
                    }
                    else
                    {   //
                        // Recursively tear the XML apart, looking for text that 
                        // looks like a playable file name, and compare against
                        // our database of file names.  Emit if we match.
                        //
                        // Pure evil, but I don't want to get bogged down in 
                        // petty details over who thinks what the XML should look
                        // like, be named, whether to put it in an attribute, 
                        // etc., and all of the possible permutations of that.
                        //
                        var xml : XML = new XML(contents);
                        // Iteratr through everything that looks like a path.
                        // If we find a match, add it to output
                        function CurseAndRecurse(xml:XML) : Boolean
                        {
                            var i : int;
                            var list : XMLList;

                            // This looks like a path to a song?
                            if( IsItAPath(xml.toString()) )
                                return true;

                            // An attribute looks like a path to a song?
                            list = xml.attributes();
                            for( i = 0; i < list.length(); ++i )
                            {
                                IsItAPath(list[i].toString());
                            }
                                
                            // Recurse and try further in
                            list = xml.children();
                            for( i = 0; i < list.length(); ++i )
                            {
                                CurseAndRecurse(list[i]);
                            }
                            return false;
                        }
                        CurseAndRecurse(xml);
                    }

                    // If we have a play list with content, generate the player file for it and add it to play_list_db database
                    if( "" != index_files )
                    {
                        var index_files : String = "";
                        const collator : Collator = new Collator(LocaleID.DEFAULT);
                        function byname(f1:File,f2:File) : int
                        {
                            return collator.compare( Find.File_nameext(f1), Find.File_nameext(f2) );
                        }
                        found_paths.sort(byname);
                        // Remove duplicates
                        for( i = found_paths.length-1; i >= 1; --i )
                        {
                            if( found_paths[i] == found_paths[i-1] )
                            {
                                found_paths.splice(i,1);
                            }
                        }

                        for( i = 0; i < found_paths.length; ++i )
                        {
                            var foundFile : File = found_paths[i];
                            var curr_index_title : String = Find.File_name( foundFile );
                            curr_index_title = Find.FixDecodeURI(curr_index_title);
                            var curr_index_absolute : String = Find.File_relative( foundFile, root_path_media );

                            var seded : String = index_file;
                            seded = seded.replace(/MEDIA_PATH/g,curr_index_absolute);
                            seded = seded.replace(/MUSIC_TITLE/g,curr_index_title);
                            seded = seded.replace(/FILE_STYLE/g,'');
                            index_files += seded;
                        }


                        var outputFileName : String = Find.File_name( playListCurr );
                        var outputFile : File = Find.File_AddPath( root_path_media, outputFileName );
                        outputFile = Find.File_newExtension( outputFile, ".html" );
                        var curr_title : String = Find.File_name( playListCurr );
                        curr_title = Find.FixDecodeURI(curr_title);
    
                        var index_content : String = player_template;
                        index_content = index_content.replace(/TITLE_TEXT/g,curr_title);
                        index_content = index_content.replace("/*INSERT_CSS_HERE*/",css_template);
                        index_content = index_content.replace("<!--INDEXES_HERE-->",index_files);
                        index_content = PackOutput(index_content);
                        
                        // Now write out index file in one pass
                        var fs : FileStream = new FileStream();
                        fs.open( outputFile, FileMode.WRITE );
                        fs.writeUTFBytes(index_content);
                        fs.close();

                        // Generate indexes for TOC, for our new player file
                        seded = index_small;
                        seded = seded.replace(/FOLDER_PATH/g, Find.File_relative( outputFile, root_path_media ) );
                        seded = seded.replace(/FOLDER_TITLE/g, curr_title);
                        seded = seded.replace(/FOLDER_STYLE/g,'');
                        var dbnew : Object = {name:curr_title,item:seded,path:outputFile,depth:0};
                        play_list_db.push( dbnew );
                    }
                }                
                
                function ThreadComplete():void
                {
                    // If user wanted a flattened table of contents, make one.
                    if( CheckGet( ui.bnTOC ) && folder_list_db.length > 1 )
                    {
                        // Insert folder list for little link table
                        var folder_list : String = "";
                        var dbCurr : Object = folder_list_db[iteration];
                        var iteration : int;
                        folder_list_db.sort(byNativePath);
                        function byNativePath( p1:Object, p2:Object ) : int
                        {
                            return Find.SortOnNative( p1.path, p2.path );
                        }
                        if( 0 != play_list_db.length )
                        {
                            play_list_db.sortOn(name);
                            folder_list += "Play Lists:";
                            for( iteration = 0; iteration < play_list_db.length; ++iteration )
                            {
                                dbCurr = play_list_db[iteration];
                                folder_list += dbCurr.item;
                            }
                            folder_list += "<br/><br/>Folders:";
                        }
                        for( iteration = 0; iteration < folder_list_db.length; ++iteration )
                        {
                            dbCurr = folder_list_db[iteration];
                            folder_list += dbCurr.item;
                        }

                        var index_content : String = index_template;
                        index_content = index_content.replace("/*INSERT_CSS_HERE*/",css_template);
                        index_content = index_content.replace("<!--INDEXES_HERE-->",file_list_index);
                        index_content = index_content.replace("<!--FOLDERS_HERE-->",folder_list);
                        
                        index_content = PackOutput(index_content);
                        
                        // Now write out index file in one pass
                        var toc_file : File = Find.File_AddPath( root_path_media, MAIN_TOC );
                        var fs : FileStream = new FileStream();
                        fs.open( toc_file, FileMode.WRITE );
                        fs.writeUTFBytes(index_content);
                        fs.close();
                    }
                    AudioFilesComplete();
                }
            }
            /*
            catch( e:Error )
            {
                trace(e.getStackTrace());
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathAudio);
                Interactive();
            }
            */

            // Fall out; timer threads are in charge
        }


        /**
         * Parse common text and XML based formats
         *
         * Play lists will be exported with their own index and with their own
         * Playlistname.html files, matching the play list file names.
         *
         * This is a 'forgiving' playlist generator.  We strip the paths off and
         * match just the file name, case insensitive, so something like...
         *
         * /volumes/music/artist/album/My Favorite Song About Food.mp3
         *
         * ...and...
         *
         * /spork/arbitrary/path/to/thing/spewspew/My Favorite Song About Food.mp3
         &
         * ...would match, as would...
         &
         * My Favorite song about Food
         *
         * ...without any file extension.
         *
         * I do this so play lists can be exchanged/used without keeping the 
         * tree of mp3 files across computers and different people's libraries.
         * As long as you both have the required songs, *named the same things*
         * a playlist will be generated.  If there's no match for an entry, 
         * then, no harm, no foul, we simply don't include it.
         *
         * There are a whole bunch of play list file formats to mess around with,
         * but they break down into two categoties for this app.  Plain text and
         * XML text.  We only look for common patterns/attributes/entries from
         * identifiable formats with the PATH in them.   This is sort of 'dirty',
         * but handling dozens of different input formats is dirty.
         *
         * I will label my 'native' format as plain text, since it is trivial
         * to work with.  In a txt file, lines beginning with '#' will be ignored
         * exactly the behavior I use for m3u and its derivations.
         *
         * For a 'playlist.txt' filename, you could make a playlist like this...
         * find /mymusic/rock -name *.mp3 > playlist.txt
         *
         * In Windows...
         * dir /s /b D:\mymusic\rock\*.mp3 > playlist.txt
         *
         * Either way, once you have the recursive list of files list, you can 
         * pare down what you wanted in a text editor.  If you change your mind 
         * about what files go into what folders later, it will still work just 
         * like you never changed anything.
        **/


        
        /**
         * Reset persistent settings
        **/
        protected function ResetSharedData() : Object
        {
            root_path_media = File.desktopDirectory;
            onFolderChanged();
            CheckSet( ui.bnTOC, true );
            CheckSet( ui.bnCompletionTone, true );
            CheckSet( ui.bnPlaylist, true );
            
            CheckSet( ui.bnTempate, false );
            ChangeTemplateEnable();
            root_path_template = Find.File_AddPath( File.applicationDirectory, SCRIPT_TEMPLATES );
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
            root_path_media = new File(share_data.url_audio);
            if( !root_path_media.exists )
                root_path_media = File.desktopDirectory;

            CheckSet( ui.bnTOC, share_data.bDoTOC );
            CheckSet( ui.bnCompletionTone, share_data.bPlayTune );
            CheckSet( ui.bnPlaylist, share_data.bPlaylist );
            
            onFolderChanged();
            
            CheckSet( ui.bnTempate, share_data.bTemplate );
            root_path_template = new File(share_data.url_template);
            if( !root_path_template.isDirectory )
            {
                root_path_template = Find.File_AddPath( File.applicationDirectory, SCRIPT_TEMPLATES );
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
            share_data.url_audio = root_path_media.url;

            share_data.bDoTOC = CheckGet( ui.bnTOC );
            share_data.bPlayTune = CheckGet( ui.bnCompletionTone );
            share_data.bPlaylist = CheckGet( ui.bnPlaylist );

            share_data.bTemplate = CheckGet( ui.bnTempate );
            share_data.url_template = root_path_template.url;
            
            share_data.sign = SO_SIGN;

            // Commit file stream
            fs.writeObject(share_data);
            fs.close();
            
            // Return our object for reference
            return share_data;
        }
        
        /** Find path to audio content */
        protected function BrowsePathAudio(e:Event=null):void
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
            root_path_media.nativePath = ui.tfPathAudio.text;
        }
        
        // Convenience - hit enter in port to start up
        private function HitEnter(event:KeyboardEvent):void
        {
            if(Keyboard.ENTER == event.charCode)
            {
                onFolderEdited();
                DoAudio();
            }
        }
        

        /** User navigated a different path */
        protected function onFolderChanged(e:Event=null):void
        {
            ui.tfPathAudio.text = root_path_media.nativePath; 
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
         * Invoke index file nuker
        **/
        private function RemoveIndexes(event:Event):void 
        { 
            if( !root_path_media.exists || !root_path_media.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathAudio);
                return;
            }

            var warning : String = "Every "+HTML_PLAYER+" from the Audio Player path will be wiped out!\n\n" + root_path_media.nativePath;
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
                        found[i].moveToTrashAsync();
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
    
