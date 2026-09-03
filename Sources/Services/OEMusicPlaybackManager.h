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

typedef NS_ENUM(NSInteger, OEMusicRepeatMode) {
    OEMusicRepeatModeOff = 0, // play the playlist once, stop at the end
    OEMusicRepeatModeAll,     // wrap around to the first track
    OEMusicRepeatModeOne      // repeat the current track
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
@property (nonatomic, readonly) OEMusicRepeatMode repeatMode;

+ (instancetype)sharedManager;

- (void)playItem:(OEEmbyItem *)item playlist:(NSArray *)playlist;
- (void)togglePlayPause;
- (void)pause;
- (void)resume;
- (void)next;
- (void)previous;
// Cycles Off -> All -> One -> Off and persists the choice. Posts a state
// change notification so transport UIs can swap the repeat icon.
- (void)cycleRepeatMode;
// Jump directly to a playlist entry (used by the play queue UI).
- (void)playItemAtIndex:(NSInteger)index;
- (void)seekToProgress:(float)progress completion:(void(^)(BOOL finished))completion;
- (void)receiveRemoteControlEvent:(UIEvent *)event;

@end
