#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, OEResolution) {
    OEResolution480p = 0,
    OEResolution720p,
    OEResolution1080p
};

@interface OETranscodeSettings : NSObject

@property (nonatomic, assign) OEResolution resolution;
@property (nonatomic, assign) NSInteger maxVideoBitrate; // bps
@property (nonatomic, assign) BOOL directPlay; // if YES, no transcode
@property (nonatomic, assign) NSInteger maxAudioBitrate; // bps

+ (instancetype)sharedSettings;
+ (instancetype)defaultSettings; // forced 720p H264 4Mbps

- (void)load;
- (void)save;

- (NSString *)resolutionString; // @"480p" etc
- (NSInteger)widthForResolution;  // 720/1280/1920
- (NSInteger)heightForResolution; // 480/720/1080

- (void)applyResolutionString:(NSString *)s;

// For PlaybackInfo: whether to request direct play
- (BOOL)shouldTranscode;

@end
