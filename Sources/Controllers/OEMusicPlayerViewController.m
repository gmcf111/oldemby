#import "OEMusicPlayerViewController.h"
#import "Models/OEEmbyItem.h"
#import "Services/OEEmbyAPIClient.h"
#import "Services/OEImageCache.h"
#import "Constants.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface OEMusicPlayerViewController ()
@property (nonatomic, strong) OEEmbyItem *currentItem;
@property (nonatomic, strong) NSArray *playlist;
@property (nonatomic, assign) NSInteger currentIndex;

@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UIButton *playPauseBtn;
@property (nonatomic, strong) UIButton *nextBtn;
@property (nonatomic, strong) UIButton *prevBtn;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UILabel *timeLabel;

@property (nonatomic, strong) AVPlayer *player; // iOS6+ AVPlayer supports streaming audio; fallback to AVAudioPlayer via NSURLConnection would be complex
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL isSeeking;
@property (nonatomic, assign) NSUInteger loadGeneration;
@end

@implementation OEMusicPlayerViewController

- (instancetype)initWithItem:(OEEmbyItem *)item playlist:(NSArray *)playlist {
    if ((self = [super init])) {
        _currentItem = item;
        _playlist = playlist;
        _currentIndex = [playlist indexOfObject:item];
        if (_currentIndex == NSNotFound) _currentIndex = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"正在播放";

    CGFloat w = self.view.bounds.size.width;
    self.artworkView = [[UIImageView alloc] initWithFrame:CGRectMake((w-200)/2, 80, 200, 200)];
    self.artworkView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.clipsToBounds = YES;
    self.artworkView.layer.cornerRadius = 8;
    [self.view addSubview:self.artworkView];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 300, w-40, 22)];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.titleLabel];

    self.artistLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 324, w-40, 18)];
    self.artistLabel.font = [UIFont systemFontOfSize:13];
    self.artistLabel.textAlignment = NSTextAlignmentCenter;
    self.artistLabel.textColor = [UIColor grayColor];
    [self.view addSubview:self.artistLabel];

    self.progressSlider = [[UISlider alloc] initWithFrame:CGRectMake(20, 350, w-40, 20)];
    [self.progressSlider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [self.progressSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.progressSlider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.view addSubview:self.progressSlider];

    self.timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 370, w-40, 16)];
    self.timeLabel.font = [UIFont systemFontOfSize:11];
    self.timeLabel.textAlignment = NSTextAlignmentCenter;
    self.timeLabel.textColor = [UIColor darkGrayColor];
    [self.view addSubview:self.timeLabel];

    CGFloat btnY = 400;
    CGFloat btnW = 60;
    self.prevBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.prevBtn.frame = CGRectMake((w - btnW*3 - 40)/2, btnY, btnW, 44);
    [self.prevBtn setTitle:@"上一首" forState:UIControlStateNormal];
    [self.prevBtn addTarget:self action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.prevBtn];

    self.playPauseBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.playPauseBtn.frame = CGRectMake((w - btnW*3 - 40)/2 + btnW+20, btnY, btnW, 44);
    [self.playPauseBtn setTitle:@"播放" forState:UIControlStateNormal];
    [self.playPauseBtn addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    self.playPauseBtn.backgroundColor = [UIColor colorWithRed:0 green:0.47 blue:1 alpha:1];
    [self.playPauseBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.playPauseBtn.layer.cornerRadius = 6;
    [self.view addSubview:self.playPauseBtn];

    self.nextBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.nextBtn.frame = CGRectMake((w - btnW*3 - 40)/2 + (btnW+20)*2, btnY, btnW, 44);
    [self.nextBtn setTitle:@"下一首" forState:UIControlStateNormal];
    [self.nextBtn addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.nextBtn];

    // Remote control
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleRemote:) name:kNotificationPlaybackStateChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAudioInterruption:) name:AVAudioSessionInterruptionNotification object:nil];

    [self loadCurrentItem];
}

- (void)loadCurrentItem {
    NSUInteger generation = ++self.loadGeneration;
    OEEmbyItem *it = self.playlist[self.currentIndex];
    self.currentItem = it;
    [self cleanupPlayer];
    self.isPlaying = NO;
    self.titleLabel.text = it.name;
    self.artistLabel.text = it.artist ?: it.album ?: @"";
    self.timeLabel.text = @"正在获取...";

    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:it width:400];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image){
        if (generation != self.loadGeneration || self.currentItem != it) return;
        self.artworkView.image = image;
        [self updateNowPlayingInfo];
    }];

    // Fetch stream URL
    [[OEEmbyAPIClient sharedClient] fetchStreamURLForItem:it.itemId isAudio:YES completion:^(id result, NSError *error){
        if (generation != self.loadGeneration || self.currentItem != it) return;
        if (error) {
            self.timeLabel.text = [NSString stringWithFormat:@"失败: %@", error.localizedDescription];
            return;
        }
        NSString *stream = (NSString *)result;
        NSLog(@"[OldEmby][Music] stream URL: %@", stream);
        NSURL *streamURL = [stream isKindOfClass:[NSString class]] ? [NSURL URLWithString:stream] : nil;
        if (!streamURL) {
            self.timeLabel.text = @"Invalid stream URL";
            return;
        }
        [self playURL:streamURL];
    }];
}

- (void)playURL:(NSURL *)url {
    [self cleanupPlayer];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    self.player = [AVPlayer playerWithPlayerItem:item];
    // Observe end
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinish:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    // Periodic time observer (iOS6+)
    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time){
        [weakSelf updateProgress];
    }];
    [self.player play];
    self.isPlaying = YES;
    [self.playPauseBtn setTitle:@"暂停" forState:UIControlStateNormal];
    [self updateNowPlayingInfo];
}

