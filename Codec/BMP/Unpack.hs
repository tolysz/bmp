{-# OPTIONS_HADDOCK hide #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Codec.BMP.Unpack
	( unpackFileHeader
	, unpackBitmapInfoV3
	, unpackBMPToRGBA32
	, unpackRGB24ToRGBA32)
where	
import Codec.BMP.Types
import Codec.BMP.Base
import Foreign.Ptr
import Foreign.Marshal.Alloc
import Foreign.Storable
import System.IO.Unsafe
import Data.Word
import Data.ByteString		as BS
import Data.ByteString.Unsafe	as BS

-- | Unpack a `FileHeader` from a `ByteString`
unpackFileHeader :: ByteString -> FileHeader
unpackFileHeader str	
	= FileHeader
	{ fileHeaderType	= getLSBWord16 str 0
	, fileHeaderSize	= getLSBWord32 str 2
	, fileHeaderReserved1	= getLSBWord16 str 6
	, fileHeaderReserved2   = getLSBWord16 str 8
	, fileHeaderOffset	= getLSBWord32 str 10 }


-- | Unpack a `BitmapInfoV3` header from a `ByteString`.
unpackBitmapInfoV3 :: ByteString -> BitmapInfoV3
unpackBitmapInfoV3 str
	= BitmapInfoV3
	{ dib3Size		= getLSBWord32 str 0
	, dib3Width		= getLSBWord32 str 4
	, dib3Height		= getLSBWord32 str 8
	, dib3Planes		= getLSBWord16 str 12 
	, dib3BitCount		= getLSBWord16 str 14
	, dib3Compression	= getLSBWord32 str 16
	, dib3ImageSize		= getLSBWord32 str 20
	, dib3PelsPerMeterX	= getLSBWord32 str 24
	, dib3PelsPerMeterY	= getLSBWord32 str 28
	, dib3ColorsUsed	= getLSBWord32 str 32
	, dib3ColorsImportant	= getLSBWord32 str 36 }
	

-- | Unpack a BMP image to a string of RGBA component values,
--	with no padding between the lines.
--	The A (alpha) value is set to 255 for every pixel.
unpackBMPToRGBA32 :: BMP -> ByteString
unpackBMPToRGBA32 bmp 
 = case bmpBitmapInfo bmp of
	InfoV3 info
	 -> let	bytesPerLine	= fromIntegral $ dib3ImageSize info `div` dib3Height info
		padPerLine	= fromIntegral $ bytesPerLine  - (dib3Width info * 3)
	    in	unpackRGB24ToRGBA32 
			(fromIntegral $ dib3Width info) 
			(fromIntegral $ dib3Height info)
			padPerLine
			(bmpRawImageData bmp)


-- | Unpack raw, uncompressed 24 bit BMP image data to a string of RGBA component values,
--	with no padding between the lines. 
--	The A (alpha) value is set to 255 for every pixel.
unpackRGB24ToRGBA32
	:: Int 		-- image width
	-> Int		-- image height
	-> Int		-- number of padding bytes at the end of each line.
	-> ByteString 	-- input string
	-> ByteString
		
unpackRGB24ToRGBA32 width height pad str
 = let	sizeDest	= width * height * 4
   in 	unsafePerformIO
       	 $ allocaBytes sizeDest      $ \bufDest -> 
   	   BS.unsafeUseAsCString str $ \bufSrc  ->
            do	unpackRGB24ToRGBA32' width height pad (castPtr bufSrc) (castPtr bufDest)
		packCStringLen (bufDest, sizeDest)
		
-- We're doing this via Ptrs because we don't want to take the
-- overhead of doing the bounds checks in ByteString.index.
unpackRGB24ToRGBA32' width height pad ptrSrc ptrDest 
 = go 0 0 0 0
 where
	go posX posY oSrc oDest
	 -- skip over padding bytes.
	 | posX == width 
	 = go 0 (posY + 1) (oSrc + pad) oDest
	
	 -- we've finished the image.
	 | posY == height
	 = return ()
	
	 -- process a pixel.
	 | otherwise
	 = do	blue  :: Word8	<- peekByteOff ptrSrc (oSrc + 0)
		green :: Word8	<- peekByteOff ptrSrc (oSrc + 1)
		red   :: Word8	<- peekByteOff ptrSrc (oSrc + 2)

		pokeByteOff ptrDest (oDest + 0) red
		pokeByteOff ptrDest (oDest + 1) green
		pokeByteOff ptrDest (oDest + 2) blue
		pokeByteOff ptrDest (oDest + 3) (255 :: Word8)
		
		go (posX + 1) posY (oSrc + 3) (oDest + 4)

