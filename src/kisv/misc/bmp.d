module kisv.misc.bmp;

import kisv.all;
import std.stdio : File;
import std.math  : abs;

/**
 *  Handle the Windows .BMP image file format.
 *
 *  Only BGR888 and ABGR8888 formats can be loaded.
 *
 *  The loaded data is stored as RGBA (4 bytes per pixel)
 *  and from top-left to bottom-right:
 *  eg.
 *  0----- x+
 *  |
 *  |
 *  y+
 */
final class BMP {
    uint width;
    uint height;
    uint bytesPerPixel;
    ubyte[] data;           // width*height*bytesPerPixel bytes

	/**
	 *	Assumes BGR_888 or ABGR_8888 format
	 *
	 *  For simplicity, the result will always be in rgba (4 bytes per pixel) format
	 */
    static auto read(string filename) {
        auto bmp   = new BMP();
    	scope file = File(filename, "rb");

    	HEADER[1] headerArray;
    	DIBHEADER[1] dibArray;
    	file.rawRead(headerArray);
    	file.rawRead(dibArray);

    	HEADER header = headerArray[0];
    	DIBHEADER dib = dibArray[0];

        if(header.dataOffset > HEADER.sizeof + DIBHEADER.sizeof) {
            // skip some stuff before the actual pixel data starts
    	    file.seek(header.dataOffset);
    	}

    	if(dib.bitsPerPixel!=24 && dib.bitsPerPixel!=32) {
    	    throwIf(true, "Unsupported BMP: '%s'".format(filename));
    	}

        // If dib.height > 0 then pixel data is in bottom-left to top-right order.
        // If dib.height < 0 then pixel data is in top-left to bottom-right order.
        // We want it in top-left to bottom-right layout.
		// Also we will convert to rgba
    	bmp.width	      = dib.width;
    	bmp.height        = abs(dib.height);
    	bmp.bytesPerPixel = dib.bitsPerPixel/8;

        bool invertY      = dib.height > 0;
    	int padding		  = (bmp.width*bmp.bytesPerPixel) & 3;
    	int widthBytes	  = bmp.width*bmp.bytesPerPixel + padding;
    	ubyte[] line	  = new ubyte[widthBytes];

		// From this point we want the result to be 4 bytes per pixel
        bmp.data.length = bmp.width*bmp.height*4;

        long dest = invertY ? (bmp.height-1)*bmp.width.as!int*4 : 0;
		long add = bmp.width.as!int*4 * (invertY ? -1 : 1);

    	for(auto y=0; y<bmp.height; y++) {
    		file.rawRead(line);

            for(auto x=0; x<bmp.width; x++) {

				long j = x*4;

                if(bmp.bytesPerPixel==3) {
                    // convert bgr to rgba
                    long i = x*3;

                    ubyte b = line[i];
                    ubyte g = line[i+1];
                    ubyte r = line[i+2];

                    bmp.data[dest+j]   = r;
                    bmp.data[dest+j+1] = g;
                    bmp.data[dest+j+2] = b;
					bmp.data[dest+j+3] = 255;
                } else {
                    // convert abgr to rgba

                    ubyte a = line[j];
                    ubyte b = line[j+1];
                    ubyte g = line[j+2];
                    ubyte r = line[j+3];

                    bmp.data[dest+j]   = r;
                    bmp.data[dest+j+1] = g;
                    bmp.data[dest+j+2] = b;
                    bmp.data[dest+j+3] = a;
                }
            }
    		dest += add;
    	}
		bmp.bytesPerPixel = 4;
    	return bmp;
    }
}

private:

align(1) struct HEADER { align(1):
	ubyte magic1 = 'B', magic2 = 'M';
	uint fileSize = 0;
	short reserved1;
	short reserved2;
	uint dataOffset = HEADER.sizeof + DIBHEADER.sizeof;
}
static assert(HEADER.sizeof==14);

struct DIBHEADER {
	uint size = DIBHEADER.sizeof;
	int width;
	int height;
	ushort planes = 1;
	ushort bitsPerPixel = 24;
	uint compression = 0;	// no compression
	uint imageSize = 0;		// o for uncompressed bitmaps
	int horizRes = 2835;
	int vertRes = 2835;
	uint numColours = 0;
	uint numImportantColours = 0;
}
static assert(DIBHEADER.sizeof==40);
