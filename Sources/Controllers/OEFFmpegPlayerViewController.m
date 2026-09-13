//
//  OEFFmpegPlayerViewController.m
//  OldEmby
//
//  Direct-play engine for containers the iOS system player cannot demux
//  (MKV, AVI, WMV, RMVB…).  The playback loop and A/V synchronisation follow
//  the kxmovie reference implementation (LGPL v3, see Sources/Player), while
//  the UI is hand-built here in the project's pure-frame style and reuses the
//  server-SRT subtitle overlay so the experience matches the system player.
//

#import "OEFFmpegPlayerViewController.h"
#import "Player/KxMovieDecoder.h"
#import "Player/KxAudioManager.h"
#import "Player/KxMovieGLView.h"
#import "Player/KxLogger.h"
#import "Models/OEStreamInfo.h"
#import "Models/OESRTSubtitleParser.h"
#import "Services/OEEmbyAPIClient.h"
#import "Views/OESubtitleOverlayView.h"
#import "Constants.h"
#import <QuartzCore/QuartzCore.h>
#include <string.h>
#include <stdlib.h>
#import <math.h>

static const CGFloat kFFTopBarHeight = 44.0;
static const CGFloat kFFBottomBarHeight = 104.0;
static const CGFloat kFFButtonSize = 44.0;
static const CGFloat kFFWideButtonWidth = 52.0;
static const NSTimeInterval kFFSkipInterval = 15.0;
static const CGFloat kFFNoticeDuration = 2.5;

// Decoded-frame buffering windows (seconds).  Old 32-bit devices have little
// RAM; a 4s window at 720p YUV costs >100 MB, so keep it deliberately small.
static const CGFloat kFFNetworkMinBuffered = 1.0;
static const CGFloat kFFNetworkMaxBuffered = 2.5;
static const CGFloat kFFLocalMinBuffered = 0.2;
static const CGFloat kFFLocalMaxBuffered = 0.4;

static NSString *OEFFFormatTime(CGFloat seconds)
{
    seconds = MAX(0, seconds);
    NSInteger s = (NSInteger)seconds;
    NSInteger m = s / 60;
    NSInteger h = m / 60;
    s = s % 60;
    m = m % 60;
    if (h != 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

@interface OEFFmpegPlayerViewController () <UIActionSheetDelegate> {

    KxMovieDecoder      *_decoder;
    dispatch_queue_t    _dispatchQueue;
    NSMutableArray      *_videoFrames;
    NSMutableArray      *_audioFrames;
    NSData              *_currentAudioFrame;
    NSUInteger          _currentAudioFramePos;
    CGFloat             _moviePosition;
    BOOL                _disableUpdateHUD;
    NSTimeInterval      _tickCorrectionTime;
    NSTimeInterval      _tickCorrectionPosition;
    NSUInteger          _tickCounter;
    BOOL                _interrupted;
    BOOL                _savedIdleTimer;

    CGFloat             _bufferedDuration;
    CGFloat             _minBufferedDuration;
    CGFloat             _maxBufferedDuration;
    BOOL                _buffered;

    KxMovieGLView       *_glView;
    UIImageView         *_imageView;
    UIView              *_topBar;
    UIView              *_bottomBar;
    UIButton            *_doneButton;
    UILabel             *_titleLabel;
    UIButton            *_playButton;
    UIButton            *_rewindButton;
    UIButton            *_forwardButton;
    UIButton            *_audioButton;
    UIButton            *_subtitleButton;
    UISlider            *_progressSlider;
    UILabel             *_positionLabel;
    UILabel             *_durationLabel;
    UIActivityIndicatorView *_activity;
    OESubtitleOverlayView *_subtitleOverlay;
    BOOL                _hudVisible;

    // Subtitles served by the Emby SRT endpoint, drawn by the overlay.
    NSArray             *_subtitleCues;
    NSInteger            _selectedSubtitleTrack;
    NSUInteger           _subtitleLoadGeneration;
    NSUInteger           _subtitleNoticeGeneration;

    UIActionSheet       *_activeSheet;
}

@property (readwrite) BOOL playing;
@property (readwrite) BOOL decoding;

@end

@implementation OEFFmpegPlayerViewController

- (instancetype)initWithContentURLString:(NSString *)urlString
{
    NSParameterAssert(urlString.length);
    self = [super initWithNibName:nil bundle:nil];
    if (self) {

        _moviePosition = 0;
        _selectedSubtitleTrack = -1;
        _interrupted = NO;

        // The resampler consults the audio manager for the hardware sample
        // rate and channel count, so the session must be live before open.
        [[KxAudioManager audioManager] activateAudioSession];

        __weak OEFFmpegPlayerViewController *weakSelf = self;
        KxMovieDecoder *decoder = [[KxMovieDecoder alloc] init];
        decoder.interruptCallback = ^BOOL(){
            __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
            return strongSelf ? strongSelf->_interrupted : YES;
        };

        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSError *error = nil;
            [decoder openFile:urlString error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
                if (strongSelf) [strongSelf installDecoder:decoder withError:error];
            });
        });
    }
    return self;
}

