//  AudioDevice.m




#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>  // for alertview to allow microphone access
#import "AudioDevice.h"
#import "SatRing.h"


#ifdef IOS_DEVICE
#define kAudioSessionMinBufferFrames	256
#else
#define kAudioSessionMinBufferFrames	256
#endif

#define kAudioSessionMinBufferDurationThreshold (0.0005+AppSettingsGetAudioSessionMinBufferDuration())






#define kAudioRecorderBitsPerChannel 16  ///< Number of bits per channel in the microphone recording
#define kAudioRecorderBytesPerFrame (kAudioRecorderChannels * (kAudioRecorderBitsPerChannel / 8)) ///< Number of bytes per frame in the microphone recording
#define kAudioRecorderLength 4 ///< Number of seconds of audio to record from the microphone to calculate the delay.

//#define kAudioMicRecordingFrames ((int)AppSettingsGetRecordSampleRate() * kAudioRecorderLength) ///< Number of frames needed to store the mic recording for kAudioRecorderLength seconds



#define AUDIO_SAMPLE_TYPE short ///< Currently 16 bits on iOS/Android devices


#pragma mark - Defines
// psuedo sim sinewave

// apple RemoteIO bus definitions
#define kRemoteIOInputScopeApp 0
#define kRemoteIOInputScopeMic 1
#define kRemoteIOOutputScopeSpeaker 0
#define kRemoteIOOutputScopeApp 1


// stores setting for playback and recording on remote io unit
static AudioComponentDescription remoteIODescription;

// stores playback format
static AudioStreamBasicDescription stereoInputDescription;

// stores mic recording format
static AudioStreamBasicDescription micRecordDescription;



static bool isInitialized = false;

static BOOL _audioUnitIsStarted = NO;
static 	Float64						_graphSampleRate;



/*  ******  The Ring  ****** */
SatRing_t recordingRing;



#pragma mark - Private c prototypes
// inline wrapper to check status of systems calls that return OSStatus such as ie AudioUnitSetProperty()
inline bool _checkStatus(OSStatus status, const char * operation, const char * file, int line, int errAction);


void updateInputDeviceStatus(AudioDevice *device);


// single function to handle all property listeners such as volume change, headphone insert change
void propertyListener(void * inClientData, AudioSessionPropertyID inID, UInt32 inDataSize, const void * inData);



void interruptionListener(void * inClientData, UInt32 inInterruptionState);
/*
 // c-style callback for transmitter playback
 OSStatus renderCallback(void * inRefCon,
 AudioUnitRenderActionFlags * ioActionFlags,
 const AudioTimeStamp * inTimeStamp,
 UInt32 inBusNumber,
 UInt32 inNumberFrames,
 AudioBufferList* ioData);
 */

// c-style callback for simulated audio playback.  This plays a panning sin wave.
// Change #define SIM_AUDIO 1 to register this function as the audio player callback
OSStatus renderCallbackTone(void *inRefCon,
                            AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp,
                            UInt32 inBusNumber,
                            UInt32 inNumberFrames,
                            AudioBufferList *ioData);


// c-style callback for mic recording
OSStatus recordCallback(void *inRefCon,
						AudioUnitRenderActionFlags *ioActionFlags,
						const AudioTimeStamp *inTimeStamp,
						UInt32 inBusNumber,
						UInt32 inNumberFrames,
						AudioBufferList *ioData);







#pragma mark - Interface
@interface AudioDevice ()
{
	AudioUnit ioUnit;  // The audio unit that is configured to be a remoteIO unit
	NSInteger _inputADChannels;
}

@end


@implementation AudioDevice;





#pragma mark - Audio Session Lifecycle

