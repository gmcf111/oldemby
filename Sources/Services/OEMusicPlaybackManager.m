#import "OEMusicPlaybackManager.h"
#import "Models/OEEmbyItem.h"
#import "Services/OEEmbyAPIClient.h"
#import "Services/OEImageCache.h"
#import "Constants.h"
#import <MediaPlayer/MediaPlayer.h>
#import <math.h>

@interface OEMusicPlaybackManager ()
@property (nonatomic, strong) OEEmbyItem *currentItem;
@property (nonatomic, strong) NSArray *playlist;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, strong) UIImage *artwork;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, assign) OEMusicPlaybackState state;
@property (nonatomic, assign) float progress;
@property (nonatomic, assign) NSTimeInterval currentTime;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) BOOL seeking;
@end

@implementation OEMusicPlaybackManager

+ (instancetype)sharedManager {
    static OEMusicPlaybackManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [[OEMusicPlaybackManager alloc] init]; });
    return manager;
}

- (instancetype)init {
    if ((self = [super init])) {
        _state = OEMusicPlaybackStateIdle;
        _statusText = @"未播放";
        _currentIndex = NSNotFound;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    }
    return self;
}

- (BOOL)isActive { return self.currentItem != nil; }
- (BOOL)isPlaying { return self.state == OEMusicPlaybackStatePlaying || self.state == OEMusicPlaybackStateBuffering; }

- (void)publishState {
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationMusicPlaybackStateChanged object:self];
}

- (void)publishProgress {
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationMusicPlaybackProgressChanged object:self];
}

- (void)playItem:(OEEmbyItem *)item playlist:(NSArray *)playlist {
    if (!item) return;
    self.playlist = playlist.count ? [playlist copy] : @[item];
    NSInteger index = [self.playlist indexOfObject:item];
    self.currentIndex = index == NSNotFound ? 0 : index;
    [self loadCurrentItem];
}

- (void)loadCurrentItem {
    if (self.currentIndex < 0 || self.currentIndex >= (NSInteger)self.playlist.count) return;
    NSUInteger generation = ++self.generation;
    [self cleanupPlayer];
    self.currentItem = self.playlist[self.currentIndex];
    self.artwork = nil;
    self.progress = 0;
    self.currentTime = 0;
    // Seed the duration from the item metadata: a transcoded HTTP stream
    // usually reports an indefinite AVPlayerItem duration, and without this
    // fallback the progress slider can never move or be dragged.
    self.duration = self.currentItem.runTimeTicks > 0 ? (NSTimeInterval)self.currentItem.runTimeTicks / 10000000.0 : 0;
    self.state = OEMusicPlaybackStateLoading;
    self.statusText = @"正在获取播放地址…";
    [self publishState];

    OEEmbyItem *item = self.currentItem;
    NSString *imageURL = [[OEEmbyAPIClient sharedClient] imageURLForItem:item width:240];
    [[OEImageCache sharedCache] loadImageFromURL:imageURL placeholder:nil completion:^(UIImage *image) {
        if (generation != self.generation || item != self.currentItem) return;
        self.artwork = image;
        [self updateNowPlayingInfo];
        [self publishState];
    }];

    [[OEEmbyAPIClient sharedClient] fetchStreamURLForItem:item.itemId isAudio:YES completion:^(id result, NSError *error) {
        if (generation != self.generation || item != self.currentItem) return;
        if (error) {
            self.state = OEMusicPlaybackStateFailed;
            self.statusText = [NSString stringWithFormat:@"播放失败：%@", error.localizedDescription ?: @"未知错误"];
            [self updateNowPlayingInfo];
            [self publishState];
            return;
        }
        NSURL *url = [result isKindOfClass:[NSString class]] ? [NSURL URLWithString:result] : nil;
        if (!url) {
            self.state = OEMusicPlaybackStateFailed;
            self.statusText = @"服务器返回了无效的播放地址";
            [self publishState];
            return;
        }
        [self beginPlayingURL:url generation:generation];
    }];
}

- (void)beginPlayingURL:(NSURL *)url generation:(NSUInteger)generation {
    if (generation != self.generation) return;
    self.playerItem = [AVPlayerItem playerItemWithURL:url];
    [self.playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
    [self.playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:NULL];
    [self.playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:NULL];
    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinish:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.playerItem];

    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 2) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        [weakSelf updateProgress];
    }];
    self.state = OEMusicPlaybackStateBuffering;
    self.statusText = @"正在缓冲…";
    [self.player play];
    [self updateNowPlayingInfo];
    [self publishState];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object != self.playerItem) return;
    void (^applyState)(void) = ^{
        if ([keyPath isEqualToString:@"status"]) {
            if (self.playerItem.status == AVPlayerItemStatusReadyToPlay) {
                self.state = OEMusicPlaybackStatePlaying;
                self.statusText = @"正在播放";
                [self.player play];
            } else if (self.playerItem.status == AVPlayerItemStatusFailed) {
                self.state = OEMusicPlaybackStateFailed;
                self.statusText = [NSString stringWithFormat:@"播放失败：%@", self.playerItem.error.localizedDescription ?: @"媒体不可播放"];
            }
            [self updateNowPlayingInfo];
            [self publishState];
        } else if ([keyPath isEqualToString:@"playbackBufferEmpty"] && self.playerItem.playbackBufferEmpty) {
            self.state = OEMusicPlaybackStateBuffering;
            self.statusText = @"正在缓冲…";
            [self publishState];
        } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"] && self.playerItem.playbackLikelyToKeepUp && self.player.rate > 0) {
            self.state = OEMusicPlaybackStatePlaying;
            self.statusText = @"正在播放";
            [self publishState];
        }
    };
    if ([NSThread isMainThread]) applyState();
    else dispatch_async(dispatch_get_main_queue(), applyState);
}