- (void)dealloc
{
    [self pause];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self dismissActiveSheetForDealloc];
}

#pragma mark - View & controls

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.view.opaque = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleHUD)];
    tap.numberOfTapsRequired = 1;
    [self.view addGestureRecognizer:tap];

    _subtitleOverlay = [[OESubtitleOverlayView alloc] initWithFrame:self.view.bounds];
    _subtitleOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _subtitleOverlay.bottomInset = kFFBottomBarHeight;
    [self.view addSubview:_subtitleOverlay];

    _topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, kFFTopBarHeight)];
    _topBar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_topBar];

    _doneButton = [self hudButtonWithTitle:@"完成"];
    [_doneButton addTarget:self action:@selector(doneDidTouch) forControlEvents:UIControlEventTouchUpInside];
    [_topBar addSubview:_doneButton];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.font = [UIFont boldSystemFontOfSize:14];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.text = self.movieTitle;
    [_topBar addSubview:_titleLabel];

    _bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
    _bottomBar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _bottomBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:_bottomBar];

    _playButton = [self hudButtonWithTitle:@"▶"];
    _playButton.titleLabel.font = [UIFont systemFontOfSize:22];
    [_playButton addTarget:self action:@selector(playDidTouch) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_playButton];

    _rewindButton = [self hudButtonWithTitle:[NSString stringWithFormat:@"-%lds", (long)kFFSkipInterval]];
    [_rewindButton addTarget:self action:@selector(rewindDidTouch) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_rewindButton];

    _forwardButton = [self hudButtonWithTitle:[NSString stringWithFormat:@"+%lds", (long)kFFSkipInterval]];
    [_forwardButton addTarget:self action:@selector(forwardDidTouch) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_forwardButton];

    _audioButton = [self hudButtonWithTitle:@"音轨"];
    [_audioButton addTarget:self action:@selector(audioDidTouch) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_audioButton];

    _subtitleButton = [self hudButtonWithTitle:@"字幕"];
    [_subtitleButton addTarget:self action:@selector(subtitleDidTouch) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_subtitleButton];

    _positionLabel = [self timeLabel];
    [_bottomBar addSubview:_positionLabel];

    _durationLabel = [self timeLabel];
    [_bottomBar addSubview:_durationLabel];

    _progressSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _progressSlider.continuous = NO;
    _progressSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_progressSlider addTarget:self action:@selector(progressDidChange:) forControlEvents:UIControlEventValueChanged];
    [_bottomBar addSubview:_progressSlider];

    _activity = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _activity.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    _activity.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:_activity];

    _hudVisible = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:[UIApplication sharedApplication]];

    if (_decoder) {
        [_activity stopAnimating];
        [self setupPresentView];
        [self restorePlay];
    } else {
        [_activity startAnimating];
    }
}

- (UIButton *)hudButtonWithTitle:(NSString *)title
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = [UIColor clearColor];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.4] forState:UIControlStateDisabled];
    button.titleLabel.font = [UIFont systemFontOfSize:15];
    [button setTitle:title forState:UIControlStateNormal];
    button.showsTouchWhenHighlighted = YES;
    return button;
}

