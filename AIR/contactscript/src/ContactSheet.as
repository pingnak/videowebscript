
/*
 * Web (HTML5) MP3 player Generator
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
    import flash.net.*;
    import flash.filters.*;
    import flash.ui.*;

    import flash.desktop.NativeApplication; 
    import flash.filesystem.*;

    // https://github.com/bashi/exif-as3
    import jp.shichiseki.exif.IFD;
    import jp.shichiseki.exif.ExifInfo;
    
    /**
     * Contact sheet generator
     *
     * Build a preview frame of little images, that link to the full-sized ones.
     *
     * Add some means of viewing selected exif details, if present
    **/
    public class ContactSheet extends applet
    {
        protected static const SO_PATH : String = "ContactSheetData";
        protected static const SO_SIGN : String = "CONTACT_SIGN_01";

CONFIG::MXMLC_BUILD
{
        /** Main SWF */
        [Embed(source="./ContactSheet_UI.swf", mimeType="application/octet-stream")]
        public static const baMainSwfClass : Class;
}

        /** Where the main UI lives */
        protected var ui : MovieClip;
        
        /** What to call the index files */
        public static const HTML_INDEXES    : String = "ContactSheet.html";

        /** What to call the 'TOC' file that has all of the index.htmls in it */
        public static const MAIN_TOC        : String = "index.html";
        
        /** Where to look for script template content */
        public static const SCRIPT_TEMPLATES: String ="default"

        /** Start of movie player and available content */
        public static const PLAYER_TEMPLATE : String = "viewer_template.html";
        
        /** Table of contents file */
        public static const INDEX_TEMPLATE  : String = "index_template.html";

        /** A css file with theming details */
        public static const CSS_TEMPLATE  : String = "template.css";
        
        /** Width of thumbnails for image */
        public static const THUMB_SIZE      : int = 240;

        /** Offset for folder depths in TOC file */
        public static const FOLDER_DEPTH : int = 32;
        
        /** Regular expressions that we accept as 'JPEG content'*/
        public static const REGEX_JPEG       : String = ".(jpg|jpeg|png|gif)";

        public static const JPEG_QUALITY : int = 90; 
        
        /** Path to do the job in */
        protected var root_path_image : File;

        /** Path to do the job in */
        protected var root_path_media : File;
        
        protected var thumb_size : int = THUMB_SIZE;

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

        /** JPEG encoding options for BitmapData.encode */
        protected var jpeg_compression_quality : JPEGEncoderOptions = new JPEGEncoderOptions(JPEG_QUALITY);
        
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
            ui.tfPathImages.addEventListener( KeyboardEvent.KEY_DOWN, HitEnter );
            ui.tfThumbnailSize.addEventListener( Event.CHANGE, onFolderEdited );
            ui.tfThumbnailSize.maxChars = 3;
            ui.tfThumbnailSize.restrict = "0-9";
            ui.bFindPathImages.addEventListener( MouseEvent.CLICK, BrowsePathVideo );
            ui.bnFindExplore.addEventListener( MouseEvent.CLICK, OpenFolder );
            CheckSetup(ui.bnTOC);
            CheckSetup(ui.bnCompletionTone);
            
            ui.bnDoIt.addEventListener( MouseEvent.CLICK, DoImages );
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
                var removeIndexes:NativeMenuItem = toolMenu.addItem(new NativeMenuItem("Remove "+HTML_INDEXES+" files")); 
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
         * Process image tree
        **/
        protected function DoImages(e:Event=null):void
        {
            var bHaveError : Boolean = false;
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
            if( thumb_size < 64 )
            {
                thumb_size = 64;
                ui.tfThumbnailSize.text = thumb_size.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfThumbnailSize);
                return;
            }
            if( thumb_size > 640 )
            {
                thumb_size = 640;
                ui.tfThumbnailSize.text = thumb_size.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfThumbnailSize);
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
                var index_template : String = LoadText(player_template_file);

                const rxFolder : RegExp = /\<\!\-\-INDEX_INDEX(.*?)\-\-\>/ms;
                var index_index : String = index_template.match( rxFolder )[0];
                index_index = index_index.replace(rxFolder,"$1");

                const rxFile : RegExp = /\<\!\-\-INDEX_FILE(.*?)\-\-\>/ms;
                var index_file : String = index_template.match( rxFile )[0];
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
                var bmThumbnail : BitmapData = new BitmapData(thumb_size,thumb_size,false,0x000000);
                
                // Iterate all of the folders
                var folders : Array = Find.GetFolders(found);

                var folder_iteration : int = 0;
                applet.setTimeout(ThreadPassFolder);
                //for( folder_iteration = 0; folder_iteration < folders.length; ++folder_iteration )
                function ThreadPassFolder():void
                {
                    if( folder_iteration >= folders.length )
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
                        curr_title = Find.FixDecodeURI(curr_title);
                        seded = index_template;
                        seded = seded.replace(/THUMB_SIZE/g,thumb_size.toString());
                        seded = seded.replace(/TITLE_TEXT/g,curr_title);
                        var index_content : String = seded;

                        var folder_content : String = "";

                        // Iterate child folders and generate links to them
                        for( iteration = 1; iteration < curr_folders.length; ++iteration )
                        {
                            var curr_folder : File  = curr_folders[iteration];
    
                            // Filter folders with no pictures in any children from lists
                            total_files_folders_at_this_depth = Find.GetChildren( found, curr_folder, int.MAX_VALUE );
                            total_files_at_this_depth = Find.GetFiles(total_files_folders_at_this_depth);
                            if( total_files_at_this_depth.length > 1 )
                            {
                                var curr_index : File = Find.File_AddPath( curr_folder, HTML_INDEXES );
                                var curr_index_title : String = Find.File_nameext( curr_folder );
                                curr_index_title = Find.FixDecodeURI(curr_index_title);
                                var curr_index_relative : String = Find.File_relative( curr_index, root );

                                // Emit index for child folder
                                seded = index_index;
                                seded = seded.replace(/FOLDER_PATH/g,Find.FixEncodeURI(curr_index_relative));
                                seded = seded.replace(/FOLDER_TITLE/g,Find.EscapeQuotes(curr_index_title));                      
                                seded = seded.replace(/FOLDER_STYLE/g,'');
                                folder_content += seded;
                            }
                        }

                        // Start table content (and closing </div> for above)
                        var thumbnail_content : String = "";
                        
                        // Start image state
                        iteration = 0;
                        applet.setTimeout(ThreadPassImage);
                        // Iterate files and generate code + thumbnails
                        function ThreadPassImage():void
                        {
                            ui.tfStatus.text = "Folders:"+folder_iteration.toString()+"/"+folders.length.toString() + " Files:" + iteration.toString()+"/"+curr_files.length.toString();
                            if( iteration >= curr_files.length )
                            {
                                // Break out of 'threaded' loop
                                // Bottom part of file index file; all done
                                applet.setTimeout(ThisFolderComplete);
                                return;
                            }

                            seded = index_file;
                            var curr_file : File = curr_files[iteration++];
                            var curr_file_relative : String = Find.File_relative( curr_file, root );
                            var curr_file_title : String = Find.File_name( curr_file );
                            curr_file_title = Find.FixDecodeURI(curr_file_title);

                            trace("ThreadPassImage:", curr_file.nativePath);
                            
                            seded = seded.replace(/FILE_TITLE/g,Find.EscapeQuotes(curr_file_title));
                            seded = seded.replace(/FILE_STYLE/g,'');
                            seded = seded.replace(/MEDIA_PATH/g,Find.FixEncodeURI(curr_file_relative));
                            seded = seded.replace(/THUMB_SIZE/g,thumb_size.toString());
                            
                            var jpeg_loaded : ByteArray = new ByteArray();
                            var fs_jpeg : FileStream = new FileStream();
                            fs_jpeg.open( curr_file, FileMode.READ );
                            fs_jpeg.readBytes(jpeg_loaded);
                            fs_jpeg.close();

                            // Generate EXIF
                            var anyexif : Object = new Object();
                            var exif : ExifInfo = new ExifInfo(jpeg_loaded);
                            var bHasGPS : Boolean = false;
                            var bHasEXIF : Boolean = false;
                            if( null != exif.ifds )
                            {
                                EXIFSubstitutions(exif.ifds.primary);
                                EXIFSubstitutions(exif.ifds.exif);
                                EXIFSubstitutions(exif.ifds.gps);
                                EXIFSubstitutions(exif.ifds.interoperability);
                                //EXIFSubstitutions(exif.ifds.thumbnail);
                                function EXIFSubstitutions( ifd:IFD ):void 
                                {
                                    if( null == ifd )
                                        return;
                                    var entry : String;
                                    for( entry in ifd )
                                    {
                                        anyexif[entry] = ifd[entry];
                                        var pattern : RegExp = new RegExp("{EXIF:"+entry+"}",'g');
                                        var value : String;
                                        var split : Array;
                                        var degrees : int;
                                        var minutes : int;
                                        var seconds : Number;
                                        var ref : String;
                                        var llref : Number;
                                        var tmp : Number;
                                        var itmp : int;
                                        switch( getQualifiedClassName(ifd[entry]) )
                                        {
                                        case "Number":  // Round down floating point values
                                            value = Number(ifd[entry]).toFixed(3);
                                            while( value.charAt(value.length-1) == '0' )
                                                value = value.slice(0,value.length-1);
                                            if( value.charAt(value.length-1) == '.' )
                                                value = value.slice(0,value.length-1);
                                            break;
                                        default:
                                            value = String(ifd[entry]);
                                            break;
                                        }

                                        //trace(entry,ifd[entry]);
                                        // Try to 'fix' values that were less than human friendly
                                        switch(entry)
                                        {
                                        case "GPSLatitude":
                                            split = value.split(",");
                                            degrees = int(split[0]);
                                            minutes = int(split[1]);
                                            seconds = Number(split[2]);
                                            llref = degrees+(minutes/60)+(seconds/3600);
                                            ref = "GPSLatitudeRef" in ifd ? ifd["GPSLatitudeRef"] : "N";
                                            if( "S" == ref )
                                                llref = -llref;
                                            value = llref.toString();
                                            bHasGPS = true;
                                            break;
                                        case "GPSLongitude":
                                            split = value.split(",");
                                            degrees = int(split[0]);
                                            minutes = int(split[1]);
                                            seconds = Number(split[2]);
                                            llref = degrees+(minutes/60)+(seconds/3600);
                                            ref = "GPSLongitudeRef" in ifd ? ifd["GPSLongitudeRef"] : "W";
                                            if( "W" == ref )
                                                llref = -llref;
                                            value = llref.toString();
                                            bHasGPS = true;
                                            break;
                                        case "GPSAltitude":
                                            value = value + "m ("+int(3.28084*Number(value))+" feet)"; 
                                            break;
                                        case "Orientation":
                                            switch(int(ifd[entry]))
                                            {
                                            case 1:
                                                value = "Normal";
                                                break;
                                            case 8:
                                                value = "Rotate CCW";
                                                break;
                                            case 3:
                                                value = "Upside-down";
                                                break;
                                            case 6:
                                                value = "Rotated CW";
                                                break;
                                            case 2:
                                                value = "H-Flip";
                                                break;
                                            case 4:
                                                value = "V-Flip";
                                                break;
                                            case 5:
                                                value = "Transpose";
                                                break;
                                            case 7:
                                                value = "Transverse";
                                                break;
                                            }
                                            break;
                                        case "ExposureProgram":
                                            switch(int(ifd[entry]))
                                            {
                                            case 0: 
                                                value = "Unknown";
                                                break;
                                            case 1:
                                                value = "Manual";
                                                break;
                                            case 2:
                                                value = "Auto";
                                                break;
                                            case 3:
                                                value = "Av";
                                                break;
                                            case 4:
                                                value = "Tv";
                                                break;
                                            case 5:
                                                value = "Creative";
                                                break;
                                            case 6:
                                                value = "Action";
                                                break;
                                            case 7:
                                                value = "Portrait";
                                                break;
                                            case 8:
                                                value = "Landscape";
                                                break;
                                            }
                                            break;
                                        case "Flash":
                                            if( 0 != (int(ifd[entry]) & 1)) 
                                            {   // If it fired, include the bits for reference
                                                value = 'Fire:' + (int(value) < 0x10 ? '0x0' : '0x') + int(value).toString(16);
                                            }
                                            else
                                            {
                                                value = "None";
                                            }
                                            break;
                                        case "LensInfo":
                                            split = value.split(",");
                                            value = split[0]+'-'+split[1]+"mm f/"+split[2]+'-'+split[3];
                                            break;
                                        case "ExposureTime":
                                            bHasEXIF = true; // We'll use this as the basis of 'have camera details'
                                            tmp = Number(ifd[entry]);
                                            if( tmp < 0.25 )
                                            {   // Do fraction
                                                value = '1/'+int(1/tmp);
                                            }
                                            else
                                            {   // Round to milliseconds
                                                tmp = 0.001 * int((tmp+0.0005)*1000);
                                                value = tmp.toString();
                                            }
                                            /*
                                            tmp = int(1000000*Number(value)+0.5);
                                            tmp /= 1000;
                                            value = tmp.toString()+'ms';
                                            */
                                            break;

                                        case "MeteringMode":
                                            switch(int(ifd[entry]))
                                            {
                                            case 0:
                                                value = "Unknown";
                                                break;
                                            case 1:
                                                value = "Average";
                                                break;
                                            case 2:
                                                value = "CWA";//"CenterWeightedAverage";
                                                break;
                                            case 3:
                                                value = "Spot";
                                                break;
                                            case 4:
                                                value = "Multi-Spot";
                                                break;
                                            case 5:
                                                value = "Pattern";
                                                break;
                                            case 6:
                                                value = "Partial";
                                                break;
                                            case 255:
                                                value = "other";                                            
                                                break;
                                            }
                                            break;
                                            
                                        case "SensitivityType":
                                            switch(int(ifd[entry]))
                                            {
                                            case 0:
                                                value = "Unknown";
                                                break;
                                            case 1:
                                                value = "Standard Output Sensitivity";
                                                break;
                                            case 2:
                                                value = "Recommended Exposure Index";
                                                break;
                                            case 3:
                                                value = "ISO Speed";
                                                break;
                                            case 4:
                                                value = "Standard Output Sensitivity and Recommended Exposure Index";
                                                break;
                                            case 5:
                                                value = "Standard Output Sensitivity and ISO Speed";
                                                break;
                                            case 6:
                                                value = "Recommended Exposure Index and ISO Speed";
                                                break;
                                            case 7:
                                                value = "Standard Output Sensitivity, Recommended Exposure Index and ISO Speed";
                                                break;
                                            }
                                            break;
                                        default:
                                            break;
                                        }
                                        // Detect if any of this was desired in output
                                        if( 0 != seded.match(pattern).length )
                                        {
                                            bHasEXIF = true;
                                            seded = seded.replace(pattern,value);
                                        }
                                    }
                                }
                                var s : String;
                                for( s in anyexif )
                                if( String(anyexif[s]).length < 100 )
                                    trace(s,anyexif[s]);
                                
                            }
                            // If no exif details, hide the table
                            seded = seded.replace(/EXIF_DATA_STYLE/g,bHasEXIF?'':'display:none;');
                            
                            // If no GPS, hide the GPS links
                            seded = seded.replace(/GPS_LINK_CUSTOM/g,bHasGPS?'':'display:none;');
                            
                            var loading : Loader = new Loader();
                            loading.contentLoaderInfo.addEventListener( Event.COMPLETE, EncodeImage );
                            jpeg_loaded.position = 0;
                            loading.loadBytes(jpeg_loaded);
                            
                            // Give us diagnostic info
                            applet.TraceDownload(loading);
                            //loading.load(new URLRequest(curr_file.url));
                            function EncodeImage(e:Event):void
                            {
                                bmThumbnail.fillRect( bmThumbnail.rect, 0x000000 );
                                var scale : Number;
                                var offsetX : Number;
                                var offsetY : Number;
                                var matrix : Matrix;

                                // We need width and height
                                seded = seded.replace(/IMG_WIDTH/g,loading.width);
                                seded = seded.replace(/IMG_HEIGHT/g,loading.height);
                                
                                
                                scale = thumb_size / loading.width;
                                offsetY = 0.5 * (thumb_size-(loading.height*scale));
                                matrix = new Matrix( scale,0,0,scale, offsetX,offsetY );
                                // Determine if matrix should be rotated, to show the image upright
                                if( "Orientation" in anyexif )
                                {
                                    switch( anyexif.Orientation )
                                    {
                                    case 1:     // Right-side up
                                        matrix = new Matrix();
                                        matrix.scale(scale,scale);
                                        matrix.translate(0, offsetY);
                                        seded = seded.replace(/ORIENT_ANGLE/g,0);
                                        break;
                                    case 8:     // Rotated clockwise
                                        matrix = new Matrix();
                                        matrix.scale(scale,scale);
                                        matrix.rotate(-0.5*Math.PI);
                                        matrix.translate(offsetY, thumb_size);
                                        seded = seded.replace(/ORIENT_ANGLE/g,270);
                                        break;
                                    case 3:     // Upside-down
                                        matrix = new Matrix();
                                        matrix.scale(scale,scale);
                                        matrix.rotate(Math.PI);
                                        matrix.translate(thumb_size, thumb_size-offsetY);
                                        seded = seded.replace(/ORIENT_ANGLE/g,180);
                                        break;
                                    case 6:     // Rotated counter-clockwise
                                        matrix = new Matrix();
                                        matrix.scale(scale,scale);
                                        matrix.rotate(0.5*Math.PI);
                                        matrix.translate(thumb_size-offsetY, 0);
                                        seded = seded.replace(/ORIENT_ANGLE/g,90);
                                        break;
                                        // Oddball orientations
                                    case 2: //H-Flip
                                    case 4: //V-Flip
                                    case 5: //Transpose
                                    case 7: //Transverse
                                        break;
                                    }
                                }
                                else
                                {
                                    seded = seded.replace(/ORIENT_ANGLE/g,0);
                                }
                                
                                // Render and encode our thumbnail image
                                bmThumbnail.draw( loading, matrix, null, null, null, true );
                                var jpegdata : ByteArray = bmThumbnail.encode(bmThumbnail.rect, jpeg_compression_quality);
                                jpegdata.position = 0;

                                // Get rid of any leftover exif tags, now that we've been through the data
                                seded = seded.replace(/{EXIF:[^}]*\}/g,'');
                                
                                // Stick the image in as Base64 data
                                var curr_thumbnail : String = "data:image/jpeg;base64," + applet.BytesToBase64(jpegdata);
                                seded = seded.replace(/THUMB_BASE64/,curr_thumbnail);

                                thumbnail_content += seded;

                                loading.unload();
                                
                                // Do next pass on next image, when this returns
                                applet.setTimeout(ThreadPassImage);
                            }
                            
    
                        }
                        function ThisFolderComplete():void
                        {
                            // Emit bottom of file

                            // Merge thumbnails and folders into content
                            index_content = index_content.replace("/*INSERT_CSS_HERE*/",css_template);
                            index_content = index_content.replace("<!--FOLDERS_HERE-->",folder_content);
                            index_content = index_content.replace("<!--THUMBNAILS_HERE-->",thumbnail_content);
                            
                            // Now write out index file in one pass
                            var curr_index_file : File = Find.File_AddPath( root, HTML_INDEXES );
                            var fs : FileStream = new FileStream();
                            fs.open( curr_index_file, FileMode.WRITE );
                            fs.writeUTFBytes(index_content);
                            fs.close();
                            
                            // Do next pass of folder iteration
                            applet.setTimeout(ThreadPassFolder);
                        }
                    }
                    else
                    {
                        applet.setTimeout(ThreadPassFolder);
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
                trace(e.getStackTrace());
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathImages);
                Interactive();
            }
            // Fall out; timer threads are in charge
        }

        
        /**
         * Iterate through folders and generate a flattened Table of Contents 
         * of index.html files, throughout the tree.
        **/
        protected function DoTOC(found:Array):void
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
                // TOC pieces
                var index_template : String = LoadText(index_template_file);

                const rxFolder : RegExp = /\<\!\-\-INDEX_INDEX(.*?)\-\-\>/ms;
                var index_index : String = index_template.match( rxFolder )[0];
                index_index = index_index.replace(rxFolder,"$1");
            }
            catch( e:Error )
            {
                trace( "Missing or malformed INDEX_INDEX in", index_template_file.nativePath );
                trace(e.getStackTrace());
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathTemplate);
            }

            var folders : Array = Find.GetFolders(found);
            var root : File = folders[0];
            var curr_title : String = Find.File_nameext(root);
            curr_title = Find.FixDecodeURI(curr_title);

            index_template = index_template.replace(/TITLE_TEXT/g,curr_title);
            var folder_content : String = "";
            
            var bExportedLinks : Boolean = false;
            var folder_iteration : int;
            for( folder_iteration = 1; folder_iteration < folders.length; ++folder_iteration )
            {
                // Create and build top half of index file
                var curr_folder : File  = folders[folder_iteration];
                var curr_index_file : File = Find.File_AddPath( curr_folder, HTML_INDEXES );
                if( curr_index_file.exists )
                {
                    var curr_depth : int = Find.File_Depth(curr_folder,root);
                    var curr_index : File = Find.File_AddPath( curr_folder, HTML_INDEXES );
                    var curr_index_title : String = Find.File_nameext( curr_folder );
                    curr_index_title = Find.FixDecodeURI(curr_index_title);
                    var curr_index_relative : String = Find.File_relative( curr_index, root );

                    // Emit index for child folder
                    var seded : String = index_index;
                    seded = seded.replace(/FOLDER_PATH/g,Find.FixEncodeURI(curr_index_relative));
                    seded = seded.replace(/FOLDER_TITLE/g,Find.EscapeQuotes(curr_index_title));                      
                    seded = seded.replace(/FOLDER_STYLE/g,'padding-left:'+(curr_depth*FOLDER_DEPTH)+'px;');
                    bExportedLinks = true;

                    folder_content += seded;
                }
            }
            
            index_template = index_template.replace("/*INSERT_CSS_HERE*/",css_template);
            index_template = index_template.replace("<!--FOLDERS_HERE-->",folder_content);
            
            var toc_file : File = Find.File_AddPath( root, MAIN_TOC );
            if( bExportedLinks )
            {
                // Now write out index file in one pass
                var fs : FileStream = new FileStream();
                fs.open( toc_file, FileMode.WRITE );
                fs.writeUTFBytes(index_template);
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
            root_path_image = File.desktopDirectory;
            onFolderChanged();
            CheckSet( ui.bnTOC, true );
            CheckSet( ui.bnCompletionTone, true );

            CheckSet( ui.bnTempate, false );
            ChangeTemplateEnable();
            root_path_template = Find.File_AddPath( File.applicationDirectory, SCRIPT_TEMPLATES );
            onTemplateChanged();
            
            thumb_size = THUMB_SIZE;
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
            root_path_image = new File(share_data.url_image);
            if( !root_path_image.exists )
                root_path_image = File.desktopDirectory;
            onFolderChanged();
            CheckSet( ui.bnTOC, share_data.bDoTOC );
            CheckSet( ui.bnCompletionTone, share_data.bPlayTune );

            CheckSet( ui.bnTempate, share_data.bTemplate );
            root_path_template = new File(share_data.url_template);
            if( !root_path_template.isDirectory )
            {
                root_path_template = Find.File_AddPath( File.applicationDirectory, SCRIPT_TEMPLATES );
                CheckSet( ui.bnTempate, false );
            }
            ChangeTemplateEnable();
            onTemplateChanged();
            
            thumb_size = share_data.thumb_size;
            ui.tfThumbnailSize.text = thumb_size.toString();
            
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
        
        /** Find path to image content */
        protected function BrowsePathVideo(e:Event=null):void
        {
            root_path_image.addEventListener(Event.SELECT, onFolderChanged);
            root_path_image.browseForDirectory("Choose a folder");
        }
        
        /** Open an OS Finder/Explorer/whatever browser */
        protected function OpenFolder(e:Event=null):void
        {
            root_path_image.openWithDefaultApplication();
        }
        

        /** Keep track if user hand-tweaked paths, so we can make them into File objects */
        protected function onFolderEdited(e:Event=null):void
        {
            root_path_image.nativePath = ui.tfPathImages.text;
            thumb_size = int(ui.tfThumbnailSize.text);
        }
        // Convenience - hit enter in port to start up
        private function HitEnter(event:KeyboardEvent):void
        {
            if(Keyboard.ENTER == event.charCode)
            {
                onFolderEdited();
                DoImages();
            }
        }

        /** User navigated a different path */
        protected function onFolderChanged(e:Event=null):void
        {
            ui.tfPathImages.text = root_path_image.nativePath; 
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
            if( !root_path_image.exists || !root_path_image.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathImages);
                return;
            }

            var warning : String = "Every "+HTML_INDEXES+" from the path will be wiped out recursively!\n\n" + root_path_image.nativePath;
            AreYouSure( GetMovieClip("UI_AreYouSure"), "Remove Thumbnail Files", yeah, warning, "DO IT!", "ABORT!" );
            var rxIndex : RegExp = new RegExp(HTML_INDEXES,"i");
            function yeah():void
            {
                trace("Removing "+HTML_INDEXES+" Files...");
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
                        found[i].moveToTrashAsync();
                    }
                    instance.Interactive();
                }
            }
        } 
        
        
    }
}
    