// Initializes audio session
-(void)interruptionListener:(NSNotification*) aNotification
{
	NSLog(@"Interruption happened");
	NSDictionary *interruptionDict = aNotification.userInfo;
	NSNumber* interruptionTypeValue = [interruptionDict valueForKey:AVAudioSessionInterruptionTypeKey];
    NSUInteger interruptionType = [interruptionTypeValue intValue];
	if ( interruptionType == AVAudioSessionInterruptionTypeBegan)
	{
		//NSLog(@"Interruption AVAudioSessionInterruptionTypeBegan");

		[self stopAudioSession];
	}
	else if ( interruptionType == AVAudioSessionInterruptionTypeEnded )
	{

		//NSLog(@"Interruption AVAudioSessionInterruptionTypeEnded");
		if ( isInitialized == true )
		{
			//NSLog(@"Interruption AVAudioSessionInterruptionTypeEnded - isInitialized = true");
			return;
		}
		else
		{
		//	NSLog(@"Interruption AVAudioSessionInterruptionTypeEnded - isInitialized = false,   let it startup...");
			
		}
		[self initAVAudioSession];
		[self releaseAudioUnit];
		[self initAudioUnit];
		[self startAudioUnit];
	}
	else if ( interruptionType == AVAudioSessionInterruptionOptionShouldResume )
	{

	//	NSLog(@"Interruption AVAudioSessionInterruptionOptionShouldResume");
		[self initAVAudioSession];
	}
	else
	{
			//	NSLog(@"Interruption something else");
	}
    
}

// -sets it for play and record mode
// -registers the property listener callbacks

-(void) checkMicrophonePermission
{
	
	if ([[AVAudioSession sharedInstance] respondsToSelector:@selector(requestRecordPermission:)]) {
		[[AVAudioSession sharedInstance] performSelector:@selector(requestRecordPermission:) withObject:^(BOOL granted) {
			if (granted) {
				// Microphone enabled code
            }
			else {
				// Microphone disabled code
				
				
				// We're in a background thread here, so jump to main thread to do UI work.
				dispatch_async(dispatch_get_main_queue(), ^{
					// TODO: UIAlertView is deprecated
					[[[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Please Allow Microphone Access", nil)]
												message:[NSString stringWithFormat:NSLocalizedString(@"To use VITALtuner, you need to go to your device's Privacy settings and give access to your microphone.\n\n Settings > Privacy > Microphone", nil)]
											   delegate:nil
									  cancelButtonTitle:[NSString stringWithFormat:NSLocalizedString(@"OK", nil)]
									  otherButtonTitles:nil]  show];
				});
			}
		}];
	}
}

- (BOOL) initAVAudioSession
{
	if ( isInitialized == true)
	{
		assert(0);
		return NO;
	}
	
	//UInt32 size;
	
	[AVAudioSession sharedInstance]; //init
	[self checkMicrophonePermission];
    
    

	NSError* error;
	BOOL activated = [[AVAudioSession sharedInstance] setActive:YES error:&error];
	
	if ( !activated)
	{
		NSAssert(0,@"Cannot activate AVAudioSession");
	}
	
#ifdef DEBUG_AUDIO_HW
	NSLog(@"AVAudioSession activated %i",activated);
#endif
	
    
	NSError* err1;
	[[AVAudioSession sharedInstance]setPreferredInputNumberOfChannels:2 error:&err1];
	_inputADChannels = [[AVAudioSession sharedInstance] inputNumberOfChannels];
	
#ifdef DEBUG_AUDIO_HW
	NSLog(@"A/D inputchannels %li",(long)_inputADChannels);
#endif
    
	// todo  change accordingly if no output
	NSError* setCatErr;

	[[AVAudioSession sharedInstance]setCategory:@"AVAudioSessionCategoryPlayAndRecord" error:&setCatErr];
	if ( setCatErr)
	{
		NSLog(@"Unable to AVAudioSessionCategory %@",setCatErr);
		NSAssert(setCatErr, @"Unable to AVAudioSessionCategory");
	}
    
	//AVAudioSessionCategoryPlayAndRecord
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(onAudioSessionRouteChange:) name:AVAudioSessionRouteChangeNotification object:nil];
	
	
	
	_graphSampleRate = [[AVAudioSession sharedInstance]sampleRate];
    
	NSTimeInterval _preferredDuration = (1024)/ _graphSampleRate ;
	NSError* err;
	[[AVAudioSession sharedInstance]setPreferredIOBufferDuration:_preferredDuration error:&err];
	if ( err)
	{
		NSLog(@"Unable to set bufferDuration %@",setCatErr);
		NSAssert(err, @"Unable to set bufferDuration");
	}
	

	
	
	// play through speaker instead of earpiece
	//set the audioSession override
	BOOL success;
    success = [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker
                                                                 error:&err];
    

//	NSLog(@"Is gain settable now: %i",[self gainIsSettable]);
		
	AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *errorInAudio   = nil;
    [session setActive:YES error:&errorInAudio];
	
//	NSLog(@"Is gain settable after active now: %i",[self gainIsSettable]);
	
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interruptionListener:) name:AVAudioSessionInterruptionNotification object:nil];
    
	
	isInitialized = true;
    
	return YES;
}