- (UILabel *)timeLabel
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:11];
    label.textAlignment = NSTextAlignmentCenter;
    return label;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    _topBar.frame = CGRectMake(0, 0, w, kFFTopBarHeight);
    _doneButton.frame = CGRectMake(6, 2, 64, kFFTopBarHeight - 4);
    CGFloat titleX = CGRectGetMaxX(_doneButton.frame) + 6;
    _titleLabel.frame = CGRectMake(titleX, 2, w - titleX - 10, kFFTopBarHeight - 4);

    _bottomBar.frame = CGRectMake(0, h - kFFBottomBarHeight, w, kFFBottomBarHeight);
    CGFloat midY = h - kFFBottomBarHeight;

    // Row 1: time + slider
    _positionLabel.frame = CGRectMake(6, midY + 4, 54, 24);
    _durationLabel.frame = CGRectMake(w - 60, midY + 4, 54, 24);
    _progressSlider.frame = CGRectMake(64, midY + 2, w - 128, 28);

    // Row 2: transport
    CGFloat btnY = midY + 34;
    CGFloat x = 10;
    _playButton.frame = CGRectMake(x, btnY, kFFButtonSize, kFFButtonSize); x += kFFButtonSize + 6;
    _rewindButton.frame = CGRectMake(x, btnY, kFFButtonSize, kFFButtonSize); x += kFFButtonSize + 6;
    _forwardButton.frame = CGRectMake(x, btnY, kFFButtonSize, kFFButtonSize);
    CGFloat rightX = w - 10;
    _subtitleButton.frame = CGRectMake(rightX - kFFWideButtonWidth, btnY, kFFWideButtonWidth, kFFButtonSize); rightX -= kFFWideButtonWidth + 6;
    _audioButton.frame = CGRectMake(rightX - kFFWideButtonWidth, btnY, kFFWideButtonWidth, kFFButtonSize);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void)toggleHUD
{
    _hudVisible = !_hudVisible;
    CGFloat alpha = _hudVisible ? 1.0 : 0.0;
    [UIView animateWithDuration:0.2 animations:^{
        _topBar.alpha = alpha;
        _bottomBar.alpha = alpha;
    }];
}

#pragma mark - Decoder installation

- (void)installDecoder:(KxMovieDecoder *)decoder withError:(NSError *)error
{
    if (self.isViewLoaded && self.view.window) [_activity stopAnimating];

    if (error || !decoder.validVideo) {
        NSString *msg = error.localizedDescription ?: @"无法解析该媒体文件（编码器可能不受支持）。请改用转码播放。";
        [self showFailureAndOfferExit:msg];
        return;
    }

    _decoder = decoder;
    _dispatchQueue = dispatch_queue_create("com.oldemby.ffmpeg", NULL);
    _videoFrames = [NSMutableArray array];
    _audioFrames = [NSMutableArray array];

    if (_decoder.isNetwork) {
        _minBufferedDuration = kFFNetworkMinBuffered;
        _maxBufferedDuration = kFFNetworkMaxBuffered;
    } else {
        _minBufferedDuration = kFFLocalMinBuffered;
        _maxBufferedDuration = kFFLocalMaxBuffered;
    }

    if (self.isViewLoaded) {
        [self setupPresentView];
        [self restorePlay];
    }
}

- (void)setupPresentView
{
    CGRect bounds = self.view.bounds;
    if (_decoder.validVideo) {
        _glView = [[KxMovieGLView alloc] initWithFrame:bounds decoder:_decoder];
    }
    if (!_glView) {
        LoggerVideo(0, @"OldEmby: GL unavailable, falling back to RGB frames");
        [_decoder setupVideoFrameFormat:KxVideoFrameFormatRGB];
        _imageView = [[UIImageView alloc] initWithFrame:bounds];
        _imageView.backgroundColor = [UIColor blackColor];
    }
    UIView *frameView = _glView ? (UIView *)_glView : (UIView *)_imageView;
    frameView.contentMode = UIViewContentModeScaleAspectFit;
    frameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:frameView atIndex:0];
    // The overlay must stay above the picture, the HUD above everything.
    [self.view bringSubviewToFront:_subtitleOverlay];
    [self.view bringSubviewToFront:_topBar];
    [self.view bringSubviewToFront:_bottomBar];
}

- (void)restorePlay
{
    [self play];
}

#pragma mark - Play / pause

