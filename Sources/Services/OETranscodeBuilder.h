#import <Foundation/Foundation.h>
#import "Models/OETranscodeSettings.h"

// Builds Emby PlaybackInfo request body + DeviceProfile for transcoding
@interface OETranscodeBuilder : NSObject

// DeviceProfile dictionary for PlaybackInfo (compatible with Emby 3.x-4.x)
+ (NSDictionary *)deviceProfileForSettings:(OETranscodeSettings *)settings isAudio:(BOOL)isAudio;

// Full PlaybackInfo JSON body
+ (NSDictionary *)playbackInfoBodyForItemId:(NSString *)itemId
                                  userId:(NSString *)userId
                                settings:(OETranscodeSettings *)settings
                                 isAudio:(BOOL)isAudio;

// Query string helpers for direct stream URL (fallback)
+ (NSString *)transcodeQueryStringForSettings:(OETranscodeSettings *)settings isAudio:(BOOL)isAudio;

// Parse PlaybackInfo response to get MediaSource -> stream URL
+ (NSString *)streamURLFromPlaybackInfoResponse:(NSDictionary *)response
                                         host:(NSString *)host
                                   mediaSourceId:(NSString **)outMediaSourceId;

@end
