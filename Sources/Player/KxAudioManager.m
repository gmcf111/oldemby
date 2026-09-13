//
//  KxAudioManager.m  (OldEmby fork)
//  kxmovie
//
//  Created by Kolyvan on 23.10.12.
//  Copyright (c) 2012 Konstantin Boukreev . All rights reserved.
//  https://github.com/kolyvan/kxmovie
//  this file is part of KxMovie, licensed under the LGPL v3, see lgpl-3.0.txt
//
//  OldEmby modifications: the deprecated C AudioSession API
//  (AudioSessionInitialize / AudioSessionGetProperty / kAudioSession*…) was
//  removed from the iOS SDK headers, so session configuration, hardware
//  sample-rate/channel queries and interruption/route observation now go
//  through AVAudioSession (available since iOS 3.0, KVO/notifications since
//  6.0 - our 6.0-9.x target). The RemoteIO AudioUnit render path and the
//  vDSP float/SInt16 conversion are kept unchanged.
//

#import "KxAudioManager.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#include <string.h>
#include <stdlib.h>
#import "KxLogger.h"

#define MAX_FRAME_SIZE 4096
#define MAX_CHAN       2

static BOOL checkError(OSStatus error, const char *operation);
static OSStatus renderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData);

@interface KxAudioManagerImpl : KxAudioManager<KxAudioManager> {
    BOOL                        _activated;
    float                       *_outData;
    AudioUnit                   _audioUnit;
    AudioStreamBasicDescription _outputFormat;
}

@property (readonly) UInt32             numOutputChannels;
@property (readonly) Float64            samplingRate;
@property (readonly) UInt32             numBytesPerSample;
@property (readwrite) Float32           outputVolume;
@property (readonly) BOOL               playing;
@property (readonly, strong) NSString   *audioRoute;

@property (readwrite, copy) KxAudioManagerOutputBlock outputBlock;
@property (readwrite) BOOL playAfterSessionEndInterruption;

- (BOOL) activateAudioSession;
- (void) deactivateAudioSession;
- (BOOL) play;
- (void) pause;

- (BOOL) checkAudioRoute;
- (BOOL) setupAudio;
- (BOOL) renderFrames:(UInt32)numFrames ioData:(AudioBufferList *)ioData;

@end

@implementation KxAudioManager

+ (id<KxAudioManager>) audioManager
{
    static KxAudioManagerImpl *audioManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        audioManager = [[KxAudioManagerImpl alloc] init];
    });
    return audioManager;
}

@end

@implementation KxAudioManagerImpl

- (id)init
{
    self = [super init];
    if (self) {
        _outData = (float *)calloc(MAX_FRAME_SIZE * MAX_CHAN, sizeof(float));
        _outputVolume = 1.0;
        _samplingRate = 44100.0;
        _numOutputChannels = 2;

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
        [center addObserver:self selector:@selector(handleRouteChange:) name:AVAudioSessionRouteChangeNotification object:[AVAudioSession sharedInstance]];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_outData) {
        free(_outData);
        _outData = NULL;
    }
}

#pragma mark - session observation

- (void)handleInterruption:(NSNotification *)note
{
    NSDictionary *info = note.userInfo;
    NSNumber *typeValue = info[AVAudioSessionInterruptionTypeKey];
    AVAudioSessionInterruptionType type = typeValue.unsignedIntegerValue;
    if (type == AVAudioSessionInterruptionTypeBegan) {
        LoggerAudio(2, @"Begin interruption");
        self.playAfterSessionEndInterruption = self.playing;
        [self pause];
    } else if (type == AVAudioSessionInterruptionTypeEnded) {
        LoggerAudio(2, @"End interruption");
        if (self.playAfterSessionEndInterruption) {
            self.playAfterSessionEndInterruption = NO;
            // Re-activate the session before restarting the output unit.
            NSError *err = nil;
            [[AVAudioSession sharedInstance] setActive:YES error:&err];
            [self play];
        }
    }
}

- (void)handleRouteChange:(NSNotification *)note
{
    [self checkAudioRoute];
}

- (BOOL) checkAudioRoute
{
    AVAudioSessionRouteDescription *route = [AVAudioSession sharedInstance].currentRoute;
    NSMutableString *desc = [NSMutableString string];
    for (AVAudioSessionPortDescription *out in route.outputs) {
        if (desc.length) [desc appendString:@","];
        [desc appendFormat:@"%@(%@)", out.portType ?: @"?", out.portName ?: @"?"];
    }
    _audioRoute = desc.length ? desc : @"unknown";
    LoggerAudio(1, @"AudioRoute: %@", _audioRoute);
    return YES;
}

#pragma mark - AudioUnit