- (void)play
{
    if (self.playing) return;
    if (!_decoder.validVideo && !_decoder.validAudio) return;
    if (_interrupted) return;

    self.playing = YES;
    _disableUpdateHUD = NO;
    _tickCorrectionTime = 0;
    _tickCounter = 0;
    _savedIdleTimer = [[UIApplication sharedApplication] isIdleTimerDisabled];
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];

    [self asyncDecodeFrames];
    [self updatePlayButton];

    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){ [self tick]; });

    if (_decoder.validAudio) [self enableAudio:YES];
}

- (void)pause
{
    if (!self.playing) return;
    self.playing = NO;
    [self enableAudio:NO];
    [self updatePlayButton];
    [[UIApplication sharedApplication] setIdleTimerDisabled:_savedIdleTimer];
}

- (void)updatePlayButton
{
    [_playButton setTitle:self.playing ? @"⏸" : @"▶" forState:UIControlStateNormal];
}

- (void)enableAudio:(BOOL)on
{
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    if (on && _decoder.validAudio) {
        __weak OEFFmpegPlayerViewController *weakSelf = self;
        audioManager.outputBlock = ^(float *outData, UInt32 numFrames, UInt32 numChannels) {
            __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
            if (strongSelf) [strongSelf audioCallbackFillData:outData numFrames:numFrames numChannels:numChannels];
            else memset(outData, 0, numFrames * numChannels * sizeof(float));
        };
        [audioManager play];
    } else {
        [audioManager pause];
        audioManager.outputBlock = nil;
    }
}

#pragma mark - Actions

- (void)playDidTouch
{
    if (self.playing) [self pause];
    else [self play];
}

- (void)rewindDidTouch
{
    [self seekToPosition:_moviePosition - kFFSkipInterval];
}

- (void)forwardDidTouch
{
    [self seekToPosition:_moviePosition + kFFSkipInterval];
}

- (void)progressDidChange:(id)sender
{
    CGFloat duration = _decoder.duration;
    if (!(duration > 0) || duration == MAXFLOAT) return;
    [self seekToPosition:[(UISlider *)sender value] * duration];
}

- (void)seekToPosition:(CGFloat)position
{
    if (!_decoder) return;
    BOOL playMode = self.playing;
    self.playing = NO;
    _disableUpdateHUD = YES;
    [self enableAudio:NO];

    __weak OEFFmpegPlayerViewController *weakSelf = self;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
        if (strongSelf) [strongSelf updatePosition:position playMode:playMode];
    });
}

- (void)updatePosition:(CGFloat)position playMode:(BOOL)playMode
{
    [self freeBufferedFrames];

    CGFloat duration = _decoder.duration;
    if (duration > 0 && duration != MAXFLOAT) {
        position = MIN(duration - 1, MAX(0, position));
    } else {
        position = MAX(0, position);
    }

    __weak OEFFmpegPlayerViewController *weakSelf = self;
    dispatch_async(_dispatchQueue, ^{
        {
            __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_decoder.position = position;
            if (playMode) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong OEFFmpegPlayerViewController *s = weakSelf;
                    if (!s) return;
                    s->_moviePosition = s->_decoder.position;
                    [s play];
                });
            } else {
                [strongSelf decodeOneBatch];
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong OEFFmpegPlayerViewController *s = weakSelf;
                    if (!s) return;
                    s->_disableUpdateHUD = NO;
                    s->_moviePosition = s->_decoder.position;
                    [s presentFrame];
                    [s updateHUD];
                });
            }
        }
    });
}

- (BOOL)decodeOneBatch
{
    if (_decoder.validVideo || _decoder.validAudio) {
        NSArray *frames = [_decoder decodeFrames:0];
        if (frames.count) return [self addFrames:frames];
    }
    return NO;
}

- (void)doneDidTouch
{
    [self pause];
    if (self.presentingViewController) {
        __block void (^handler)(void) = self.dismissHandler;
        self.dismissHandler = nil;
        [self dismissViewControllerAnimated:YES completion:^{
            if (handler) handler();
        }];
    } else if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
        if (self.dismissHandler) self.dismissHandler();
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self pause];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    if (self.playing) {
        [self pause];
        [self freeBufferedFrames];
        _minBufferedDuration = kFFNetworkMinBuffered * 0.5;
        _maxBufferedDuration = kFFNetworkMaxBuffered * 0.5;
        [self play];
    } else {
        [self freeBufferedFrames];
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:[UIApplication sharedApplication]];
    [super viewWillDisappear:animated];
    [self pause];
    [self clearSubtitleCues];
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    _interrupted = YES;
    _buffered = NO;
}

