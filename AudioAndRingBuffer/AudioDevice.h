/**
 @file
//  AudioDevice.h

//
//  Created by Jim Bilitski

//
// Audio driver for iOS.
// Sets up:
//	Audio session lifecycle, callbacks for volume change and headphone insert change 
//  Remote io audio unit lifecycle, sets format and callbacks for playback and recording
*/


#import <AudioToolbox/AudioToolbox.h>

#define kAudioRecorderRate 44100.0   ///< The sample rate of the microphone recorder.
#define kAudioRecorderChannels 1	 ///< The number of channels in the microphone recording.

#define kAudioPlayerBitsPerChannel 16 ///< Number of bits per channel.  Left is a channel.  Right is a channel.

///< The sample rate of the audio player on the receiving device.
#define kAudioPlayerChannels 2		  ///< Number of channels in the network stream.  (2 means stereo)
#define kAudioPlayerBytesPerFrame (kAudioPlayerChannels * (kAudioPlayerBitsPerChannel / 8))  ///< Number of bytes in a frame.  A frame is a L/R pair.
#define kAudioStreamRecorderLength 4   ///< Number of seconds of audio to record from the stream to calculate the delay.
//#define kAudioStreamRecordingFrames ((int)AppSettingsGetRecordSampleRate() * kAudioStreamRecorderLength) ///< Number of frames needed to store the stream recording for kAudioStreamRecorderLength seconds



@interface AudioDevice : NSObject
{
	@public
	BOOL _isPlayingTone;
	float _toneFrequency;
}




- (BOOL) initAVAudioSession;
- (BOOL) initAudioUnit;
- (BOOL) startAudioUnit;
- (void) stopAudioUnit;
- (BOOL) audioUnitIsStarted;
- (void) stopAudioSession;
-(void) playTone: (float) frequency;
-(void) stopTone;




@end

#define checkStatus(result, operation, errAction) (_checkStatus((result), (operation), strrchr(__FILE__, '/'), __LINE__, errAction))

extern inline bool _checkStatus(OSStatus status, const char * operation, const char * file, int line, int errAction);
