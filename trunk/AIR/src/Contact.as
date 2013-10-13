
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
    import flash.utils.*;
    import flash.geom.*;
    import flash.events.*;
    import flash.display.*;
    import flash.text.*;
    import flash.media.*;
    import flash.filters.*;

    import flash.filesystem.*;
    
    public class Contact extends MovieClip
    {
        internal static const SO_PATH : String = "ContactData";
        internal static const SO_SIGN : String = "CONTACT_SIGN_01";

        /** What to call the 'top level' index file */
        public var MAIN_INDEX      : String = "index.html";

        /** Multiple index mode: What to call the folder indexes */
        public var FOLDER_INDEX    : String = "index_toc.html";

        /** Where to look for script template content */
        public var SCRIPT_TEMPLATES: String ="templates/"

        /** Top few lines of html files */
        public var INDEX_TOPMOST   : String = SCRIPT_TEMPLATES+"index_topmost.html";

        /** CSS as its own stand-alone css file (concatenated in for easy house-keeping) */
        public var INDEX_CSS       : String = SCRIPT_TEMPLATES+"webified.css";
        
        /** Start of movie player and available content */
        public var MOVIE_PROLOG    : String = SCRIPT_TEMPLATES+"index_prolog.html";
        
        /** End of movie player html file */
        public var INDEX_EPILOG    : String = SCRIPT_TEMPLATES+"index_epilog.html";
        
        /** A movie file link with player logic */
        public var INDEX_FILE      : String = SCRIPT_TEMPLATES+"index_file.html";

        /** Accordion movie folder link */
        public var INDEX_FOLDER    : String = SCRIPT_TEMPLATES+"index_folder.html";

        /** Link to folder index */
        public var INDEX_INDEX     : String = SCRIPT_TEMPLATES+"index_index.html";
        
        /** Width of thumbnails */
        public var THUMB_SIZE      : int = 128;

        /** Regular expressions that we accept as 'MP4 content' 
            Lots of synonyms for 'mp4'.  Many of these may have incompatible CODECs 
            or DRM, or other proprietary extensions in them.   
        **/
        public var REGEX_MP4        : String = ".(mp4|m4v|m4p|m4r|3gp|3g2)";

        /** Regular expressions that we accept as 'MP4 content'*/
        public var REGEX_THUMB      : String = ".(png|jpg|jpeg)";
        
        internal var root_path_video : File;
        internal var root_path_audio : File;
        internal var root_path_image : File;
        
        internal var finding : Find;
        
        internal var thumbnail_template : MovieClip;
        internal var thumbnail : Thumbnail;
        
        public function Contact()
        {
            ui.tfPathVideo.addEventListener( Event.CHANGE, onFolderEdited );
            ui.tfThumbnailSize.addEventListener( Event.CHANGE, onFolderEdited );
            ui.bFindPathVideo.addEventListener( MouseEvent.CLICK, BrowsePathVideo );
            CheckSetup(ui.bDoVideo);
            CheckSetup(ui.bnVideoAllInOne);

            ui.tfPathAudio.addEventListener( Event.CHANGE, onFolderEdited ); 
            ui.bFindPathAudio.addEventListener( MouseEvent.CLICK, BrowsePathAudio );
            CheckSetup(ui.bDoAudio);

            // Not implemented...
            DisableIt(ui.tfPathAudio);
            DisableIt(ui.bFindPathAudio);
            DisableIt(ui.bDoAudio);
            DisableIt(ui.tfPathTitleAudio);

            ui.tfPathImage.addEventListener( Event.CHANGE, onFolderEdited );
            ui.bFindPathImage.addEventListener( MouseEvent.CLICK, BrowsePathImage );
            CheckSetup(ui.bDoImage);
            
            // Not implemented...
            DisableIt(ui.tfPathImage);
            DisableIt(ui.bFindPathImage);
            DisableIt(ui.bDoImage);
            DisableIt(ui.tfPathTitleImage);

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

            Interactive();
            
        }
        
        /**
         * Do the stuff.
        **/
        internal function DoIt(e:Event=null):void
        {
            trace("Doit",root_path_video.nativePath);

            /**
             * Do error checks before we launch into process
            **/
            ui.tfPathVideo.text = root_path_video.nativePath;
            if( CheckGet( ui.bDoVideo ) && (!root_path_video.exists || !root_path_video.isDirectory) )
            {
                ErrorIndicate(ui.bDoVideo);
                CheckSet( ui.bDoVideo, false );
                return;
            }
            ui.tfPathAudio.text = root_path_audio.nativePath;
            if( CheckGet( ui.bDoAudio ) && (!root_path_audio.exists || !root_path_audio.isDirectory) )
            {
                CheckSet( ui.bDoAudio, false );
                ErrorIndicate(ui.bDoAudio);
                return;
            }
            ui.tfPathImage.text = root_path_image.nativePath;
            if( CheckGet( ui.bDoImage ) && (!root_path_image.exists || !root_path_image.isDirectory) )
            {
                CheckSet( ui.bDoImage, false );
                ErrorIndicate(ui.bDoImage);
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
            ui.gotoAndStop("working");
            ui.tfStatus.text = "...";
            ui.tabChildren = false;
        }
        private function Interactive() : void
        {
            ui.gotoAndStop("interactive");
            ui.tfStatus.text = "";
            ui.tabChildren = true;
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
            if( !CheckGet( ui.bDoVideo ) )
            {
                DoAudio(e);
                return;
            }
            
            if( !root_path_video.exists || !root_path_video.isDirectory )
            {
                ErrorIndicate(ui.bDoVideo);
                CheckSet( ui.bDoVideo, false );
                return;
            }

            // MP4, PNG, folders
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
                return !ext.match(new RegExp(REGEX_MP4,"i")) && !ext.match(new RegExp(REGEX_THUMB,"i"));
            }
            
            finding = new Find( root_path_video, filter_mp4_png_folders );
            ui.tfStatus.text = "...";
            finding.addEventListener( Find.ABORT, Aborted );
            finding.addEventListener( Find.MORE, FindStatus );
            finding.addEventListener( Find.FOUND, HaveVideoFiles );

            thumbnail_template = new ThumbnailTemplate();
            thumbnail = new Thumbnail(thumbnail_template.mcPlaceholder,THUMB_SIZE);
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
                    var ret = fs.readUTFBytes(fs.bytesAvailable);
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
            if( 0 != thumbnail.queue_length )
            {
                // Wait for thumbnailing to complete
                thumbnail.Startup();
                thumbnail.addEventListener( Event.COMPLETE, VideoFilesComplete );
                thumbnail.addEventListener( Thumbnail.SNAPSHOT_READY, ThumbnailNext );
            }
            else
            {
                // Jump to audio task
                VideoFilesComplete();
            }
        }
        
        /** Update progress animation with thumbnail status */
        protected function ThumbnailNext(e:Event=null):void
        {
            ui.tfStatus.text = thumbnail.queue_length.toString() + " " + Find.File_nameext(thumbnail.thumb_file);

            // Size elements
            addChild(thumbnail_template);
            thumbnail_template.mcSprocketHoles.width = thumbnail_template.mcSprocketHoles.height = THUMB_SIZE;

            // Render to bitmap
            var bmd : BitmapData = new BitmapData(THUMB_SIZE, thumbnail.video_object.height, false, 0);
            bmd.draw(thumbnail_template);
            removeChild(thumbnail_template);
            
            // Encode jpeg
            var jpeg : JPGEncoder = new JPGEncoder(80);
            var bytes : ByteArray = jpeg.encode(bmd);
            
            // Write jpeg
            var fs:FileStream = new FileStream();
            fs.open( thumbnail.thumb_file, FileMode.WRITE );
            fs.writeBytes(bytes,0,bytes.length );
            fs.close();
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
            /* Unit test for some of the path manipulations/formatting
            trace( "\n\nFound",found.length,"video files.");
            var i : int;
            var root : File = found[0];
            for( i = 0; i < found.length; ++i )
            {
                var file : File = found[i];
                trace( Find.File_Depth(file,root), Find.File_relative(file,root) );
                trace( "    File_extension",Find.File_extension( file ) );
                trace( "    File_name",     Find.File_name( file ) );
                trace( "    File_nameext",  Find.File_nameext( file ) );
                trace( "    File_parent",   Find.File_parent( file ) );
                trace( "    File_relative", Find.File_relative( file, root ) );
            }
            trace( "\n\n" );
            */

            try
            {
                var i : int;
                var j : int;
                var file : File;
                var folder : File;
                var root : File = found[0];
                var root_string : String = Find.File_name(root);
                var main_index_file : File = Find.File_AddPath( root, MAIN_INDEX );
                var fs:FileStream = new FileStream();
                
                // Make a dictionary of the files and paths, to make a quicker 'exists' check
                var existsLUT : Dictionary = new Dictionary();
                for( i = 1; i < found.length; ++i )
                {
                    file = found[i];
                    existsLUT[file.nativePath] = file;
                }                
                
                var folders : Array = Find.GetFolders(found);
                
                fs.open( main_index_file, FileMode.WRITE );
                
                // Top part of file
                fs.writeUTFBytes(LoadText(INDEX_TOPMOST));
                var seded : String
                seded = LoadText(INDEX_CSS);
                seded = seded.replace(/THUMB_SIZE/g,THUMB_SIZE.toString());
                fs.writeUTFBytes(seded);
                
                seded = LoadText(MOVIE_PROLOG);
                seded = seded.replace(/TITLE_TEXT/g,root_string);
                fs.writeUTFBytes(seded);

                var index_file : String = LoadText(INDEX_FILE); 
                var index_folder : String = LoadText(INDEX_FOLDER); 
                var need_sdiv : Boolean = false;
                
                // Iterate files + folders
                var rxMP4 : RegExp = new RegExp(REGEX_MP4,"i");
                for( i = 0; i < folders.length; ++i )
                {
                    folder = folders[i];
                    
                    var files : Array = Find.GetChildren( found, folder );
                    var mp4files : Array = Find.Filter( files, justmp4 );
                    function justmp4(file:File):Boolean
                    {
                        return !Find.File_extension( file ).match(rxMP4);
                    }
                    
                    // Skip over folders that don't have mp4 files.
                    //trace(mp4files.length, folder.nativePath);
                    if( 1 < mp4files.length ) 
                    {
                        var relative_path : String;
                        var folderparent : String;
                        var foldername : String;
                        var folderstyle : String;
                        if( 0 == i )
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
                        fs.writeUTFBytes(seded);
                        
                        for( j = 1; j < mp4files.length; ++j )
                        {
                            file = mp4files[j];
    
                            var file_relative_path : String = Find.File_relative( file, root );
                            var filename : String = file_relative_path.slice(1+file_relative_path.lastIndexOf('/'));
                            var lastdot : int = filename.lastIndexOf('.');
                            var ext : String = lastdot<0?'':filename.slice(lastdot);
                            if( ext.match(rxMP4) )
                            {   // Video file
                                var filename_noext : String = -1 == lastdot ? filename : filename.slice(0,lastdot);
                                var file_thumb : File;
                                var filename_thumb : String;
                                file_thumb = Find.File_newExtension( file, '.png' );
                                if( file_thumb.nativePath in existsLUT )
                                {   // Have a jpeg thumbnail
                                    filename_thumb = Find.File_relative( file_thumb, root );
                                }
                                else
                                {   // Have a jpeg thumbnail
                                    file_thumb = Find.File_newExtension( file, '.jpeg' );
                                    if( file_thumb.nativePath in existsLUT )
                                    {   // Have a JPEG thumbnail
                                        filename_thumb = Find.File_relative( file_thumb, root );
                                    }
                                    else
                                    {
                                        file_thumb = Find.File_newExtension( file, '.jpg' );
                                        if( !file_thumb.nativePath in existsLUT )
                                        {   // Have NO thumbnail (make a jpeg)
                                            trace("Needs:",file_thumb.url);
                                            thumbnail.AddTask( file, file_thumb )
                                        }
                                        filename_thumb = Find.File_relative( file_thumb, root );
                                    }
                                }
                                seded = index_file.replace(/VIDEO_IMAGE/g,filename_thumb);
                                seded = seded.replace(/VIDEO_PATH/g,file_relative_path);
                                seded = seded.replace(/MOVIE_TITLE/g,filename_noext);
                                fs.writeUTFBytes(seded);
                            }
                            else
                            {
                                // Thumbnail files are mixed in with the mp4, so we don't
                                // do extra directory tree searches through the file system
                                // to check for thumbnails' existence
                            }
                        }
                        fs.writeUTFBytes("</div>\n");
                    }
                }
    
                // Bottom part of file
                fs.writeUTFBytes(LoadText(INDEX_EPILOG));
                fs.close();
            }
            catch( e:Error )
            {
                trace(e);
                ErrorIndicate(ui.bDoVideo);
            }
        }

        
        /**
         * Recursively generates files for each folder, and generates a master
         * index for all.
         *
         * This will definitely load individual pages a lot faster, but you'll
         * add some more clutter to your directory tree for all of the toc.html
         * files.  
         *
         * Simpler UI without folding folders.  Just one index.html at the root
         * like the other one, but containing only folder to folders containing 
         * a player and file list.
        **/
        protected function DoVideoFilesTree(found:Array):void
        {
            var i : int;
            trace( "Found",found.length,"video files.");
            for( i = 0; i < found.length; ++i )
            {
                trace(found[i].nativePath);
            }
        }

        /**
         * Clean up after video UI and thumbnail generation
        **/
        protected function VideoFilesComplete(e:Event=null):void
        {
            if( null != thumbnail )
            {
                thumbnail.Cleanup();
                thumbnail = null;
            }
            DoAudio();
        }
        
        /**
         * Process audio tree
        **/
        protected function DoAudio(e:Event=null):void
        {

            if( !CheckGet( ui.bDoAudio ) )
            {
                DoImage();
                return;
            }
            
            finding = new Find( root_path_audio );
            ui.tfStatus.text = "...";
            finding.addEventListener( Find.FOUND, DoAudioFiles );
            finding.addEventListener( Find.ABORT, Aborted );
            finding.addEventListener( Find.MORE, FindStatus );
            Busy();
        }
        protected function DoAudioFiles(e:Event=null):void
        {
            var i : int;
            var list : Array = finding.results;
            trace( "Found",list.length,"audio files.");
            for( i = 0; i < list.length; ++i )
            {
                trace(list[i].nativePath);
            }

            DoImage();
        }

        /**
         * Process image tree
        **/
        protected function DoImage(e:Event=null):void
        {
            if( !CheckGet( ui.bDoImage ) )
            {
                Interactive();
                return;
            }
            
            finding = new Find( root_path_image );
            ui.tfStatus.text = "...";
            finding.addEventListener( Find.FOUND, DoImageFiles );
            finding.addEventListener( Find.ABORT, Aborted );
            finding.addEventListener( Find.MORE, FindStatus );
            Busy();
        }
        protected function DoImageFiles(e:Event=null):void
        {
            var i : int;
            var list : Array = finding.results;
            trace( "Found",list.length,"image files.");
            for( i = 0; i < list.length; ++i )
            {
                trace(list[i].nativePath);
            }

            Interactive();
        }


        /**
         * Reset persistent settings
        **/
        protected function ResetSharedData():void
        {
            CheckSet( ui.bDoVideo, true );
            CheckSet( ui.bnVideoAllInOne, false );
            root_path_video = File.userDirectory;
            CheckSet( ui.bDoAudio, true );
            root_path_audio = File.userDirectory;
            CheckSet( ui.bDoImage, true );
            root_path_image = File.userDirectory;
            onFolderChanged();
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
                ResetSharedData();
                return;
            }
            
            // Decode the saved data
            CheckSet( ui.bDoVideo, share_data.bDoVideo );
            CheckSet( ui.bnVideoAllInOne, share_data.bDoVideoAllInOne );
            root_path_video = new File(share_data.url_video);
            THUMB_SIZE = share_data.thumb_size;
            ui.tfThumbnailSize.text = THUMB_SIZE.toString();
            
            CheckSet( ui.bDoAudio, share_data.bDoAudio );
            root_path_audio = new File(share_data.url_audio);
            
            CheckSet( ui.bDoImage, share_data.bDoImage );
            root_path_image = new File(share_data.url_image);
            onFolderChanged();

        }
        
        /**
         * Save persistent settings
        **/
        public function CommitSharedData():void
        {
            var share_data : Object = {}; 

            // Get file 
            var f:File = File.applicationStorageDirectory.resolvePath(SO_PATH);
            var fs:FileStream = new FileStream();
            fs.open(f, FileMode.WRITE);

            // Copy data to our save 'object'
            share_data.url_video = root_path_video.url;
            share_data.url_audio = root_path_audio.url;
            share_data.url_image = root_path_image.url;
            share_data.bDoVideo = CheckGet( ui.bDoVideo );
            share_data.bDoVideoAllInOne = CheckGet( ui.bnVideoAllInOne );
            share_data.thumb_size = THUMB_SIZE;
            
            share_data.bDoAudio = CheckGet( ui.bDoAudio );
            share_data.bDoImage = CheckGet( ui.bDoImage );
            share_data.sign = SO_SIGN;

            // Commit file stream
            fs.writeObject(share_data);
            fs.close();
        }
        
        /** Find path to video content */
        internal function BrowsePathVideo(e:Event=null):void
        {
            root_path_video = new File;
            root_path_video.addEventListener(Event.SELECT, onFolderChanged);
            root_path_video.browseForDirectory("Choose a folder");
        }

        /** Find path to audio content */
        internal function BrowsePathAudio(e:Event=null):void
        {
            root_path_audio = new File;
            root_path_audio.addEventListener(Event.SELECT, onFolderChanged);
            root_path_audio.browseForDirectory("Choose a folder");
        }

        /** Find path to image content */
        internal function BrowsePathImage(e:Event=null):void
        {
            root_path_image = new File;
            root_path_image.addEventListener(Event.SELECT, onFolderChanged);
            root_path_image.browseForDirectory("Choose a folder");
        }

        /** Keep track if user hand-tweaked paths, so we can make them into File objects */
        internal function onFolderEdited(e:Event=null):void
        {
            root_path_video = new File(ui.tfPathVideo.text);
            THUMB_SIZE = int(ui.tfThumbnailSize.text);
            root_path_image = new File(ui.tfPathImage.text);
            root_path_audio = new File(ui.tfPathAudio.text);
        }

        /** User navigated a different path */
        internal function onFolderChanged(e:Event=null):void
        {
            ui.tfPathVideo.text = root_path_video.nativePath; 
            ui.tfPathAudio.text = root_path_audio.nativePath; 
            ui.tfPathImage.text = root_path_image.nativePath; 
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
         * By default, exclude hidden files.  
         * Provide your own filter to override.
         * @param path File to consider
         * @return true to exclude it, false to keep it
        **/
        private static function FilterHidden(path:File):Boolean
        {
            return path.isHidden;
        }

        /**
         * Flash an error indicator
        **/
        internal function ErrorIndicate(whereXY:Object) : void
        {
            var mc : MovieClip = new ErrorIndicator();
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
        }
        
    }
}
    
