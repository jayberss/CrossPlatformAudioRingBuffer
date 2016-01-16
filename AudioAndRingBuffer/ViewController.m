//
//  ViewController.m
//  AudioAndRingBuffer
//
//  Created by James Bilitski on 11/16/14.
//  Copyright © 2014 com.jaybers. All rights reserved.
//

#import "ViewController.h"
#import "AudioDevice.h"

#import "SatRing.h"
#define NUMBER_OF_SECONDS_TO_RECORD 2
@interface ViewController ()
{
	AudioDevice* _audioDevice;
	NSTimer* timer;
}
@end

extern SatRing_t recordingRing;
uint8_t *copyOfLastNSecondsOfRecordingBuffer;
int numberOfRecordingFrames;
@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
	
	
	
	//  Help determine size of ring.
	// How many frames do I need?

	numberOfRecordingFrames  =  kAudioRecorderRate * NUMBER_OF_SECONDS_TO_RECORD;  // recording sample rate in Hz * number of seconds
	int numberOfChannels = kAudioRecorderChannels;
	int numberOfBytesPerChannel = 2;
	
	
	// ensure ring buffer is created and initialized before starting audio
	SatRingCreate(&recordingRing, numberOfRecordingFrames, numberOfChannels, numberOfBytesPerChannel);
	NSLog(@"Mic ring created.");
	SatRingInit(&recordingRing);
	NSLog(@"Mic ring initalized.");

	copyOfLastNSecondsOfRecordingBuffer = malloc(numberOfRecordingFrames * numberOfChannels * numberOfBytesPerChannel);
	
	
	_audioDevice = [[AudioDevice alloc]init];
	[_audioDevice initAVAudioSession];
	[_audioDevice initAudioUnit];
	[_audioDevice startAudioUnit];
	[_audioDevice playTone:440.0f];
	
	
	
	// every so often, go read data from the ring
	timer = [NSTimer scheduledTimerWithTimeInterval:7
														   target:self
														 selector:@selector(timerFired:)
														 userInfo:nil
														  repeats:YES];
	
	
	
}


- (void) timerFired:(NSTimer *)theTimer
{
	NSLog(@"Reading last %i seconds from ring",NUMBER_OF_SECONDS_TO_RECORD);
	
	
	SatRingRead(&recordingRing, copyOfLastNSecondsOfRecordingBuffer);
	int16_t* ptrToAFrame;  // process in 2 byte frames for 16 bit samples.
	ptrToAFrame = (int16_t*)copyOfLastNSecondsOfRecordingBuffer;
	
	// dump some of data to log
	for (int i = 0;  i < numberOfRecordingFrames; ++i)
	{
			// reading in frames,   not bytes
		NSLog(@"Recording sample |%i|",*( ptrToAFrame + i ) );
		
	}
	
	
}
- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}

@end