- (void)cleanupPlayer {
    if (self.timeObserver) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [self.player pause];
    self.player = nil;
}

- (void)updateProgress {
    if (!self.player || self.isSeeking) return;
    CMTime cur = self.player.currentTime;
    CMTime dur = self.player.currentItem.duration;
    if (CMTIME_IS_INVALID(dur) || dur.value==0) return;
    Float64 c = CMTimeGetSeconds(cur);
    Float64 d = CMTimeGetSeconds(dur);
    if (d>0) {
        self.progressSlider.value = c / d;
        self.timeLabel.text = [NSString stringWithFormat:@"%02d:%02d / %02d:%02d", (int)c/60, (int)c%60, (int)d/60, (int)d%60];
    }
    [self updateNowPlayingInfo];
}

- (void)updateNowPlayingInfo {
    if (!self.currentItem) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = self.currentItem.name ?: @"";
    info[MPMediaItemPropertyArtist] = self.currentItem.artist ?: @"";
    info[MPMediaItemPropertyAlbumTitle] = self.currentItem.album ?: @"";
    if (self.artworkView.image) {
        MPMediaItemArtwork *art = [[MPMediaItemArtwork alloc] initWithImage:self.artworkView.image];
        info[MPMediaItemPropertyArtwork] = art;
    }
    if (self.player && self.player.currentItem) {
        CMTime dur = self.player.currentItem.duration;
        if (!CMTIME_IS_INVALID(dur)) {
            info[MPMediaItemPropertyPlaybackDuration] = @(CMTimeGetSeconds(dur));
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(CMTimeGetSeconds(self.player.currentTime));
            info[MPNowPlayingInfoPropertyPlaybackRate] = @(self.isPlaying?1.0:0.0);
        }
    }
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:info];
}

- (void)handleRemote:(NSNotification *)n {
    UIEvent *ev = n.object;
    if (ev.subtype == UIEventSubtypeRemoteControlPlay) [self resume];
    else if (ev.subtype == UIEventSubtypeRemoteControlPause) [self pause];
    else if (ev.subtype == UIEventSubtypeRemoteControlTogglePlayPause) [self playPauseTapped];
    else if (ev.subtype == UIEventSubtypeRemoteControlNextTrack) [self nextTapped];
    else if (ev.subtype == UIEventSubtypeRemoteControlPreviousTrack) [self prevTapped];
}

- (void)handleAudioInterruption:(NSNotification *)n {
    NSNumber *typeNum = n.userInfo[AVAudioSessionInterruptionTypeKey];
    if (!typeNum) return;
    NSUInteger type = [typeNum unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        [self pause];
    } else if (type == AVAudioSessionInterruptionTypeEnded) {
        NSNumber *optNum = n.userInfo[AVAudioSessionInterruptionOptionKey];
        if ([optNum unsignedIntegerValue] == AVAudioSessionInterruptionOptionShouldResume) {
            [self resume];
        }
    }
}

- (void)playPauseTapped {
    if (self.isPlaying) [self pause]; else [self resume];
}

- (void)pause {
    [self.player pause];
    self.isPlaying = NO;
    [self.playPauseBtn setTitle:@"播放" forState:UIControlStateNormal];
    [self updateNowPlayingInfo];
}

- (void)resume {
    [self.player play];
    self.isPlaying = YES;
    [self.playPauseBtn setTitle:@"暂停" forState:UIControlStateNormal];
    [self updateNowPlayingInfo];
}

- (void)nextTapped {
    if (self.currentIndex +1 < self.playlist.count) {
        self.currentIndex++;
        [self loadCurrentItem];
    }
}

- (void)prevTapped {
    if (self.currentIndex >0) {
        self.currentIndex--;
        [self loadCurrentItem];
    }
}

- (void)sliderTouchDown {
    self.isSeeking = YES;
}

- (void)sliderChanged:(UISlider *)s {
    if (!self.player) return;
    CMTime dur = self.player.currentItem.duration;
    if (CMTIME_IS_INVALID(dur) || dur.value == 0) return;
    Float64 d = CMTimeGetSeconds(dur);
    Float64 previewTime = d * s.value;
    self.timeLabel.text = [NSString stringWithFormat:@"%02d:%02d / %02d:%02d", (int)previewTime/60, (int)previewTime%60, (int)d/60, (int)d%60];
}

- (void)sliderTouchUp {
    self.isSeeking = NO;
    if (!self.player) return;
    CMTime dur = self.player.currentItem.duration;
    if (CMTIME_IS_INVALID(dur) || dur.value == 0) return;
    Float64 d = CMTimeGetSeconds(dur);
    Float64 t = d * self.progressSlider.value;
    [self.player seekToTime:CMTimeMakeWithSeconds(t, 600) completionHandler:^(BOOL finished){
        [self updateNowPlayingInfo];
    }];
}

- (void)itemDidFinish:(NSNotification *)n {
    if (self.currentIndex + 1 < self.playlist.count) {
        [self nextTapped];
    } else {
        [self pause];
        [self.progressSlider setValue:0 animated:YES];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Keep playing in background due to UIBackgroundModes audio, don't cleanup unless popped
    if ([self.navigationController.viewControllers indexOfObject:self]==NSNotFound) {
        // popped
        [self cleanupPlayer];
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
    }
}

- (void)dealloc {
    [self cleanupPlayer];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

@end
