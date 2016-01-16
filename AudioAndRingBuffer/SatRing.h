/**
 * @author Jim Bilitski
 */



/**

 
 
 We implement a Ring buffer that is always full.  To accomplish this, the Ring always writes over the latest data.
 We have a Ring that is writing all the time.  Readers may come in can copy data out of it with their own supplied buffers.
 To avoid reader/writer conflict, we make the presumption that the writer always writes newest data overtop of the oldest data.
 Once the buffer is full, the read position moves along the ring with the write position.
 This write position becomes the critical section since the read and write positions are the same.
 When a read request occurs, it will not attempt to read this latest data.
 Instead it will chop a few frames from the front and back to avoid a read during a write.
 
 **/




#include <stdint.h>
#include <stdbool.h>

/// An enum specifying the state of a ring buffer
typedef enum 
{
	NOT_FULL,			///< Buffer is not full yet
	READY_FOR_READING,  ///< Buffer is full and read for reading
	READ_SUCCESS,		///< Buffer has been successfully read
	INVALID_STATE		///< Invalid state for error handling

} satRingState;


/// A data structure for a ring buffer. It is not a generic ring buffer.  Rather, it is designed specifically for storing audio data 
typedef struct SatRing_t
{
	int framesInRing_User;  ///< to the user's view, this is the number of frames in the ring.   It excludes the saftey bytes.
	uint8_t * backRingBuf;	///< A pointer to the front of the ring buffer.  It is called "back" ring to support future double buffering.
	
	uint8_t * backRingEnd;	///< A pointer to the end of the ring buffer.
	
	uint8_t * backRingWritePos; ///< A pointer to the write position.
	
	int bytesPerFrame;	///< number of bytes in a frame
	int bytesPerRing;   ///< total number of bytes in the entire ring buffer.
	int framesInRing; ///< Number of frames in the ring.  Bytes and frames can be implied but it makes it easier to store it once
	int channelsPerFrame;  ///< Number of channels per frame
	int bytesPerChannel; ///< Number of bytes (not bits) per channel
	
	int backRingFramesWritten; ///< Number of frames written so far
	
	satRingState backRingState;	  ///< The state of the ring as defined by satRingState
	
	bool isInitialized;	///< Initializtion flag
} SatRing_t;

/**
 @brief Creates a ring using dynamic memory.  It also sets initializes the fields in SatRing_t.
 */
int SatRingCreate (SatRing_t* Ring,  int framesInRing, int channelsPerFrame, int bytesPerChannel);

/**
 @brief Initializes a SatRing to all 0's.  The function assumes that the Ring has been created and initialized.
 @return 0 upon success
 */
int SatRingInit (SatRing_t * Ring);

/**
 @brief Deallocates a ring.
 @return 0 upon success
 */
int SatRingDestroy (SatRing_t * Ring);

/**
 @brief Lets the Audio Callback write to the Ring.
 @return 0 upon success
 */
int SatRingWriteFrames (SatRing_t * Ring, uint8_t* frameSrc, int numFrames );


/**
 @brief Lets the delay/src read the Ring.  It reads from the ring and writes it to outputBuffer.
 @return satRingState
 */
satRingState SatRingRead (SatRing_t * Ring, uint8_t* outputBuffer );