- (BOOL) setupAudio
{
    // --- AVAudioSession configuration ---
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *err = nil;

    if (![session setCategory:AVAudioSessionCategoryPlayback error:&err]) {
        LoggerAudio(0, @"Couldn't set audio category: %@", err);
    }
    // Small IO buffer keeps latency down; failure is non-fatal (warning only).
    [session setPreferredIOBufferDuration:0.0232 error:&err];
    if (![session setActive:YES error:&err]) {
        LoggerAudio(0, @"Couldn't activate the audio session: %@", err);
        return NO;
    }

    // Hardware sample rate + channel count (the resampler targets this so no
    // extra SRC is needed on the common 44.1k/2ch route).
    Float64 hwRate = session.sampleRate;
    if (hwRate > 0) _samplingRate = hwRate;
    UInt32 hwCh = [self hardwareOutputChannelCount];
    if (hwCh > 0) _numOutputChannels = hwCh;
    _outputVolume = session.outputVolume;
    [self checkAudioRoute];

    LoggerAudio(1, @"session smr: %f vol: %f", _samplingRate, _outputVolume);

    // ----- Audio Unit (RemoteIO output) -----
    AudioComponentDescription description = {0};
    description.componentType = kAudioUnitType_Output;
    description.componentSubType = kAudioUnitSubType_RemoteIO;
    description.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent component = AudioComponentFindNext(NULL, &description);
    if (!component) {
        LoggerAudio(0, @"Couldn't find an output audio component");
        return NO;
    }
    if (checkError(AudioComponentInstanceNew(component, &_audioUnit),
                   "Couldn't create the output audio unit"))
        return NO;

    UInt32 size = sizeof(AudioStreamBasicDescription);
    if (checkError(AudioUnitGetProperty(_audioUnit,
                                        kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Input,
                                        0,
                                        &_outputFormat,
                                        &size),
                   "Couldn't get the hardware output stream format"))
        return NO;

    _outputFormat.mSampleRate = _samplingRate;
    if (checkError(AudioUnitSetProperty(_audioUnit,
                                        kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Input,
                                        0,
                                        &_outputFormat,
                                        size),
                   "Couldn't set the hardware output stream format")) {
        // just warning
    }

    _numBytesPerSample = _outputFormat.mBitsPerChannel / 8;
    _numOutputChannels = _outputFormat.mChannelsPerFrame;

    LoggerAudio(2, @"Current output bytes per sample: %u", _numBytesPerSample);
    LoggerAudio(2, @"Current output num channels: %u", _numOutputChannels);

    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = renderCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)(self);
    if (checkError(AudioUnitSetProperty(_audioUnit,
                                        kAudioUnitProperty_SetRenderCallback,
                                        kAudioUnitScope_Input,
                                        0,
                                        &callbackStruct,
                                        sizeof(callbackStruct)),
                   "Couldn't set the render callback on the audio unit"))
        return NO;

    if (checkError(AudioUnitInitialize(_audioUnit),
                   "Couldn't initialize the audio unit"))
        return NO;

    return YES;
}

// outputChannelCount is iOS 7+, numberOfChannels is iOS 3-6 (deprecated in 7).
// Probe both so the 6.0 deployment target keeps working.
- (UInt32) hardwareOutputChannelCount
{
    AVAudioSession *s = [AVAudioSession sharedInstance];
    NSNumber *count = nil;
    @try {
        if ([s respondsToSelector:@selector(outputChannelCount)])
            count = [s valueForKey:@"outputChannelCount"];
    } @catch (NSException *e) {
        count = nil;
    }
    if (!count) {
        @try {
            count = [s valueForKey:@"numberOfChannels"];
        } @catch (NSException *e) {
            count = nil;
        }
    }
    return count ? (UInt32)[count unsignedIntValue] : 2;
}

- (BOOL) renderFrames:(UInt32)numFrames ioData:(AudioBufferList *)ioData
{
    for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; ++iBuffer)
        memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);

    if (_playing && _outputBlock) {
        _outputBlock(_outData, numFrames, _numOutputChannels);

        if (_numBytesPerSample == 4) { // already floats
            float zero = 0.0;
            for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
                int thisNumChannels = ioData->mBuffers[iBuffer].mNumberChannels;
                for (int iChannel = 0; iChannel < thisNumChannels; ++iChannel)
                    vDSP_vsadd(_outData + iChannel, _numOutputChannels, &zero, (float *)ioData->mBuffers[iBuffer].mData, thisNumChannels, numFrames);
            }
        } else if (_numBytesPerSample == 2) { // SInt16 -> Float (with scale)
            float scale = (float)INT16_MAX;
            vDSP_vsmul(_outData, 1, &scale, _outData, 1, numFrames * _numOutputChannels);
            for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
                int thisNumChannels = ioData->mBuffers[iBuffer].mNumberChannels;
                for (int iChannel = 0; iChannel < thisNumChannels; ++iChannel)
                    vDSP_vfix16(_outData + iChannel, _numOutputChannels, (SInt16 *)ioData->mBuffers[iBuffer].mData + iChannel, thisNumChannels, numFrames);
            }
        }
    }
    return noErr;
}

#pragma mark - public

- (BOOL) activateAudioSession
{
    if (!_activated) {
        if ([self setupAudio])
            _activated = YES;
    }
    return _activated;
}

- (void) deactivateAudioSession
{
    if (_activated) {
        [self pause];
        checkError(AudioUnitUninitialize(_audioUnit), "Couldn't uninitialize the audio unit");
        checkError(AudioComponentInstanceDispose(_audioUnit), "Couldn't dispose the output audio unit");
        _audioUnit = NULL;
        NSError *err = nil;
        checkError((OSStatus)![[AVAudioSession sharedInstance] setActive:NO error:&err],
                   "Couldn't deactivate the audio session");
        _activated = NO;
    }
}

- (void) pause
{
    if (_playing) {
        _playing = !checkError(AudioOutputUnitStop(_audioUnit), "Couldn't stop the output unit");
    }
}

- (BOOL) play
{
    if (!_playing) {
        if ([self activateAudioSession]) {
            _playing = !checkError(AudioOutputUnitStart(_audioUnit), "Couldn't start the output unit");
        }
    }
    return _playing;
}

@end

#pragma mark - callbacks

static OSStatus renderCallback(void *inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inOutputBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData)
{
    KxAudioManagerImpl *sm = (__bridge KxAudioManagerImpl *)inRefCon;
    return (OSStatus)[sm renderFrames:inNumberFrames ioData:ioData];
}

static BOOL checkError(OSStatus error, const char *operation)
{
    if (error == noErr)
        return NO;

    char str[20] = {0};
    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else {
        sprintf(str, "%d", (int)error);
    }
    LoggerStream(0, @"Error: %s (%s)\n", operation, str);
    return YES;
}