- (void) stopAudioSession
{
	NSLog(@"stopAudioSession");
    
	AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *errorInAudio   = nil;
	[session setActive:NO error:&errorInAudio];
	isInitialized = false;
	
}





#pragma mark - Audio Unit Lifecycle


// Sets the audio unit to be a remoteIO
// Sets the format of the recording and playback
// Sets the recording and playback callbacks

- (BOOL) initAudioUnit
{
	_isPlayingTone = NO;
	_toneFrequency = 440;

    
	UInt32 enableOutput = 1;  // 1 enable  0 disable
	UInt32 enableInput = 1;  // 1 enable  0 disable
	
	memset(&stereoInputDescription, 0, sizeof(stereoInputDescription));
	memset(&micRecordDescription, 0, sizeof(micRecordDescription));
	
	// set stereo description
	stereoInputDescription.mFormatID = kAudioFormatLinearPCM;
	stereoInputDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger;
	stereoInputDescription.mSampleRate = kAudioRecorderRate;
	stereoInputDescription.mChannelsPerFrame = kAudioPlayerChannels; // Stereo
	stereoInputDescription.mFramesPerPacket = 1;
	stereoInputDescription.mBitsPerChannel = kAudioPlayerBitsPerChannel;
	stereoInputDescription.mBytesPerPacket = stereoInputDescription.mBytesPerFrame = kAudioPlayerBytesPerFrame;  // 16 bits per channel * 2 channel
	
	// set io description
	remoteIODescription.componentType = kAudioUnitType_Output;
	remoteIODescription.componentSubType = kAudioUnitSubType_RemoteIO;
	remoteIODescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	remoteIODescription.componentFlags = 0,
	remoteIODescription.componentFlagsMask = 0;
	
	// set microphone
	micRecordDescription.mFormatID = kAudioFormatLinearPCM;
	micRecordDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger;
	micRecordDescription.mSampleRate = kAudioRecorderRate;
	micRecordDescription.mChannelsPerFrame = kAudioRecorderChannels; // mono
	micRecordDescription.mFramesPerPacket = 1;
	micRecordDescription.mBitsPerChannel = kAudioRecorderBitsPerChannel;
	micRecordDescription.mBytesPerPacket = micRecordDescription.mBytesPerFrame = kAudioRecorderBytesPerFrame; // 16 bits per channel * 1 channel
	
	
	AudioComponent audioComponent = AudioComponentFindNext(NULL, &remoteIODescription);
	
	if ( !checkStatus(AudioComponentInstanceNew(audioComponent, &ioUnit), "AudioComponentInstanceNew",-1))
	{
		assert(0);
		return NO;
	}
	
	
	
	if (!checkStatus(AudioUnitSetProperty(ioUnit,
										  kAudioOutputUnitProperty_EnableIO,
										  kAudioUnitScope_Input,
										  kRemoteIOInputScopeMic,
										  &enableInput,sizeof(enableInput)),
					 "AudioUnitSetProperty ioUnit Enable IO",-1))
	{
		return NO;
	}
	
    if (!checkStatus(AudioUnitSetProperty(ioUnit,
										  kAudioUnitProperty_StreamFormat,
										  kAudioUnitScope_Output,
										  kRemoteIOOutputScopeApp,
										  &micRecordDescription,
										  sizeof(micRecordDescription)),
					 
					 "AudioUnitSetProperty set Stream Format",-1))
	{
		return NO;
	}
	
	
	/// set mic recording stuff
	
    AURenderCallbackStruct inRenderProc;
    inRenderProc.inputProc = &recordCallback;
    inRenderProc.inputProcRefCon =(__bridge void*) self;
    if (!checkStatus (AudioUnitSetProperty(ioUnit,
										   kAudioOutputUnitProperty_SetInputCallback,
										   kAudioUnitScope_Global,
										   kRemoteIOInputScopeMic,
										   &inRenderProc,
										   sizeof(inRenderProc)),
					  "AudioUnitSetProperty set InputCallback",-1))
	{
		return NO;
	}
	
	// playback - enable output
	if (!checkStatus(AudioUnitSetProperty(ioUnit,
										  kAudioOutputUnitProperty_EnableIO,
										  kAudioUnitScope_Output,
										  kRemoteIOOutputScopeSpeaker,
										  &enableOutput,
										  sizeof(enableOutput)),
					 "AudioUnitSetProperty EnableIO",-1))
	{
		return NO;
	}
	
	
	
	/// set playback stuff

    AURenderCallbackStruct outRenderProc;
	outRenderProc.inputProc = renderCallbackTone;

    outRenderProc.inputProcRefCon = (__bridge void*)self;
    if (!checkStatus (AudioUnitSetProperty(ioUnit,
										   kAudioUnitProperty_SetRenderCallback,
										   kAudioUnitScope_Global,
										   kRemoteIOInputScopeApp,
										   &outRenderProc,
										   sizeof(outRenderProc)),
					  "AudioUnitSetProperty Set RenderCallback",-1))
	{
		return NO;
	}
	
	
	// playback - set stream feed format
    if (!checkStatus(AudioUnitSetProperty(ioUnit,
										  kAudioUnitProperty_StreamFormat,
										  kAudioUnitScope_Input,
										  kRemoteIOInputScopeApp,
										  &stereoInputDescription,
										  sizeof(stereoInputDescription)),
					 "AudioUnitSetProperty Set Stream Format",-1))
	{
		return NO;
		
	}
	
	// initializes both playback and recording
	if (!checkStatus(AudioUnitInitialize(ioUnit), "AudioUnitInitialize",-1))
	{
		assert(0);
		return NO;
	}
	
	
	return YES;
}

