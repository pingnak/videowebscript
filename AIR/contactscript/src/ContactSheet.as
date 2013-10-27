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
        public static var CONTACT_PROLOG  : String = SCRIPT_TEMPLATES+"index_prolog.html";

        /** Link to folder index */
        public static var INDEX_INDEX     : String = SCRIPT_TEMPLATES+"index_index.html";

        /** Separate HTML into a block that is separately loadable */
        public static var INDEX_TABLE     : String = SCRIPT_TEMPLATES+"index_thumbnails.html";
        
        /** A movie file link with player logic */
        public static var INDEX_FILE      : String = SCRIPT_TEMPLATES+"index_file.html";
        
        /** End of movie player html file */
        public static var CONTACT_EPILOG  : String = SCRIPT_TEMPLATES+"index_epilog.html";

        /** Table of contents file begin */
        public static var TOC_PROLOG      : String = SCRIPT_TEMPLATES+"TOC_prolog.html";

        /** Table of contents file end */
        public static var TOC_EPILOG      : String = SCRIPT_TEMPLATES+"TOC_epilog.html";
        
        /** Width of thumbnails for image */
        public static var THUMB_SIZE      : int = 240;

        /** Width of thumbnails for image */
        public static var COLUMNS         : int = 4;
        
        /** Offset for folder depths in TOC file */
        public static var FOLDER_DEPTH : int = 32;
        
        /** Regular expressions that we accept as 'JPEG content'*/
        public static var REGEX_JPEG       : String = ".(jpg|jpeg|png|gif)";
        
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
            var bHaveError : Boolean = false;
            trace("DoImages",root_path_image.nativePath);

            /**
             * Do parameter checks before we launch into processes
            **/
            ui.tfPathImages.text = root_path_image.nativePath;

            if( !root_path_image.exists || !root_path_image.isDirectory )
            {
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathImages);
                bHaveError = true;
            }
            // Make sure we don't go way out of range on thumb size
            if( THUMB_SIZE < 64 )
            {
                THUMB_SIZE = 64;
                ui.tfThumbnailSize.text = THUMB_SIZE.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfThumbnailSize);
                bHaveError = true;
            }
            if( THUMB_SIZE > 500 )
            {
                THUMB_SIZE = 500;
                ui.tfThumbnailSize.text = THUMB_SIZE.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfThumbnailSize);
                bHaveError = true;
            }
            
            if( COLUMNS < 1 )
            {
                COLUMNS = 1;
                ui.tfColumns.text = COLUMNS.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfColumns);
                bHaveError = true;
            }
            if( COLUMNS * THUMB_SIZE > 8192 )
            {
                COLUMNS = int(8192 / THUMB_SIZE);
                ui.tfColumns.text = COLUMNS.toString();
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfColumns);
                bHaveError = true;
            }
            if( bHaveError )
                return;
                
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
            //try
            {
                // Preload the various template elements we'll be writing for each folder/file
                var index_top : String      = LoadText(INDEX_TOPMOST) + LoadText(INDEX_CSS);
                var index_prolog : String   = index_top + LoadText(CONTACT_PROLOG); 
                var index_index : String    = LoadText(INDEX_INDEX);
                var index_table : String     = LoadText(INDEX_TABLE);
                var index_file : String     = LoadText(INDEX_FILE); 
                var index_epilog : String   = LoadText(CONTACT_EPILOG); 

                var jpgEncoder : JPGEncoder = new JPGEncoder(90);
                var bmThumbnail : BitmapData = new BitmapData(THUMB_SIZE,THUMB_SIZE,false,0x000000);
                
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
                        seded = index_prolog;
                        seded = seded.replace(/THUMB_SIZE/g,THUMB_SIZE.toString());
                        seded = seded.replace(/TITLE_TEXT/g,curr_title);
                        var index_content : String = seded;
    
                        // Iterate child folders and generate links to them
                        for( iteration = 1; iteration < curr_folders.length; ++iteration )
                        {
                            var curr_folder : File  = curr_folders[iteration];
    
                            // Filter folders with no pictures in any children from lists
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

                        // Start table content (and closing </div> for above)
                        seded = index_table;
                        seded = seded.replace(/THUMB_SIZE/g,THUMB_SIZE.toString());
                        index_content += seded;
                        
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

                            if( 0 == iteration )
                            {
                                seded = "<tr>\n<td>"+index_file+"</td>";
                            }
                            else if( 0 == (iteration % COLUMNS) )
                            {
                                seded = "</tr><tr>\n<td>"+index_file+"</td>";
                            }
                            else
                            {
                                seded = "<td>"+index_file+"</td>";
                            }
                            
                            var curr_file : File = curr_files[iteration++];
                            var curr_file_relative : String = Find.File_relative( curr_file, root );
                            var curr_file_title : String = Find.File_name( curr_file );

                            trace("ThreadPassImage:", curr_file.nativePath);
                            
                            seded = seded.replace(/FILE_TITLE/g,curr_file_title);
                            seded = seded.replace(/FILE_STYLE/g,'');
                            seded = seded.replace(/MEDIA_PATH/g,curr_file_relative);
                            seded = seded.replace(/THUMB_SIZE/g,THUMB_SIZE.toString());
                            
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
                                            tmp = Math.floor(ifd[entry]);
                                            tmp = ifd[entry] - tmp;
                                            itmp = int((tmp*1000)+0.0005);
                                            value = int(ifd[entry]).toString();
                                            if( itmp >= 100 )
                                            {
                                                if( 0 == itmp % 10 )
                                                    itmp = itmp % 10;
                                                if( 0 == itmp % 10 )
                                                    itmp = itmp % 10;
                                                if( 0 != itmp )
                                                    value += '.' + itmp;
                                            }
                                            else if( itmp >= 10 )
                                            {
                                                if( 0 == itmp % 10 )
                                                    itmp = itmp % 10;
                                                if( 0 != itmp )
                                                    value += '.0' + itmp;
                                            }
                                            else if( itmp >= 1 )
                                            {
                                                value += '.00' + itmp;
                                            }
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
                                
                                
                                scale = THUMB_SIZE / loading.width;
                                offsetY = 0.5 * (THUMB_SIZE-(loading.height*scale));
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
                                        matrix.translate(offsetY, THUMB_SIZE);
                                        seded = seded.replace(/ORIENT_ANGLE/g,270);
                                        break;
                                    case 3:     // Upside-down
                                        matrix = new Matrix();
                                        matrix.scale(scale,scale);
                                        matrix.rotate(Math.PI);
                                        matrix.translate(THUMB_SIZE, THUMB_SIZE-offsetY);
                                        seded = seded.replace(/ORIENT_ANGLE/g,180);
                                        break;
                                    case 6:     // Rotated counter-clockwise
                                        matrix = new Matrix();
                                        matrix.scale(scale,scale);
                                        matrix.rotate(0.5*Math.PI);
                                        matrix.translate(THUMB_SIZE-offsetY, 0);
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
                                var jpegdata : ByteArray = jpgEncoder.encode(bmThumbnail);
                                jpegdata.position = 0;

                                // Get rid of any leftover exif tags, now that we've been through the data
                                seded = seded.replace(/{EXIF:[^}]*\}/g,'');
                                
                                // Stick the image in as Base64 data
                                var curr_thumbnail : String = "data:image/jpeg;base64," + applet.BytesToBase64(jpegdata);
                                seded = seded.replace(/THUMB_BASE64/,curr_thumbnail);

                                index_content += seded;

                                loading.unload();
                                
                                // Do next pass on next image, when this returns
                                applet.setTimeout(ThreadPassImage);
                                
                                
                            }
                            
    
                        }
                        function ThisFolderComplete():void
                        {
                            // Emit bottom of file
                            index_content += index_epilog;
                            
                            // Now write out index file in one pass
                            var curr_index_file : File = Find.File_AddPath( root, MAIN_INDEX );
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
            /*
            catch( e:Error )
            {
                trace(e);
                ErrorIndicate(GetMovieClip("ErrorIndicator"), ui.tfPathImages);
                Interactive();
            }
            */
            // Fall out; timer threads are in charge
        }

        
        /**
         * Iterate through folders and generate a flattened Table of Contents 
         * of index.html files, throughout the tree.
        **/
        protected function DoTOC(found:Array):void
        {
            var index_top : String      = LoadText(INDEX_TOPMOST) + LoadText(INDEX_CSS);
            var TOC_prolog : String     = index_top + LoadText(TOC_PROLOG); 
            var index_index : String    = LoadText(INDEX_INDEX); 
            var index_epilog : String   = LoadText(TOC_EPILOG); 

            var folders : Array = Find.GetFolders(found);
            var root : File = folders[0];
            var curr_title : String = Find.File_nameext(root);
            var seded : String;
            var bExportedLinks : Boolean = false;
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
                    bExportedLinks = true;
                    index_content += seded;
                }
            }
            
            index_content += index_epilog;
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
                        found[i].moveToTrashAsync();
                    }
                    instance.Interactive();
                }
            }
        } 
        
        
    }
}
    
