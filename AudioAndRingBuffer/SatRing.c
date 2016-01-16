/**
//  SatRing.c
//  Created by James Bilitski 
 */
#include "SatRing.h"
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <assert.h>


#define EXTRA_SAFETY_FRAMES 2  // defines a little extra space that will not be read to avoid read/write collision  - MUST be an even number >= 2

//private
static int writeRing(SatRing_t * Ring,  uint8_t* frameSrc, int numFrames );
static int readRing(SatRing_t * Ring,  uint8_t* outputBuffer);

// helper function to write a ring.
static int writeRing(SatRing_t * Ring,  uint8_t* frameSrc, int numFrames )
{
	if ( Ring -> isInitialized == false)
	{
		assert( 0 );  // ring not initialized
	}

	// Ensure number of bytes requested is less than the size of the ring
	if ( numFrames >= Ring -> framesInRing)
	{
		assert( 0 );  // ring too small
	}
	long int bytesToEnd;
	long int bytesWrittenSoFar = 0;
	long int totalBytesToWrite;
	uint8_t * buf;
	uint8_t ** endPos;
	uint8_t ** writePos;
	int* framesWrittenPtr;
	
	
	totalBytesToWrite = numFrames * Ring->channelsPerFrame * Ring->bytesPerChannel;
	


	buf		= Ring -> backRingBuf;
	endPos	= &Ring -> backRingEnd;
	writePos= &Ring -> backRingWritePos;
	framesWrittenPtr = &Ring -> backRingFramesWritten;

	
	// how many frames can I write before it wraps
	bytesToEnd = 1 + *endPos - *writePos; // in bytes!!!
	
	// factor of 4.  ie ensure we can write a whole frame. It really should not fail
	if ( (bytesToEnd % Ring -> bytesPerChannel != 0))
	{
		assert(0); // invalid number of bytes remaining
	}

	
	// are we going to wrap around the ring during copy?
	if ( bytesToEnd > totalBytesToWrite ) // only 1 memcpy needed
	{
		bytesWrittenSoFar = totalBytesToWrite;
		memcpy(*writePos, frameSrc, bytesWrittenSoFar);  
		// update write and read positions
		*writePos += bytesWrittenSoFar;
	}
	else // deal with wrapping and doing 2 memcpys
	{
		long int bytesForSecondWrite;
		bytesWrittenSoFar = bytesToEnd;
		memcpy(*writePos, frameSrc, bytesWrittenSoFar);  // write the 1st chunk and this should take us to the end
		*writePos = buf;
		bytesForSecondWrite = totalBytesToWrite - bytesWrittenSoFar; 
		memcpy(*writePos, frameSrc + bytesWrittenSoFar, bytesForSecondWrite );  //write the second chuck
		*writePos += bytesForSecondWrite;			   
	}
	
	// did we write a block of data that ended exactly at the end of the buffer?
	if ( *writePos > *endPos )
	{
		*writePos = buf;  
	}
	*framesWrittenPtr += numFrames;
	if ( *framesWrittenPtr >= Ring -> framesInRing )
	{
		*framesWrittenPtr = Ring -> framesInRing;
		Ring->backRingState = READY_FOR_READING;
	}
	
	return 0;
	
}


//  outputBuffer must be big enough to hold the data.
static int readRing(SatRing_t * Ring,  uint8_t* outputBuffer)
{
	uint8_t* readPtr;
	long int bytesToEnd;
	long int bytesWrittenSoFar = 0;
	long int totalBytesToWrite;
	
	totalBytesToWrite = Ring -> bytesPerRing - ( EXTRA_SAFETY_FRAMES * Ring->bytesPerFrame ) ; 
	
	//find a good safe spot to read with reasonably recent data
	readPtr = Ring->backRingWritePos; // this is the begninning frame but it could get over written by the writter any second now...
	readPtr += ( EXTRA_SAFETY_FRAMES * Ring->bytesPerFrame ) / 2;  // now go up for safety
	
	
	// did we wrap around when we found the read spot
	if ( readPtr > Ring -> backRingEnd )
	{
		readPtr = (readPtr - Ring -> backRingEnd) + (Ring -> backRingBuf) - 1;
	}
	
	bytesToEnd = 1 + Ring->backRingEnd  - readPtr; // in bytes!!!
	
	// now copy
	if ( totalBytesToWrite  <=  bytesToEnd)
	{
		// Can do 1 copy
		memcpy(outputBuffer, readPtr, totalBytesToWrite);
		//bytesWrittenSoFar = totalBytesToWrite;
	}
	else 
	{
		// two copies required
		long int bytesForSecondWrite;
		memcpy(outputBuffer, readPtr, bytesToEnd);
		bytesWrittenSoFar = bytesToEnd;
		bytesForSecondWrite	= totalBytesToWrite - bytesWrittenSoFar;
		memcpy(outputBuffer + bytesWrittenSoFar, Ring->backRingBuf,bytesForSecondWrite );
	}
	return 0;
	
}