- (BOOL) startAudioUnit
{
	
	// cannot assume returning yes here.  in case we get interrupted and audio needs restarted
	/*
     if ( _audioUnitIsStarted == YES)
     {
     return YES;
     }
     */
	// starts both playback and recording
	if (!checkStatus(AudioOutputUnitStart(ioUnit), "AudioOutputUnitStart",-1))
	{
		assert(0);
		return NO;
	}
	
	_audioUnitIsStarted = YES;
	return YES;
}


- (BOOL) audioUnitIsStarted
{
	return _audioUnitIsStarted;
}

- (void) stopAudioUnit
{
    
	if ( _audioUnitIsStarted == NO)
	{
		// already stopped
		return;
	}
	if (!checkStatus(AudioOutputUnitStop(ioUnit), "AudioOutputUnitStop",-1))
	{
		assert(0);
		return;
	}
	_audioUnitIsStarted = NO;

}


- (BOOL) releaseAudioUnit
{

	OSStatus status = AudioComponentInstanceDispose(ioUnit);
	return status;
}





#pragma mark - Audio Unit Listeners

// example sine-ish wave
OSStatus renderCallbackTone(void *inRefCon,
                            AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp,
                            UInt32 inBusNumber,
                            UInt32 inNumberFrames,
                            AudioBufferList *ioData)
{
    
	AudioDevice * device = (__bridge AudioDevice *)inRefCon;
	// Assumes stereo interleaved, 16-bit
    SInt16 *audioPtr = (SInt16*)ioData->mBuffers[0].mData;
    SInt16 *audioPtrEnd = audioPtr + (inNumberFrames * 2);
    
	
	
	
	if ( ! device -> _isPlayingTone )
	{
		//		memset(audioPtr,0,inNumberFrames*1);
		while ( audioPtr < audioPtrEnd )
		{
			*(audioPtr++) = 0;
			*(audioPtr++) = 0;
			
		}
		return noErr;
	}
	


	static double theta = 0.0;
	
	double theta_increment = 2.0 * M_PI * device -> _toneFrequency / kAudioRecorderRate; // 440.0 hz


	//sine wave

		double amplitude = 30000;
		while ( audioPtr < audioPtrEnd )
		{
			
			*(audioPtr++) = sin(theta) * amplitude;
			*(audioPtr++) = sin(theta) * amplitude;
			//NSLog(@"samp val  %f",sin(theta) * amplitude);
			theta += theta_increment;
			if (theta > 2.0 * M_PI)
			{
				theta -= 2.0 * M_PI;
			}
		}
	
	
	return noErr;
}


