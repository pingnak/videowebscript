
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
     * Utility base class, to make reusing some of the bits and pieces easier
    **/
    public class applet extends MovieClip
    {
        /** App instance */
        public static var instance : applet = null;
        
        /** Keep track of timeouts, so that they can be cancelled */
        private static var _timeouts : Dictionary = new Dictionary();

        public function applet()
        {
            instance = this;

            // Keep kicking the random number generator
            addEventListener( Event.ENTER_FRAME, Entropy );

        }

        /**
         * Keep random output inconsistent
        **/
        internal function Entropy(e:Event=null):void
        {
            Math.random();
        }

        /**
         * Put app into non-interactive mode
        **/
        public function isBusy():Boolean
        {
            return false;
        }
        
        /**
         * Put app into non-interactive mode
        **/
        public function Busy(e:Event=null):void
        {
        }
        
        /**
         * Put app into interactive mode
        **/
        public function Interactive(e:Event=null):void
        {
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

        // A nice disabler helper
        public static function EnableControl(dobj:DisplayObject, bEnable:Boolean = true):void
        {
            if( dobj is InteractiveObject )
            {
                var iobj : InteractiveObject = dobj as InteractiveObject;
                iobj.tabEnabled = iobj.mouseEnabled = bEnable; 
                if( iobj is DisplayObjectContainer )
                    ( iobj as DisplayObjectContainer ).mouseChildren = bEnable;
            }
            dobj.alpha = bEnable ? 1 : 0.5;
        }

        /**
         * Run through a UI and sort its tabs by depth, rather than Flash's random/created order 
         * @param ui Where to start
        **/
        public static function SortTabs(ui:DisplayObjectContainer) : void
        {
            // Make tab order match depth of objects
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
        }
        
        /**
         * Do a confirmation dialog for dangerous-looking stunts
         * @param ui MovieClip to use for confirmation; must contain: tfBody, tfYes, tfNo, bnYES, bnNO 
         * @param title Window title
         * @param body  Body text explaining why we're stopping
         * @param yes   Yes button text
         * @param no    No button text
        **/
        internal static function AreYouSure( ui : MovieClip, title:String, onYes : Function, body:String="Keep going?", yes:String="Yes", no:String="No" ) : void
        {
            var bYes : Boolean = false;
            
            if( instance.isBusy() )
                return;
            instance.Busy();
            
            // create NativeWindowInitOptions
            var windowInitOptions:NativeWindowInitOptions = new NativeWindowInitOptions();
            windowInitOptions.type = NativeWindowType.NORMAL;
            windowInitOptions.minimizable = false;
            windowInitOptions.resizable = false;
            windowInitOptions.maximizable = false;
            windowInitOptions.systemChrome = NativeWindowSystemChrome.STANDARD;
            windowInitOptions.transparent = false;

            // create new NativeWindow
            var popupWindow:NativeWindow = new NativeWindow(windowInitOptions);

            // Text
            SortTabs(ui);
            ui.tfBody.text = body;
            ui.tfYES.text = yes;
            ui.tfNO.text = no;
            popupWindow.title = title;
            
            ui.bnYES.addEventListener(MouseEvent.CLICK, onConfirm);
            ui.bnNO.addEventListener(MouseEvent.CLICK, onDeny);
            popupWindow.addEventListener( Event.CLOSE, onClose );
            
            function onClose(e:Event):void
            {
                if( !bYes )
                    instance.Interactive();
            }
            function onConfirm(e:Event):void
            {
                bYes = true;
                popupWindow.close();
                onYes.call(instance);
            }
            function onDeny(e:Event):void
            {
                popupWindow.close();
                instance.Interactive();
            }
            
            
            // for a popup it might be nice to have it activated and on top
            // resize
            //popupWindow.width = ui.width;
            //popupWindow.height = ui.height;

            // add
            popupWindow.stage.addChild(ui);
            popupWindow.stage.align = StageAlign.TOP_LEFT;
            popupWindow.stage.scaleMode = StageScaleMode.NO_SCALE;

            popupWindow.alwaysInFront = true;
            popupWindow.activate();
            
        }
        
        /**
         * Flash an error indicator
         * mc: MovieClip with indicator art
         * whereXY: Any object with x, y in it (Point, DisplayObject, etc.)
        **/
        internal function ErrorIndicate(mc:MovieClip, whereXY:Object) : void
        {
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
            PlaySound("fxBeepBoop");
        }

        
        /**
         * Load a resource that's in a ByteArray
         * @param ba ByteArray to load
         * @return Loader to add events to, or poll, and get the DisplayObject from; or just add it to DisplayList, and let it show up on its own
        **/
        public static function LoadFromByteArray( ba : ByteArray ) : Loader
        {
            var loader : Loader = new Loader();
            var loaderContext:LoaderContext = new LoaderContext(false);
            loaderContext.checkPolicyFile = false;
            loaderContext["allowCodeImport"] = true;
            loaderContext.applicationDomain = ApplicationDomain.currentDomain;
            loader.loadBytes(ba,loaderContext);
            return loader;
        }

        /**
         * Resolve a class id that may have been loaded
         * @param id Class name to resolve
         * @return Class
        **/
        public static function GetClass( id : String ) : Class
        {
            return ApplicationDomain.currentDomain.getDefinition(id) as Class;
        }

        /**
         * Get a DisplayObject from class name
         * @param id Class name to resolve
         * @return MovieClip, or Bitmap, or null
        **/
        public static function GetDisplayObject( id : String ) : DisplayObject
        {
            var cls : Class = ApplicationDomain.currentDomain.getDefinition(id) as Class;
            return new cls() as DisplayObject;
        }

        /**
         * Get a MovieClip from class name
         * @param id Class name to resolve
         * @return MovieClip we're expecting, or null
        **/
        public static function GetMovieClip( id : String ) : MovieClip
        {
            var cls : Class = ApplicationDomain.currentDomain.getDefinition(id) as Class;
            return new cls() as MovieClip;
        }
        
        /**
         * Play a Sound
         * @param id What sound to play (matches class export in Flash)
         * @params... Parameters to pass to Sound.Play
         * @return SoundChannel from play()
        **/
        public static function PlaySound( id : String, ...params ) : SoundChannel
        {
            var cls : Class = ApplicationDomain.currentDomain.getDefinition(id) as Class;
            var sound : Sound = new cls();
            return sound.play.apply(id,params);
        }

        
        /**
         * Load a text file (e.g. HTML template parts)
         * @param path Where to find the text
         * @return String containing the text
        **/
        protected function LoadText( path:File ) : String
        {
            try
            {
                if( path.exists && !path.isDirectory )
                {
                    var fs:FileStream = new FileStream();
                    fs.open(path, FileMode.READ);
                    var ret : String = fs.readUTFBytes(fs.bytesAvailable);
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
        
        /**
         * Do something in a bit
         * @param function Function to call back; doesn't need any special parameters
         * @param ms Milliseconds to wait; anything below 1000/app frame rate will generally happen next frame
        **/
        public static function setTimeout( func:Function, ms : int = 16 ) : void
        {
            var timer : Timer = new Timer( ms, 1 );
            timer.addEventListener( TimerEvent.TIMER, doTimerCallback );
            timer.start();
            _timeouts[timer] = func;
        }
        /** 
         * @private
         * Do the callback for setTimeout
        **/
        private static function doTimerCallback(e:Event) : void
        {
            var timer : Timer = e.currentTarget as Timer;
            if( timer in _timeouts )
            {
                var func : Function = _timeouts[timer];
                delete _timeouts[timer];
                func();
            }
        }
        /** 
         * Stop all scheduled timeouts
        **/
        public static function AbortTimeouts() : void
        {
            var key : Object;
            for (key in _timeouts) 
            {
                (key as Timer).stop();
            }
            _timeouts = new Dictionary();
        }

        /**
         * Encode data to Base64 format
        **/
        public static function BytesToBase64( ba:ByteArray, length:uint = uint.MAX_VALUE ):String
        {
            var result:String = "";
            var remains : uint = Math.min( ba.length-ba.position, length );
            var encodes : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
            var shift : uint = 0;
            while( 3 <= remains )
            {
                shift =  (ba.readByte()&0xff) << 16;
                shift |= (ba.readByte()&0xff) << 8;
                shift |= (ba.readByte()&0xff);
                result += encodes.charAt((shift>>18) & 0x3f);
                result += encodes.charAt((shift>>12) & 0x3f);
                result += encodes.charAt((shift>> 6) & 0x3f);
                result += encodes.charAt(shift & 0x3f);
                remains -= 3;
            }
            switch( remains )
            {
            case 2:
                shift =  (ba.readByte()&0xff) << 16;
                shift |= (ba.readByte()&0xff) << 8;
                result += encodes.charAt((shift>>18) & 0x3f);
                result += encodes.charAt((shift>>12) & 0x3f);
                result += encodes.charAt((shift>> 6) & 0x3f);
                result += '=';
                break;
            case 1:
                shift = (ba.readByte()&0xff) << 16;
                result += encodes.charAt((shift>>18) & 0x3f);
                result += encodes.charAt((shift>>12) & 0x3f);
                result += '==';
                break;
            case 0:
                break;
            }
            return result;
        }

        /**
         * Trace common download status events
        **/
        public static function TraceDownload( loader : EventDispatcher ) : void
        {
            if( loader is Loader )
                loader = (loader as Loader).contentLoaderInfo;
            loader.addEventListener( IOErrorEvent.IO_ERROR, trace );
            loader.addEventListener( SecurityErrorEvent.SECURITY_ERROR, trace );
CONFIG::DEBUG {
            loader.addEventListener( Event.OPEN, trace );
            loader.addEventListener( Event.COMPLETE, trace );
            loader.addEventListener( Event.INIT, trace );
            loader.addEventListener( HTTPStatusEvent.HTTP_STATUS, trace );
            // loader.addEventListener( ProgressEvent.PROGRESS, trace );
}
        }        
        
        /**
         * Dump public contents of an Object/Dictionary/Array
         * @param o Object to trace publicly accessible contents of
         * @param s If passed, tells us something about this object
        **/
        public static function TraceObject( o:*, s:* = "" ) : void
        {
CONFIG::DEBUG {
            { CONFIG::DEBUG { trace(s+": "+o ); } }
            if( o is XML )
            {
                { CONFIG::DEBUG { trace(o.toXMLString() ); } }
            }
            else
            {
                for( var m:String in o )
                {
                    { CONFIG::DEBUG { trace("    " + m + ": " + o[m] ); } }
                }
            }
}
        }
    }
}
    