#pragma mark - Buffering / decode loop

- (BOOL)addFrames:(NSArray *)frames
{
    if (_decoder.validVideo) {
        @synchronized(_videoFrames) {
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeVideo) {
                    [_videoFrames addObject:frame];
                    _bufferedDuration += frame.duration;
                }
        }
    }
    if (_decoder.validAudio) {
        @synchronized(_audioFrames) {
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeAudio)
                    [_audioFrames addObject:frame];
        }
    }
    return self.playing && _bufferedDuration < _maxBufferedDuration;
}

- (void)asyncDecodeFrames
{
    if (self.decoding) return;

    __weak OEFFmpegPlayerViewController *weakSelf = self;
    __weak KxMovieDecoder *weakDecoder = _decoder;
    const CGFloat duration = _decoder.isNetwork ? 0.0f : 0.1f;

    self.decoding = YES;
    dispatch_async(_dispatchQueue, ^{
        {
            __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
            if (!strongSelf.playing) {
                if (strongSelf) strongSelf.decoding = NO;
                return;
            }
        }
        BOOL good = YES;
        while (good) {
            good = NO;
            @autoreleasepool {
                __strong KxMovieDecoder *decoder = weakDecoder;
                if (decoder && (decoder.validVideo || decoder.validAudio)) {
                    NSArray *frames = [decoder decodeFrames:duration];
                    if (frames.count) {
                        __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
                        if (strongSelf) good = [strongSelf addFrames:frames];
                    }
                }
            }
        }
        __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
        if (strongSelf) strongSelf.decoding = NO;
    });
}

- (void)tick
{
    if (_buffered && ((_bufferedDuration > _minBufferedDuration) || _decoder.isEOF)) {
        _tickCorrectionTime = 0;
        _buffered = NO;
        [_activity stopAnimating];
    }

    CGFloat interval = 0;
    if (!_buffered) interval = [self presentFrame];

    if (self.playing) {

        const NSUInteger leftFrames =
            (_decoder.validVideo ? _videoFrames.count : 0) +
            (_decoder.validAudio ? _audioFrames.count : 0);

        if (0 == leftFrames) {
            if (_decoder.isEOF) {
                [self pause];
                [self updateHUD];
                return;
            }
            if (_minBufferedDuration > 0 && !_buffered) {
                _buffered = YES;
                [_activity startAnimating];
            }
        }

        if (!leftFrames || !(_bufferedDuration > _minBufferedDuration)) {
            [self asyncDecodeFrames];
        }

        const NSTimeInterval correction = [self tickCorrection];
        const NSTimeInterval time = MAX(interval + correction, 0.01);
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(time * NSEC_PER_SEC));
        __weak OEFFmpegPlayerViewController *weakSelf = self;
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
            if (strongSelf) [strongSelf tick];
        });
    }

    if ((_tickCounter++ % 3) == 0) {
        [self updateHUD];
        [self updateSubtitleDisplay];
    }
}

- (CGFloat)tickCorrection
{
    if (_buffered) return 0;

    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!_tickCorrectionTime) {
        _tickCorrectionTime = now;
        _tickCorrectionPosition = _moviePosition;
        return 0;
    }

    NSTimeInterval dPosition = _moviePosition - _tickCorrectionPosition;
    NSTimeInterval dTime = now - _tickCorrectionTime;
    NSTimeInterval correction = dPosition - dTime;
    if (correction > 1.f || correction < -1.f) {
        correction = 0;
        _tickCorrectionTime = 0;
    }
    return correction;
}

- (CGFloat)presentFrame
{
    CGFloat interval = 0;
    if (_decoder.validVideo) {
        KxVideoFrame *frame = nil;
        @synchronized(_videoFrames) {
            if (_videoFrames.count > 0) {
                frame = _videoFrames[0];
                [_videoFrames removeObjectAtIndex:0];
                _bufferedDuration -= frame.duration;
            }
        }
        if (frame) {
            if (_glView) {
                [_glView render:frame];
            } else if ([frame isKindOfClass:[KxVideoFrameRGB class]]) {
                _imageView.image = [(KxVideoFrameRGB *)frame asImage];
            }
            _moviePosition = frame.position;
            interval = frame.duration;
        }
    }
    return interval;
}

