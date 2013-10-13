
package
{
    import flash.net.*;
    import flash.media.*;
    import flash.utils.*;
    import flash.display.*;
    import flash.events.*;
    import flash.filesystem.*;

    // I'll have to migrate this out of the flash build, to a flex build
    //import mx.graphics.codec.*;
    
    /**
     * Generate a thumbnail from an mp4 file.
     * Assumes you already checked whether it existed, before proceeding
     *
     * This would be MUCH simplified if I could find an event that definitely 
     * told me the video had been rendered, and then definitely told me that 
     * maybe it hadn't been.
     * 
     * Open a video file
     * Seek to a random location in the file
     * Capture a frame
     * Save a jpeg/png JPEGEncoder/PNGEncoder
     * http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/media/Video.html
     *
     * Kind of evolved to a queue of thumbnails, since everything is asynchronous
     * Use AddTask to add video+thumbnail paths, then call Startup and wait for 'Event.COMPLETE'
    **/
    public class Thumbnail extends EventDispatcher
    {
        // Events
        public static const SNAPSHOT_READY : String = "snapshot";
        public static const COMPLETE : String = Event.COMPLETE;
        
        internal var connection : NetConnection;
        internal var stream : NetStream;
        internal var video : Video;
        internal var _metadata : Object;

        internal var mcPlace : MovieClip;
        internal var thumbsize : uint;
        
        internal var videoFile : File;
        internal var thumbFile : File;
        
        // A 'playlist' for the thumbnailer to consume, behind the scenes
        internal var queue : Array;
        
        internal var bSeekHappened : Boolean;
        
        public function get busy() : Boolean { return 0 != queue.length; }
        public function get queue_length() : int { return queue.length; }
        public function get metadata() : Object { return null == _metadata ? new Object() : _metadata; }

        public function get video_file() : File { return videoFile; }
        public function get thumb_file() : File { return thumbFile; }
        public function get video_object() : Video { return video; }
        public function get video_stream() : NetStream { return stream; }
        
        public function Thumbnail( mcPlace : MovieClip, thumbsize : uint = 128 )
        {
            this.thumbsize = thumbsize;
            this.mcPlace = mcPlace;
            queue = new Array();

            connection = new NetConnection();
			connection.connect(null);
			
			stream = new NetStream(connection);
			stream.addEventListener(NetStatusEvent.NET_STATUS, onNetStatus );
			stream.addEventListener(AsyncErrorEvent.ASYNC_ERROR, onError );
			stream.addEventListener(IOErrorEvent.IO_ERROR, onError );
			stream.addEventListener(Event.VIDEO_FRAME, trace );
			stream.client = this;
			
			video = new Video(thumbsize, thumbsize);
			video.attachNetStream( stream );
			mcPlace.addChild(video);            
        }

        /**
         * Clean up any dangling work 
        **/
        public function Cleanup():void
        {
            if( null != stream )
            {
                queue = new Array();
                if( null != video.parent )
                {
                    video.parent.removeChild(video);
                }
                stream.close();
                stream = null;
            }
        }

        /** 
         * Since there are asynchronous components to playback
         * we need to pile these requests into a queue, and perform 
         * them as they get done
        **/
        public function AddTask( file:File, thumb:File ) : void
        {
            queue.push( { file:file, thumb:thumb } );
        }

        /** Pop a task off the queue */
        protected function PopTask( e:Event=null ) : void
        {
            if( 0 == queue.length )
            {
                dispatchEvent( new Event( COMPLETE ) );
                return;
            }
            var queueObj = queue[0];
            videoFile = queueObj.file;
            thumbFile = queueObj.thumb;
            stream.close();
            bSeekHappened = false;
			stream.play( videoFile.url );
        }
        
        /**
         * How many things to do
        **/
        public function Startup( e:Event=null ) : void
        {
            PopTask();
        }

		protected function onError(event:Event):void
		{
		    trace( event.toString() );
		    // Skip this
		    PopTask();
		}
        
		protected function onNetStatus(event:NetStatusEvent):void 
		{
		    TraceObject( event.toString(), event.info );
		    switch( event.info.code )
		    {
		    // As far as I can tell, this is the 'last' thing I get, after
		    // starting, seeking, pausing, so this is what I capture based on
		    case "NetStream.Video.DimensionChange":
		        //Capture();
		        break;
		    case "NetStream.Seek.Notify":
		        bSeekHappened = true;
		        break;
		    case "NetStream.Buffer.Full":
                if( bSeekHappened )
                {
                    // IF the seek we did happened, AND we got this message, we would
                    // usually (but not always) get NetStream.Video.DimensionChange, and
                    // could trigger based on that.  But since we don't always get it, 
                    // this kludge is in place to WAIT A BIT after the buffer fills, 
                    // because usually that message happened within ~100ms.  FML.
                    
                    // Too bad there isn't something like a 'NetStatusEvent.FIRST_FRAME'
                    // generated after playback starts up from beginning, or after a 
                    // seek.
                    var timer : Timer = new Timer( 250, 1 );
                    timer.addEventListener( TimerEvent.TIMER, Capture );
                    timer.start();
                    
                    bSeekHappened = false;
                }
		        break;
		    }
		}
		public function onCuePoint(info:Object):void 
		{
		    TraceObject("onCuePoint",info);
		}
		public function onImageData(info:Object):void 
		{
		    TraceObject("onImageData",info);
		}
		public function onMetaData(info:Object):void 
		{
		    //TraceObject("onMetaData",info);
		    trace("onMetaData");
            this._metadata = info;
            // Pick a frame, any frame, from about 15%~25%
            // Hopefully, no 'spoilers' that early in the movie
            var seek_to : int = (0.15*metadata.duration) + (0.1*metadata.duration*Math.random());
            stream.seek( seek_to );
            stream.pause();
            video.height = thumbsize * info.height / info.width;
            //video.y = 0.5*(thumbsize-video.height);
            
		}
		public function onPlayStatus(info:Object):void
		{
		    TraceObject("onPlayStatus",info);
		}
		public function onSeekPoint(info:Object):void
		{
		    TraceObject("onSeekPoint",info);
		}
		public function onTextData(info:Object):void
		{
		    TraceObject("onTextData",info);
		}
		public function onXMPData(info:Object):void 
		{
		    TraceObject("onXMPData",info);
		}
		protected function TraceObject(sz:String, info:Object):void
		{
		    //trace(sz,':',getTimer(),videoFile.url);
		    //for( var s : String in info ) trace("\t",s,info[s]);
		}
        
		/**
		 * Ready for frame capture.
		**/
        private function Capture(e:Event=null) : void
        {
            trace("Capture",thumbFile.nativePath);
            if( null == stream )
                return;

            // Let app know to set up any capture decorations
            // Makes the code a touch more 'reusable' by abstracting this
            // Add crap to the template, draw on it, whatever
            dispatchEvent( new Event( SNAPSHOT_READY ) );
            
            // Give UI a chance to refresh after calling back
            var timer : Timer = new Timer( 10, 1 );
            timer.addEventListener( TimerEvent.TIMER, DoCapture );
            timer.start();
            
        }

        /**
         * Write a captured image
        **/
        protected function DoCapture(e:Event):void
        {
            // Render to bitmap
            var bmd : BitmapData = new BitmapData(thumbsize, mcPlace.height, false, 0);
            bmd.draw(mcPlace);
            
            // Encode jpeg
            var jpeg : JPGEncoder = new JPGEncoder(80);
            var bytes : ByteArray = jpeg.encode(bmd);
            
            // Write jpeg
            var fs:FileStream = new FileStream();
            fs.open( thumbFile, FileMode.WRITE );
            fs.writeBytes(bytes,0,bytes.length );
            fs.close();

            // Remove current queue, see if there's more to do
            queue.shift();
            PopTask();
        }
   
    }
}
    