// Callback for mic input.



OSStatus recordCallback(void *inRefCon,
						AudioUnitRenderActionFlags *ioActionFlags,
						const AudioTimeStamp *inTimeStamp,
						UInt32 inBusNumber,
						UInt32 inNumberFrames,
						AudioBufferList *ioData)
{

	
	AudioDevice *device = (__bridge AudioDevice *)inRefCon;
	struct
	{
		AudioBufferList bufferList;
		AudioBuffer nextBuffer;
	} __attribute((packed)) buffers;
	
	buffers.bufferList.mNumberBuffers =
    stereoInputDescription.mFormatFlags & kAudioFormatFlagIsNonInterleaved ?
    stereoInputDescription.mChannelsPerFrame : 1;
	
	// later deal with lots of channesl
    for ( int i = 0; i < buffers.bufferList.mNumberBuffers; i++ )
	{
        buffers.bufferList.mBuffers[i].mNumberChannels =
		stereoInputDescription.mFormatFlags & kAudioFormatFlagIsNonInterleaved ? 1 : stereoInputDescription.mChannelsPerFrame;
        buffers.bufferList.mBuffers[i].mData = NULL;
        buffers.bufferList.mBuffers[i].mDataByteSize = inNumberFrames * stereoInputDescription.mBytesPerFrame;
    }
	
	OSStatus err = AudioUnitRender(device->ioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, &buffers.bufferList);
	if (! err)
	{
			// all good, write to the wring buffer of first channel

		SatRingWriteFrames(&recordingRing,
						   buffers.bufferList.mBuffers[0].mData,
						   buffers.bufferList.mBuffers[0].mDataByteSize);
	}
	else
	{   NSLog(@"recordCallback AudioUnitRender error" );
		assert(0);
	}
	return 0;
}

void updateInputDeviceStatus(AudioDevice *device)
{
	
	return;
}





#pragma mark - Utility methods
// inline wrapper to check status of systems calls that return OSStatus such as ie AudioUnitSetProperty()
inline bool _checkStatus(OSStatus status, const char * operation, const char * file, int line, int errAction)
{
	
	if(status != 0)
	{
		
		NSError * error = [NSError errorWithDomain:NSOSStatusErrorDomain
											  code:status
										  userInfo:nil];
		
		NSLog(@"%s:%d: %s: %@ \n", file, line, operation, error);  /// This error important enough to force it to log to nslog
		
		switch (errAction) {
			case -1:
				assert(0);
				break;
			default:
				// todo: other cases
				assert(0);
				break;
		}
        return false;
    }
    return true;
}




#pragma mark audio tone interface
-(void) playTone: (float) frequency
{
	_isPlayingTone = YES;
	_toneFrequency = frequency;
}
-(void) stopTone
{
	_isPlayingTone = NO;
}


#pragma mark notifications
-(void) onAudioSessionRouteChange: (id)notif
{
	AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription* desc in [route outputs])
	{
		
		if ( [[desc portType]isEqualToString:AVAudioSessionPortBuiltInReceiver] )
		{
			// receiver speaker detected, reroute to bottom speaker
			BOOL success;
			NSError* err;
			success = [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker
																		 error:&err];
			
			if (!success)
			{
				NSLog(@"onAudioSessionRouteChange  AVAudioSession error overrideOutputAudioPort");
				//		NSAssert( @"AVAudioSession error overrideOutputAudioPort" );
			}
			
		}
    }
	
	
	
    
	
	
}
@end

#pragma mark - Property Listeners
// Single function for all audio property listeners
// Handles volume change and headphone insert change.   Could handle others in future.