- (void)freeBufferedFrames
{
    @synchronized(_videoFrames) { [_videoFrames removeAllObjects]; }
    @synchronized(_audioFrames) {
        [_audioFrames removeAllObjects];
        _currentAudioFrame = nil;
    }
    _bufferedDuration = 0;
}

#pragma mark - Audio clock

- (void)audioCallbackFillData:(float *)outData numFrames:(UInt32)numFrames numChannels:(UInt32)numChannels
{
    if (_buffered) {
        memset(outData, 0, numFrames * numChannels * sizeof(float));
        return;
    }

    @autoreleasepool {
        while (numFrames > 0) {

            if (!_currentAudioFrame) {
                @synchronized(_audioFrames) {
                    NSUInteger count = _audioFrames.count;
                    if (count > 0) {
                        KxAudioFrame *frame = _audioFrames[0];
                        const CGFloat delta = _moviePosition - frame.position;
                        if (delta < -0.1) {
                            memset(outData, 0, numFrames * numChannels * sizeof(float));
                            break; // video is ahead: stay silent, wait
                        }
                        [_audioFrames removeObjectAtIndex:0];
                        if (delta > 0.1 && count > 1) continue; // audio lags: skip
                        _currentAudioFramePos = 0;
                        _currentAudioFrame = frame.samples;
                    }
                }
            }

            if (_currentAudioFrame) {
                const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels * sizeof(float);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                if (bytesToCopy < bytesLeft) _currentAudioFramePos += bytesToCopy;
                else _currentAudioFrame = nil;
            } else {
                memset(outData, 0, numFrames * numChannels * sizeof(float));
                break;
            }
        }
    }
}

#pragma mark - HUD updates

- (void)updateHUD
{
    if (_disableUpdateHUD || !_decoder) return;

    CGFloat duration = _decoder.duration;
    CGFloat position = _moviePosition - _decoder.startTime;

    if (duration > 0 && duration != MAXFLOAT) {
        if (_progressSlider.state == UIControlStateNormal)
            _progressSlider.value = position / duration;
        _durationLabel.text = OEFFFormatTime(duration);
    } else {
        _progressSlider.enabled = NO;
        _durationLabel.text = @"--:--";
    }
    _positionLabel.text = OEFFFormatTime(position);
}

#pragma mark - Track sheets

- (void)audioDidTouch
{
    if (!_decoder) return;
    NSArray *names = _decoder.info[@"audio"];
    if (![names isKindOfClass:[NSArray class]] || names.count < 2) {
        [self showNotice:@"该视频只有一条音轨"];
        return;
    }
    [self dismissActiveSheet];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"选择音轨"
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    sheet.tag = 9100;
    NSInteger selected = _decoder.selectedAudioStream;
    for (NSUInteger i = 0; i < names.count; i++) {
        NSString *title = [NSString stringWithFormat:@"%@", names[i]];
        if ((NSInteger)i == selected) title = [NSString stringWithFormat:@"✓ %@", title];
        [sheet addButtonWithTitle:title];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"取消"];
    _activeSheet = sheet;
    [sheet showInView:self.view];
}

- (void)subtitleDidTouch
{
    NSArray *tracks = self.subtitleTracks;
    [self dismissActiveSheet];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"选择字幕"
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    sheet.tag = 9200;
    [sheet addButtonWithTitle:[NSString stringWithFormat:@"%@关闭字幕", _selectedSubtitleTrack < 0 ? @"✓ " : @""]];
    for (NSUInteger i = 0; i < tracks.count; i++) {
        OEStreamInfo *info = tracks[i];
        NSString *title = info.title.length ? info.title : @"未知";
        if ((NSInteger)i == _selectedSubtitleTrack) title = [NSString stringWithFormat:@"✓ %@", title];
        [sheet addButtonWithTitle:title];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"取消"];
    _activeSheet = sheet;
    [sheet showInView:self.view];
}

- (void)dismissActiveSheet
{
    UIActionSheet *sheet = _activeSheet;
    if (!sheet) return;
    _activeSheet = nil;
    sheet.delegate = nil;
    [sheet dismissWithClickedButtonIndex:sheet.cancelButtonIndex animated:NO];
}

