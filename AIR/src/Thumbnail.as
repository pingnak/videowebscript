
package
{
    import flash.utils.*;
    import flash.display.*;
    import flash.events.*;
    import flash.filesystem.*;

    // I'll have to migrate this out of the flash build, to a flex build
    import mx.graphics.codec.*;
    
    /**
     * Generate a thumbnail from an mp4 file.
     * Assumes you already checked whether it existed, before proceeding
     * 
     * Open a video file
     * Seek to a random location in the file
     * Capture a frame
     * Save a jpeg/png JPEGEncoder/PNGEncoder
     * http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/media/Video.html
    **/
    public class Thumbnail
    {
        public function Thumbnail( file:File )
        {
        }
        
        
    }
}
    
