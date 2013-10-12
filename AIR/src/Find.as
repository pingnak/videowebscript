
package
{
    import flash.utils.*;
    import flash.events.*;
    import flash.filesystem.*;

    /**
     * Given a path, do something like 'gnu find' on it.  Do it asynchronously
     * so that we don't 'hang' while recursing deep trees on network drives.
     *
     * First result (final_result[0]) is always the path that we searched.
     * Sorted by url
     *
     * It is up to the app to disable controls while a process is busy
     *
    **/
    public class Find extends EventDispatcher
    {
        /** Event for completion */
        public static const FOUND : String = "FindFound";

        /** Event for error/abort */
        public static const ABORT : String = "FindAbort";

        /** Update status as find progresses */
        public static const MORE : String = "FindMore";
        
        /** List of stuff we're finding, so far */
        private var final_result : Array;

        /** Stack of folders to iterate depth */
        private var stack : Array;

        /** Current path waiting for async outcome */
        private var path_curr : File;
        
        /** Stack of folders to iterate depth */
        private var filter : Function;
        
        /**
         * Given a path, do something like 'gnu find' on it.  Do it asynchronously
         * so that we don't 'hang' while recursing deep trees on network drives.
         *
         * addEventListener( this, Find.FOUND, find_finished_function )
         * addEventListener( this, Find.ABORT, find_aborted_function )
         *
         * @param path File containing root of find operation
         * @param filter A function that returns true if a path should be thrown out
        **/
        public function Find( path:File, filter:Function = null )
        {
            this.filter = null == filter ? FilterHidden : filter;
            final_result = new Array(path);
            stack = new Array();
            stack.push(path);
            FindNext();
        }

        /**
         * How many files/folders found
        **/
        public function FoundSoFar():int
        {
            return final_result.length;
        }

        /**
         * Get all results; makes a copy
        **/
        public function get results() : Array
        {
            return final_result.slice();
        }
        
        /**
         * Filter to just files
        **/
        public function get files() : Array
        {
            var i : int;
            var ret : Array = new Array();
            var file : File;
            for( i = 0; i < final_result.length; ++i )
            {
                file = final_result[i];
                if( !file.isDirectory )
                    ret.push(file);
            }
            return ret;
        }
        
        /**
         * Filter to just folders
        **/
        public function get folders() : Array
        {
            var i : int;
            var ret : Array = new Array();
            var file : File;
            for( i = 0; i < final_result.length; ++i )
            {
                file = final_result[i];
                if( file.isDirectory )
                    ret.push(file);
            }
            return ret;
        }
        
        
        /**
         * Stop a lengthy or hanged find operation
        **/
        public function Abort(e:Event=null):void
        {
            if( null != stack )
            {
                stack = null;
                dispatchEvent( new Event(ABORT) );
            }
        }

        /**
         * Wake iteration thread for another pass through a few folders
        **/
        private function FindNext(e:Event=null):void
        {
            // Detect abort condition
            if( null == stack )
                return;
            try
            {
                if( 0 == stack.length )
                {
                    // Sort results...
                    final_result.sortOn("nativePath");
                    // Delay completion slightly.
                    function InAMoment(e:Event):void
                    {
                        dispatchEvent( new Event(FOUND) );
                    }
                    var timer : Timer = new Timer(25,1);
                    timer.addEventListener( TimerEvent.TIMER_COMPLETE, InAMoment );
                    timer.start();
                    return;
                }

                // Pop another folder off the stack
                path_curr = stack.pop();
                path_curr.addEventListener(FileListEvent.DIRECTORY_LISTING, FoundSome);
                path_curr.getDirectoryListingAsync();
            }
            catch(e:Error)
            {
                trace(e);
                Abort();
            }
        }
        
        /**
         * Async folder listing got some files
        **/
        private function FoundSome(event:FileListEvent) : void
        {
            if( null == stack )
                return;
            var result:Array = event.files;
            path_curr.removeEventListener(FileListEvent.DIRECTORY_LISTING, FoundSome);
            path_curr = null;
            try
            {
                var file : File;
                var i : int;
                for( i = 0; i < result.length; ++i )
                {
                    file = result[i];
                    if( !filter(file) )
                    {
                        if( file.isDirectory )
                        {   // Add to stack of folders to iterate
                            stack.push(file);
                        }
                        final_result.push(file);
                    }
                }
                dispatchEvent( new Event(MORE) );

                // Delay dispatch of next event, to keep them from getting crossed
                var timer : Timer = new Timer(1,1);
                timer.addEventListener( TimerEvent.TIMER_COMPLETE, FindNext );
                timer.start();
            }
            catch(e:Error)
            {
                trace(e);
                Abort();
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
         * Given a path, do something like 'gnu find' on it.  Do it asynchronously
         * so that we don't 'hang' while recursing deep trees on network drives.
         *
         * @param path File containing root of find operation
         * @param filter A function that returns true if a path should be thrown out
         * @return List of files and folders
        **/
        public static function FindBlock( path:File, filter:Function = null ):Array
        {
            var result : Array = path.getDirectoryListing();
            var file : File;
            var i : int;
            if( null == filter )
                filter = FilterHidden;
            for( i = result.length-1; i >= 0; --i )
            {
                file = result[i];
                if( !filter(file) )
                {
                    if( file.isDirectory )
                    {
                        result = result.concat(FindBlock(file, filter));
                    }
                }
                else
                {
                    result.splice(i,1);
                }
            }
            // The way we tacked on the additional, recursed results left this out of whack
            result.sortOn("url");
            return result;
        }

        /** Get extension from file, with '.' still on it */
        public static function File_extension( file : File ) : String
        {
            var url = file.url;
            var index : int = url.lastIndexOf('.');
            if( -1 == index )
                return "";
            return decodeURI(url.slice(index));
        }

        /** Name of file File without extension */
        public static function File_name( file : File ) : String
        {
            var url = File_nameext(file);
            var index : int = url.lastIndexOf('.');
            if( -1 == index )
                return url;
            return decodeURI(url.slice(0,index));
        }

        /** Name of file File and extension */
        public static function File_nameext( file : File ) : String
        {
            var url = file.url;
            var index : int = url.lastIndexOf('/');
            if( -1 == index )
                return "";
            return decodeURI(url.slice(1+index));
        }
        
        /** Get path to folder containing this File, including its terminating '/' */
        public static function File_parent( file : File ) : File
        {
            var url = file.url;
            var index : int = url.lastIndexOf('/');
            if( -1 == index )
                return file;
            return new File(url.slice(0,1+index));
        }
        
        /** Get path to folder containing this File, including its terminating '/' */
        public static function File_AddPath( file : File, name:String = "" ) : File
        {
            var url = file.url;
            if( '/' == url.charAt(url.length-1) )
            {
                return new File(url + name);
            }
            return new File(url + '/' + name);
        }

        /** Change or remove extension on file  */
        public static function File_newExtension( file : File, ext:String = "" ) : File
        {
            if( "" != ext && '.' != ext.charAt(0) )
            {
                ext = '.' + ext;
            }
            var url = file.url;
            var index : int = url.lastIndexOf('.');
            if( -1 == index )
                return new File( url + ext );
            return new File( url.slice(0,index) + ext );
        }
        
        /** Remove everything that's the same as 'root/'
         * @param file Path to test
         * @param root Root of tree 'file' is in
         * @return Just the portion of the path different from root/
        **/
        public static function File_relative( file : File, root : File ) : String
        {
            var ret : String = root.getRelativePath(file,true);
            return decodeURI(null == ret ? file.url : ret);
        }

        /** How deep is file; how many '/' does it have, different from the root? 
         * @param file Path to test
         * @param root Root of tree 'file' is in
         * @return How many slashes past root; 0 if in root
        **/
        public static function File_Depth( file : File, root : File ) : int
        {
            const regex : RegExp = /\//g;
            var rel : String = File_relative( file, root );
            return rel.match(regex).length;
        }

        /**
         * Filter tree for only a certain path
         * @param tree Array in same format as 'Find' makes, with root as a[0]
         * @param path Path to get children of
         * @param max_depth 0 for only current folder, higher numbers for greater depth
         * @return Any matches, and the original path passed in as the a[0]
        **/
        public static function GetChildren( tree : Array, path : File, max_depth : uint = 0/*uint.MAX_VALUE*/  ) : Array
        {
            var i : int;
            var f : File;
            var root : File = tree[0];
            var url : String = path.url;
            var depth : int = File_Depth(path,root);
            var found : Array = [path];
            for( i = 0; i < tree.length; ++i )
            {
                f = tree[i];
                if( -1 != f.url.indexOf(url) )
                {
                    if( max_depth >= File_Depth(f,path)-depth )
                    {
                        found.push(f);
                    }
                }
            }
            return found;
        }

        /**
         * Get a list of folders in an array tree
        **/
        public static function GetFolders( tree : Array ) : Array
        {
            var ret : Array = new Array();
            var i : int;
            var f : File;
            for( i = 0; i < tree.length; ++i )
            {
                f = tree[i];
                if( f.isDirectory )
                {
                    ret.push(f);
                }
            }
            return ret;
        }

        /**
         * Get a list of files in an array tree
        **/
        public static function GetFiles( tree : Array ) : Array
        {
            var ret : Array = new Array();
            var i : int;
            var f : File;
            for( i = 0; i < tree.length; ++i )
            {
                f = tree[i];
                if( !f.isDirectory )
                {
                    ret.push(f);
                }
            }
            return ret;
        }
        
        /**
         * Re-filter contents
         * @param tree A tree, like results would return 
         * @param filter A function that returns true if a path should be thrown out
        **/
        public static function Filter( tree : Array, filter : Function ) : Array
        {
            var ret : Array = new Array();
            ret.push(tree[0]);
            var i : int;
            var f : File;
            for( i = 1; i < tree.length; ++i )
            {
                f = tree[i];
                if( !filter(f) )
                {
                    ret.push(f);
                }
            }
            return ret;
        }

        /**
         * Re-filter contents
         * @param tree A tree, like results would return 
         * @param file A path to check 
         * @return true if this file exists in 'tree'
        **/
        public static function Exists( tree : Array, file : File ) : Boolean
        {
            var regex : RegExp = new RegExp(file.url,"i");
            var i : int;
            for( i = 0; i < tree.length; ++i )
            {
                if( tree[i].url.match(regex) )
                    return true;
            }
            return false;
        }
        
    }
}
    