int SatRingCreate (SatRing_t* Ring,  int framesInRing, int channelsPerFrame, int bytesPerChannel)
{
	// *** must be an even number.
	// The extra frames are split evenly in the front and back of the buffer
	if ( !(EXTRA_SAFETY_FRAMES % 2 == 0 && EXTRA_SAFETY_FRAMES >= 2)  )
	{
		assert(0);  // invalid number of safety frames  (must be even)
	}
	
	if ( Ring )
	{
		Ring -> framesInRing = (framesInRing + EXTRA_SAFETY_FRAMES);  /// ;)  don't let the reader know about the extra space
		Ring->framesInRing_User = framesInRing; // The user should only look at this
		Ring -> bytesPerRing =  Ring -> framesInRing * channelsPerFrame * bytesPerChannel;
		Ring -> backRingBuf = (uint8_t *) malloc ( Ring -> bytesPerRing  );
		
		if (   Ring -> backRingBuf == NULL )
		{
			assert(0);  // malloc fail
		}
		else 
		{
			// good case
			Ring->backRingEnd  = Ring->backRingBuf  + Ring -> bytesPerRing - 1;
			Ring->backRingWritePos  = Ring->backRingBuf;
			Ring->bytesPerFrame =  channelsPerFrame * bytesPerChannel;
			Ring->channelsPerFrame = channelsPerFrame;
			Ring->bytesPerChannel = bytesPerChannel;
			Ring->backRingState  = NOT_FULL;
			Ring->isInitialized = false;
		}
	}
	else
	{
		//ring passed in is null
		assert(0);
		return -1;
	}
	return 0;
}

int SatRingInit (SatRing_t * Ring)
{
	// TODO: Handle Ring being null;
	// TODO: Move flag Ring->isInitialized into this function
	// TODO: Add a flag Ring->isCreated in function SatRingCreate
	
	memset(Ring->backRingBuf, 0, Ring -> bytesPerRing);
	Ring->backRingFramesWritten =  0;
	Ring->isInitialized = true;
	return 0;
}

// TODO: clear the isInitialized flag and possible an is CreatedFlag
int SatRingDestroy (SatRing_t * Ring)
{
	if ( Ring )
	{
		if ( Ring -> backRingBuf )
		{
			free ( Ring -> backRingBuf );
		}
	}
	return 0;
}

// lets the Audio Callback write to the ring 
int SatRingWriteFrames (SatRing_t * Ring, uint8_t* frameSrc, int numFrames )
{
	if ( Ring -> isInitialized == false)
	{
		// ring not initialized
		assert(0);
	}
	writeRing(Ring, frameSrc, numFrames);
	return 0;
}

// lets the delay/src read the ring
// Assumes outputBuffer is big enough.  The caller should know because they created the ring and specified the ring size (excluding safety bytes) (ie framesInRing_User).
satRingState SatRingRead (SatRing_t * Ring, uint8_t* outputBuffer )
{
	if ( Ring -> isInitialized == false)
	{
		// ring not initialized
		assert(0);
	}
	//check if full
	if ( Ring -> backRingState == NOT_FULL)
	{
		// can't be read
	
		// may as well wipe out the buffer too.  It's not really punishment.  We just want to make sure we don't supply bad data to the delay algorithm.  memset could be removed for optimization.
		memset(outputBuffer, 0, (Ring->framesInRing_User * Ring->bytesPerFrame) );
		return NOT_FULL;
	}
	if ( Ring -> backRingState == READY_FOR_READING )
	{
		//LogToConsole("Read - READ_FOR_READING  executing the copy");
		// copy from ring to buffer
		readRing(Ring, outputBuffer);
		return READ_SUCCESS;
	}	
	
	assert(0);  // invalid state
	return INVALID_STATE;
}