- (void)dismissActiveSheetForDealloc
{
    UIActionSheet *sheet = _activeSheet;
    if (!sheet) return;
    _activeSheet = nil;
    sheet.delegate = nil;
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.cancelButtonIndex) return;
    if (actionSheet.tag == 9100) {
        if (buttonIndex >= (NSInteger)[_decoder.info[@"audio"] count]) return;
        NSInteger chosen = buttonIndex;
        if (chosen == _decoder.selectedAudioStream) return;
        // Decoder stream switching touches AVCodecContext; run it on the same
        // serial queue that decodes so it never races decodeFrames.
        __weak OEFFmpegPlayerViewController *weakSelf = self;
        dispatch_async(_dispatchQueue, ^{
            __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_decoder.selectedAudioStream = chosen;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong OEFFmpegPlayerViewController *s = weakSelf;
                if (s) {
                    [s freeBufferedFrames];
                    [s showNotice:@"已切换音轨"];
                }
            });
        });
    } else if (actionSheet.tag == 9200) {
        // Button 0 is "off"; streams start at button 1.
        [self applySubtitleTrack:buttonIndex - 1];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (_activeSheet == actionSheet) _activeSheet = nil;
}

#pragma mark - Subtitles (Emby server SRT → overlay)

- (void)applySubtitleTrack:(NSInteger)index
{
    _selectedSubtitleTrack = index;
    if (index < 0 || index >= (NSInteger)self.subtitleTracks.count) {
        [self clearSubtitleCues];
        return;
    }
    [self loadSubtitleTrackAtIndex:index];
}

- (void)loadSubtitleTrackAtIndex:(NSInteger)index
{
    OEStreamInfo *info = self.subtitleTracks[index];
    NSString *msId = info.mediaSourceId.length ? info.mediaSourceId : self.mediaSourceId;
    if (!self.itemId.length || !msId.length || !info.index.length) {
        [self showNotice:@"该字幕缺少必要信息，无法加载"];
        return;
    }

    NSUInteger generation = ++_subtitleLoadGeneration;
    [_subtitleOverlay setSubtitleText:@"正在加载字幕…"];
    __weak OEFFmpegPlayerViewController *weakSelf = self;
    [[OEEmbyAPIClient sharedClient] fetchSubtitleForItem:self.itemId
                                          mediaSourceId:msId
                                            streamIndex:[info.index integerValue]
                                                 format:@"srt"
                                             completion:^(id result, NSError *error) {
        __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf->_subtitleLoadGeneration) return;
        NSString *text = [result isKindOfClass:[NSString class]] ? result : nil;
        if (error || !text.length) {
            [strongSelf showNotice:@"字幕加载失败"];
            return;
        }
        NSArray *cues = [OESubtitleParser parse:text];
        if (!cues.count) {
            [strongSelf showNotice:@"字幕格式无法解析"];
            return;
        }
        strongSelf->_subtitleCues = cues;
        [strongSelf showNotice:@"字幕已开启"];
    }];
}

- (void)updateSubtitleDisplay
{
    if (!_subtitleOverlay) return;
    if (!_subtitleCues.count) return;
    NSString *text = [OESubtitleParser textForTime:_moviePosition inCues:_subtitleCues];
    [_subtitleOverlay setSubtitleText:text];
}

- (void)clearSubtitleCues
{
    ++_subtitleLoadGeneration;
    _subtitleCues = nil;
    if (_subtitleOverlay) [_subtitleOverlay setSubtitleText:nil];
}

- (void)showNotice:(NSString *)text
{
    if (!_subtitleOverlay || !text.length) return;
    NSUInteger generation = ++_subtitleNoticeGeneration;
    [_subtitleOverlay setSubtitleText:text];
    __weak OEFFmpegPlayerViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFFNoticeDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong OEFFmpegPlayerViewController *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf->_subtitleNoticeGeneration) return;
        [strongSelf->_subtitleOverlay setSubtitleText:nil];
    });
}

#pragma mark - Failure

- (void)showFailureAndOfferExit:(NSString *)message
{
    NSString *text = [NSString stringWithFormat:@"%@\n\n可退出后使用“播放（HLS 转码）”按钮观看。", message ?: @"FFmpeg 无法打开该流"];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"直接播放失败"
                                                    message:text
                                                   delegate:self
                                          cancelButtonTitle:@"退出"
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [self doneDidTouch];
}

@end