- (void)updateProgress {
    if (!self.player || self.seeking) return;
    CMTime current = self.player.currentTime;
    CMTime total = self.player.currentItem.duration;
    NSTimeInterval duration = CMTIME_IS_INVALID(total) ? 0 : CMTimeGetSeconds(total);
    // Transcoded streams often carry an indefinite duration; keep the
    // RunTimeTicks-derived value seeded in loadCurrentItem in that case.
    if (!isfinite(duration) || duration <= 0) duration = self.duration;
    NSTimeInterval currentTime = CMTimeGetSeconds(current);
    if (duration <= 0 || !isfinite(currentTime)) return;
    self.duration = duration;
    self.currentTime = MAX(0, currentTime);
    self.progress = MIN(1.0, MAX(0.0, self.currentTime / duration));
    [self updateNowPlayingInfo];
    [self publishProgress];
}

- (void)updateNowPlayingInfo {
    if (!self.currentItem) {
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
        return;
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = self.currentItem.name ?: @"";
    info[MPMediaItemPropertyArtist] = self.currentItem.artist ?: @"";
    info[MPMediaItemPropertyAlbumTitle] = self.currentItem.album ?: @"";
    if (self.artwork) info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithImage:self.artwork];
    if (self.duration > 0) {
        info[MPMediaItemPropertyPlaybackDuration] = @(self.duration);
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.currentTime);
        info[MPNowPlayingInfoPropertyPlaybackRate] = @(self.isPlaying ? 1.0 : 0.0);
    }
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:info];
}

- (void)togglePlayPause { self.isPlaying ? [self pause] : [self resume]; }

- (void)pause {
    if (!self.player || self.state == OEMusicPlaybackStateFailed) return;
    [self.player pause];
    self.state = OEMusicPlaybackStatePaused;
    self.statusText = @"已暂停";
    [self updateNowPlayingInfo];
    [self publishState];
}

- (void)resume {
    if (!self.currentItem) return;
    if (!self.player || self.state == OEMusicPlaybackStateFailed) {
        [self loadCurrentItem];
        return;
    }
    [self.player play];
    self.state = OEMusicPlaybackStateBuffering;
    self.statusText = @"正在缓冲…";
    [self updateNowPlayingInfo];
    [self publishState];
}

- (void)next {
    if (self.currentIndex + 1 < (NSInteger)self.playlist.count) {
        self.currentIndex++;
        [self loadCurrentItem];
    }
}

- (void)previous {
    if (self.currentIndex > 0) {
        self.currentIndex--;
        [self loadCurrentItem];
    } else if (self.currentTime > 3.0) {
        [self seekToProgress:0 completion:nil];
    }
}

- (void)seekToProgress:(float)progress completion:(void(^)(BOOL finished))completion {
    if (!self.player || self.duration <= 0) { if (completion) completion(NO); return; }
    self.seeking = YES;
    CMTime target = CMTimeMakeWithSeconds(MAX(0, MIN(1, progress)) * self.duration, 600);
    // -seekToTime:completionHandler: is iOS 7+. Calling it on an iOS 6
    // device causes an unrecognized-selector crash exactly when the user
    // releases the full-player slider. The synchronous selector is available
    // on the deployment target and is sufficient for this UI.
    [self.player seekToTime:target];
    self.seeking = NO;
    [self updateProgress];
    if (completion) completion(YES);
}

- (void)itemDidFinish:(NSNotification *)notification {
    if (self.currentIndex + 1 < (NSInteger)self.playlist.count) [self next];
    else {
        self.progress = 0;
        self.currentTime = 0;
        self.state = OEMusicPlaybackStatePaused;
        self.statusText = @"播放结束";
        [self updateNowPlayingInfo];
        [self publishState];
        [self publishProgress];
    }
}

- (void)itemFailed:(NSNotification *)notification {
    NSError *error = notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    self.state = OEMusicPlaybackStateFailed;
    self.statusText = [NSString stringWithFormat:@"播放失败：%@", error.localizedDescription ?: @"媒体流中断"];
    [self updateNowPlayingInfo];
    [self publishState];
}

- (void)audioInterrupted:(NSNotification *)notification {
    NSNumber *type = notification.userInfo[AVAudioSessionInterruptionTypeKey];
    if ([type unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan) {
        [self pause];
    } else if ([type unsignedIntegerValue] == AVAudioSessionInterruptionTypeEnded) {
        NSNumber *options = notification.userInfo[AVAudioSessionInterruptionOptionKey];
        if ([options unsignedIntegerValue] == AVAudioSessionInterruptionOptionShouldResume) [self resume];
    }
}

- (void)receiveRemoteControlEvent:(UIEvent *)event {
    if (event.type != UIEventTypeRemoteControl) return;
    if (event.subtype == UIEventSubtypeRemoteControlPlay) [self resume];
    else if (event.subtype == UIEventSubtypeRemoteControlPause) [self pause];
    else if (event.subtype == UIEventSubtypeRemoteControlTogglePlayPause) [self togglePlayPause];
    else if (event.subtype == UIEventSubtypeRemoteControlNextTrack) [self next];
    else if (event.subtype == UIEventSubtypeRemoteControlPreviousTrack) [self previous];
}

- (void)cleanupPlayer {
    if (self.timeObserver) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
    if (self.playerItem) {
        @try { [self.playerItem removeObserver:self forKeyPath:@"status"]; } @catch (NSException *exception) {}
        @try { [self.playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"]; } @catch (NSException *exception) {}
        @try { [self.playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"]; } @catch (NSException *exception) {}
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.playerItem];
    }
    [self.player pause];
    self.player = nil;
    self.playerItem = nil;
}

- (void)dealloc {
    [self cleanupPlayer];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
