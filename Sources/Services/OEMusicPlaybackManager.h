#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
@class OEEmbyItem;

typedef NS_ENUM(NSInteger, OEMusicPlaybackState) {
    OEMusicPlaybackStateIdle = 0,
    OEMusicPlaybackStateLoading,
    OEMusicPlaybackStateBuffering,
    OEMusicPlaybackStatePlaying,
    OEMusicPlaybackStatePaused,
    OEMusicPlaybackStateFailed
};

@interface OEMusicPlaybackManager : NSObject

@property (nonatomic, readonly) OEEmbyItem *currentItem;
@property (nonatomic, readonly) NSArray *playlist;
@property (nonatomic, readonly) NSInteger currentIndex;
@property (nonatomic, readonly) UIImage *artwork;
@property (nonatomic, readonly) OEMusicPlaybackState state;
@property (nonatomic, readonly) float progress;
@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) NSString *statusText;
// Copyable diagnostics for the most recent failure (stream URL, error domain
// and code, track identity). Nil unless state == OEMusicPlaybackStateFailed.
@property (nonatomic, readonly) NSString *lastErrorDetail;
@property (nonatomic, readonly, getter=isActive) BOOL active;
@property (nonatomic, readonly, getter=isPlaying) BOOL playing;

+ (instancetype)sharedManager;

- (void)playItem:(OEEmbyItem *)item playlist:(NSArray *)playlist;
- (void)togglePlayPause;
- (void)pause;
- (void)resume;
- (void)next;
- (void)previous;
- (void)seekToProgress:(float)progress completion:(void(^)(BOOL finished))completion;
- (void)receiveRemoteControlEvent:(UIEvent *)event;

@end
