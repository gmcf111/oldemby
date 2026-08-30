#import "OETranscodeSettings.h"
#import "Constants.h"

@implementation OETranscodeSettings

+ (instancetype)sharedSettings {
    static OETranscodeSettings *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[OETranscodeSettings alloc] init]; [s load]; });
    return s;
}

+ (instancetype)defaultSettings {
    OETranscodeSettings *s = [[OETranscodeSettings alloc] init];
    s.resolution = OEResolution720p;
    s.maxVideoBitrate = kDefaultVideoBitrate;
    s.maxAudioBitrate = kDefaultAudioBitrate;
    s.directPlay = kDefaultDirectPlay;
    return s;
}

- (void)load {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *res = [d stringForKey:kDefaultsTranscodeResolution];
    if (res) [self applyResolutionString:res]; else self.resolution = OEResolution720p;
    NSNumber *br = [d objectForKey:kDefaultsTranscodeBitrate];
    self.maxVideoBitrate = br ? [br integerValue] : kDefaultVideoBitrate;
    NSNumber *abr = [d objectForKey:kDefaultsAudioBitrate];
    self.maxAudioBitrate = abr ? [abr integerValue] : kDefaultAudioBitrate;
    self.directPlay = [d boolForKey:kDefaultsTranscodeDirectPlay];
    // Validate bitrate presets if zero
    if (self.maxVideoBitrate < 500000) self.maxVideoBitrate = kDefaultVideoBitrate;
    if (self.maxAudioBitrate < 64000) self.maxAudioBitrate = kDefaultAudioBitrate;
}

- (void)save {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:[self resolutionString] forKey:kDefaultsTranscodeResolution];
    [d setObject:@(self.maxVideoBitrate) forKey:kDefaultsTranscodeBitrate];
    [d setObject:@(self.maxAudioBitrate) forKey:kDefaultsAudioBitrate];
    [d setBool:self.directPlay forKey:kDefaultsTranscodeDirectPlay];
    [d synchronize];
}

- (NSString *)resolutionString {
    switch (self.resolution) {
        case OEResolution480p: return @"480p";
        case OEResolution720p: return @"720p";
        case OEResolution1080p: return @"1080p";
    }
    return @"720p";
}

- (NSInteger)widthForResolution {
    switch (self.resolution) {
        case OEResolution480p: return 720;
        case OEResolution720p: return 1280;
        case OEResolution1080p: return 1920;
    }
    return 1280;
}

- (NSInteger)heightForResolution {
    switch (self.resolution) {
        case OEResolution480p: return 480;
        case OEResolution720p: return 720;
        case OEResolution1080p: return 1080;
    }
    return 720;
}

- (void)applyResolutionString:(NSString *)s {
    if ([s isEqualToString:@"480p"]) self.resolution = OEResolution480p;
    else if ([s isEqualToString:@"1080p"]) self.resolution = OEResolution1080p;
    else self.resolution = OEResolution720p;
}

- (BOOL)shouldTranscode { return !self.directPlay; }

@end
