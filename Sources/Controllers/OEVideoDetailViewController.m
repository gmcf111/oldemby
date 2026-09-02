#import "OEVideoDetailViewController.h"
#import "Models/OEEmbyItem.h"
#import "Models/OECastItem.h"
#import "Models/OETranscodeSettings.h"
#import "Services/OEEmbyAPIClient.h"
#import "Services/OEImageCache.h"
#import "Views/OETheme.h"
#import "Views/OECastStripView.h"
#import "Views/OEErrorAlertView.h"
#import "Constants.h"
#import <MediaPlayer/MediaPlayer.h>

// Layout constants
static const CGFloat kDetailSidePadding = 12.0;
static const CGFloat kDetailCoverWidthFraction = 0.42;  // cover occupies ~42% of screen width
static const CGFloat kDetailCoverMaxWidth = 200.0;
static const CGFloat kDetailCoverMinWidth = 120.0;
static const CGFloat kDetailCoverMinHeight = 180.0;
static const CGFloat kDetailCoverMaxHeight = 300.0;
static const CGFloat kCastStripHeight = 132.0;

@interface OEVideoDetailViewController ()
@property (nonatomic, strong) OEEmbyItem *item;
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *overviewLabel;
@property (nonatomic, strong) UILabel *overviewHeaderLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UIButton *directPlayBtn;
@property (nonatomic, strong) UILabel *castHeaderLabel;
@property (nonatomic, strong) OECastStripView *castStrip;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) MPMoviePlayerViewController *activePlayerController;
@property (nonatomic, assign) BOOL playerBecamePlayable;
@property (nonatomic, assign) BOOL fetchingStream;
@property (nonatomic, assign) BOOL dismissingPlayer;
@property (nonatomic, assign) NSUInteger playRequestGeneration;
@property (nonatomic, assign) NSInteger pendingFinishReason;
@property (nonatomic, strong) NSError *pendingPlaybackError;
// Kept for diagnostics: shown (and copyable) in the failure sheet.
@property (nonatomic, copy) NSString *activeStreamURLString;
@end

@implementation OEVideoDetailViewController

- (instancetype)initWithItem:(OEEmbyItem *)item {
    if ((self = [super init])) _item = item;
    return self;
}

- (NSString *)playButtonTitle {
    OETranscodeSettings *settings = [OETranscodeSettings sharedSettings];
    if (settings.directPlay) return @"直接播放";
    return [NSString stringWithFormat:@"播放（HLS 转码 %@ / %ld Mbps）", [settings resolutionString], (long)settings.maxVideoBitrate / 1000000];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [OETheme prepareViewController:self];
    self.title = self.item.name;

    // ScrollView to hold all content (cover+overview+casts+play button)
    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.showsVerticalScrollIndicator = YES;
    [self.view addSubview:_scrollView];

    _contentView = [[UIView alloc] initWithFrame:CGRectZero];
    [_scrollView addSubview:_contentView];

    // Cover image (left side)
    self.cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.cover.contentMode = UIViewContentModeScaleAspectFill;
    self.cover.clipsToBounds = YES;
    self.cover.layer.borderWidth = 1.0;
    [self.contentView addSubview:self.cover];

    // Title label (right side, above overview)
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.titleLabel.text = self.item.name;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.numberOfLines = 2;
    [self.contentView addSubview:self.titleLabel];

    // Overview header
    self.overviewHeaderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.overviewHeaderLabel.font = [UIFont boldSystemFontOfSize:13];
    self.overviewHeaderLabel.text = @"简介";
    self.overviewHeaderLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:self.overviewHeaderLabel];

    // Overview label (right side)
    self.overviewLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.overviewLabel.font = [UIFont systemFontOfSize:15];
    self.overviewLabel.numberOfLines = 0;
    self.overviewLabel.text = self.item.overview ?: @"暂无简介";
    self.overviewLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:self.overviewLabel];

    // Cast header label
    self.castHeaderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.castHeaderLabel.font = [UIFont boldSystemFontOfSize:14];
    self.castHeaderLabel.text = @"演职人员";
    self.castHeaderLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:self.castHeaderLabel];

    // Cast strip view
    self.castStrip = [[OECastStripView alloc] initWithFrame:CGRectZero];
    self.castStrip.casts = @[];
    [self.contentView addSubview:self.castStrip];

    // Status label
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [OETheme accentColor];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:self.statusLabel];

    // Play button
    self.playBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playBtn.backgroundColor = [OETheme accentColor];
    self.playBtn.layer.cornerRadius = 7;
    self.playBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.playBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.playBtn setTitle:[self playButtonTitle] forState:UIControlStateNormal];
    [self.playBtn addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.playBtn];

    // Direct play button — requests the original file with no transcoding.
    // Useful for content already in a device-decodable format (older TV
    // recordings, MPEG-2 / H.264 mp4) where HLS transcode may fail or add
    // unnecessary overhead.
    self.directPlayBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.directPlayBtn.backgroundColor = [UIColor clearColor];
    self.directPlayBtn.layer.cornerRadius = 7;
    self.directPlayBtn.layer.borderWidth = 1.0;
    self.directPlayBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.directPlayBtn setTitle:@"不转码直接播放" forState:UIControlStateNormal];
    [self.directPlayBtn addTarget:self action:@selector(directPlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.directPlayBtn];

    [self applyTheme];

    // Load cover image — larger resolution since cover is bigger now
    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:self.item width:400 height:600];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image) { self.cover.image = image; }];

    // Fetch cast list
    [self loadCasts];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:kNotificationThemeDidChange object:nil];
}

- (void)loadCasts {
    NSString *castItemId = self.item.seriesId.length ? self.item.seriesId : self.item.itemId;
    NSString *fallbackItemId = self.item.seriesId.length ? self.item.itemId : nil;
    [[OEEmbyAPIClient sharedClient] fetchCastsForItem:castItemId completion:^(id result, NSError *error) {
        if (error) {
            // Silently ignore cast errors - not critical for playback
            return;
        }
        if ([result isKindOfClass:[NSArray class]] && ((NSArray *)result).count > 0) {
            self.castStrip.casts = result;
            [self.view setNeedsLayout];
            return;
        }
        // First attempt returned no people: if we queried by seriesId, retry
        // with the item's own Id — some Emby versions only attach People to
        // the episode/movie item, not to the series root.
        if (fallbackItemId.length) {
            [[OEEmbyAPIClient sharedClient] fetchCastsForItem:fallbackItemId completion:^(id r2, NSError *e2) {
                if (e2) return;
                if ([r2 isKindOfClass:[NSArray class]]) {
                    self.castStrip.casts = r2;
                    [self.view setNeedsLayout];
                }
            }];
        }
    }];
}

- (void)applyTheme {
    self.view.backgroundColor = [OETheme libraryBackgroundColor];
    self.scrollView.backgroundColor = [OETheme libraryBackgroundColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    self.cover.backgroundColor = [OETheme imagePlaceholderColor];
    self.cover.layer.borderColor = [OETheme separatorColor].CGColor;
    self.titleLabel.textColor = [OETheme primaryTextColor];
    self.overviewHeaderLabel.textColor = [OETheme accentColor];
    self.overviewLabel.textColor = [OETheme secondaryTextColor];
    self.castHeaderLabel.textColor = [OETheme primaryTextColor];
    self.statusLabel.textColor = [OETheme accentColor];
    self.directPlayBtn.layer.borderColor = [OETheme accentColor].CGColor;
    [self.directPlayBtn setTitleColor:[OETheme accentColor] forState:UIControlStateNormal];
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat w = self.view.bounds.size.width;
    CGFloat margin = kDetailSidePadding;

    // Calculate cover dimensions: ~42% of screen width, clamped
    CGFloat coverWidth = w * kDetailCoverWidthFraction;
    coverWidth = MAX(kDetailCoverMinWidth, MIN(coverWidth, kDetailCoverMaxWidth));
    // Cover aspect ratio: use 2:3 for movie posters, or item's aspect ratio
    CGFloat aspectRatio = self.item.primaryImageAspectRatio > 0 ? self.item.primaryImageAspectRatio : (2.0 / 3.0);
    // For posters, aspect < 1 means portrait; use it to calculate height
    CGFloat coverHeight = coverWidth / (aspectRatio > 0 ? aspectRatio : (2.0 / 3.0));
    coverHeight = MAX(kDetailCoverMinHeight, MIN(coverHeight, kDetailCoverMaxHeight));

    // Top section: cover on left, title+overview on right
    CGFloat topY = margin;
    self.cover.frame = CGRectMake(margin, topY, coverWidth, coverHeight);

    CGFloat rightX = margin + coverWidth + margin;
    CGFloat rightWidth = w - rightX - margin;

    // Title at top of right column
    CGFloat titleHeight = 38;
    self.titleLabel.frame = CGRectMake(rightX, topY, rightWidth, titleHeight);

    // Overview header
    CGFloat ovHdrY = CGRectGetMaxY(self.titleLabel.frame) + 6;
    self.overviewHeaderLabel.frame = CGRectMake(rightX, ovHdrY, rightWidth, 18);

    // Overview label: fill remaining right column space below cover top area
    CGFloat ovY = CGRectGetMaxY(self.overviewHeaderLabel.frame) + 4;
    CGFloat ovHeight = coverHeight - (titleHeight + 6 + 18 + 4);
    // Calculate actual needed height using iOS 6 compatible API
    CGSize textSize = [self.overviewLabel.text sizeWithFont:self.overviewLabel.font
                                           constrainedToSize:CGSizeMake(rightWidth, CGFLOAT_MAX)
                                               lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat neededHeight = ceil(textSize.height);
    // The overview should at least fill the remaining cover area, but can be taller
    ovHeight = MAX(neededHeight, ovHeight);
    self.overviewLabel.frame = CGRectMake(rightX, ovY, rightWidth, ovHeight);

    // After cover+overview section, the Y is the max of cover bottom and overview bottom
    CGFloat afterTopY = MAX(CGRectGetMaxY(self.cover.frame), CGRectGetMaxY(self.overviewLabel.frame)) + 16;

    // Cast section
    self.castHeaderLabel.frame = CGRectMake(margin, afterTopY, w - 2 * margin, 20);
    CGFloat castY = CGRectGetMaxY(self.castHeaderLabel.frame) + 6;
    self.castStrip.frame = CGRectMake(margin, castY, w - 2 * margin, kCastStripHeight);

    // Play button + status + direct play button
    CGFloat playY = CGRectGetMaxY(self.castStrip.frame) + 16;
    self.statusLabel.frame = CGRectMake(margin, playY, w - 2 * margin, 18);
    playY += 22;
    self.playBtn.frame = CGRectMake(margin, playY, w - 2 * margin, 46);
    playY += 46 + 8;
    self.directPlayBtn.frame = CGRectMake(margin, playY, w - 2 * margin, 40);
    playY += 40 + margin;

    // Set content size for scrolling
    self.scrollView.frame = self.view.bounds;
    self.contentView.frame = CGRectMake(0, 0, w, playY);
    self.scrollView.contentSize = CGSizeMake(w, playY);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.activePlayerController) [self.playBtn setTitle:[self playButtonTitle] forState:UIControlStateNormal];
    if (!self.activePlayerController) self.directPlayBtn.enabled = YES;
}

- (void)playTapped {
    [self beginStreamFetch:^(OEEmbyAPIClient *client, NSString *itemId, OEAPICompletion cb) {
        [client fetchStreamURLForItem:itemId isAudio:NO completion:cb];
    } statusText:@"正在请求 HLS 转码流…"];
}

- (void)directPlayTapped {
    if (self.fetchingStream || self.activePlayerController || self.dismissingPlayer) return;
    [self beginStreamFetch:^(OEEmbyAPIClient *client, NSString *itemId, OEAPICompletion cb) {
        [client fetchDirectStreamURLForItem:itemId isAudio:NO completion:cb];
    } statusText:@"正在请求直接播放地址…"];
}

- (void)beginStreamFetch:(void(^)(OEEmbyAPIClient *, NSString *, OEAPICompletion))fetchBlock
              statusText:(NSString *)statusText {
    if (self.fetchingStream || self.activePlayerController || self.dismissingPlayer) return;
    NSUInteger generation = ++self.playRequestGeneration;
    self.fetchingStream = YES;
    self.statusLabel.text = statusText;
    [self.playBtn setTitle:@"正在获取播放地址…" forState:UIControlStateNormal];
    self.playBtn.enabled = NO;
    self.directPlayBtn.enabled = NO;
    fetchBlock([OEEmbyAPIClient sharedClient], self.item.itemId, ^(id result, NSError *error) {
        if (generation != self.playRequestGeneration) return;
        self.fetchingStream = NO;
        self.playBtn.enabled = YES;
        self.directPlayBtn.enabled = YES;
        [self.playBtn setTitle:[self playButtonTitle] forState:UIControlStateNormal];
        if (error) {
            NSString *detail = [NSString stringWithFormat:@"错误域：%@\n错误码：%ld", error.domain ?: @"-", (long)error.code];
            [self showPlaybackError:error.localizedDescription ?: @"请求播放地址失败" detail:detail];
            return;
        }
        NSString *streamURL = [result isKindOfClass:[NSString class]] ? result : nil;
        NSURL *url = [NSURL URLWithString:streamURL];
        // The API client already validated and repaired the URL. Requiring a
        // non-empty scheme/host here as well used to reject playable streams,
        // so only bail out when NSURL produced nothing at all.
        if (!url) {
            [self showPlaybackError:@"服务器返回了无效的播放地址"
                             detail:streamURL.length ? [NSString stringWithFormat:@"地址：%@", streamURL] : @"服务器未返回任何地址"];
            return;
        }
        if (self.activePlayerController || self.dismissingPlayer) return;
        NSLog(@"[OldEmby] video stream URL: %@", streamURL);
        [self presentPlayerForURL:url];
    }];
}

- (void)removePlayerObserversForPlayer:(MPMoviePlayerController *)player {
    if (!player) return;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:MPMoviePlayerLoadStateDidChangeNotification object:player];
    [center removeObserver:self name:MPMoviePlayerPlaybackStateDidChangeNotification object:player];
    [center removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:player];
}

- (void)presentPlayerForURL:(NSURL *)url {
    if (!url || self.activePlayerController || self.dismissingPlayer) return;
    self.activeStreamURLString = url.absoluteString;
    MPMoviePlayerViewController *controller = [[MPMoviePlayerViewController alloc] initWithContentURL:url];
    if (!controller || !controller.moviePlayer) { [self showPlaybackError:@"无法初始化系统播放器" detail:[NSString stringWithFormat:@"地址：%@", url.absoluteString]]; return; }
    self.activePlayerController = controller;
    self.playerBecamePlayable = NO;
    self.dismissingPlayer = NO;
    controller.moviePlayer.movieSourceType = MPMovieSourceTypeStreaming;
    controller.moviePlayer.shouldAutoplay = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieLoadStateChanged:) name:MPMoviePlayerLoadStateDidChangeNotification object:controller.moviePlayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlaybackStateChanged:) name:MPMoviePlayerPlaybackStateDidChangeNotification object:controller.moviePlayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:controller.moviePlayer];
    self.statusLabel.text = @"正在缓冲视频…";
    [controller.moviePlayer prepareToPlay];
    [self presentMoviePlayerViewControllerAnimated:controller];
}

- (void)movieLoadStateChanged:(NSNotification *)notification {
    MPMoviePlayerController *player = notification.object;
    if (player != self.activePlayerController.moviePlayer || self.dismissingPlayer) return;
    if (player.loadState & MPMovieLoadStatePlayable) {
        self.playerBecamePlayable = YES;
        self.statusLabel.text = @"视频已就绪";
        [player play];
    } else if (player.loadState & MPMovieLoadStateStalled) {
        self.statusLabel.text = @"视频缓冲中…";
    }
}

- (void)moviePlaybackStateChanged:(NSNotification *)notification {
    MPMoviePlayerController *player = notification.object;
    if (player != self.activePlayerController.moviePlayer || self.dismissingPlayer) return;
    if (player.playbackState == MPMoviePlaybackStatePlaying) self.statusLabel.text = @"正在播放";
    else if (player.playbackState == MPMoviePlaybackStateInterrupted) self.statusLabel.text = @"播放被中断";
}

- (NSString *)playbackFailureDetail {
    NSMutableString *detail = [NSMutableString string];
    if (self.activeStreamURLString.length) [detail appendFormat:@"地址：%@", self.activeStreamURLString];
    NSError *error = self.pendingPlaybackError;
    if (error) {
        if (detail.length) [detail appendString:@"\n"];
        [detail appendFormat:@"错误域：%@\n错误码：%ld", error.domain ?: @"-", (long)error.code];
        NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
        if ([underlying isKindOfClass:[NSError class]]) {
            [detail appendFormat:@"\n底层错误：%@ (%ld)", underlying.domain ?: @"-", (long)underlying.code];
            if (underlying.localizedDescription.length) [detail appendFormat:@"\n%@", underlying.localizedDescription];
        }
    }
    return detail;
}

- (void)finishDismissingPlayer {
    MPMoviePlayerViewController *controller = self.activePlayerController;
    self.dismissingPlayer = NO;
    if (self.pendingFinishReason == MPMovieFinishReasonPlaybackError) {
        NSString *msg = self.pendingPlaybackError.localizedDescription;
        if (!msg.length) msg = @"系统播放器无法播放该 HLS 流，请检查 Emby 转码日志与 HLS 版本设置";
        [self showPlaybackError:msg detail:[self playbackFailureDetail]];
    } else if (self.pendingFinishReason == MPMovieFinishReasonUserExited) {
        self.statusLabel.text = @"已退出播放";
    } else if (self.pendingFinishReason == MPMovieFinishReasonPlaybackEnded) {
        self.statusLabel.text = @"播放结束";
    } else if (!self.playerBecamePlayable) {
        // The player gave up before reaching a playable state without an
        // explicit error. Surface whatever the system attached (if anything)
        // so the failure reason is visible instead of a generic status line.
        NSString *detail = self.pendingPlaybackError.localizedDescription;
        [self showPlaybackError:detail.length
            ? [NSString stringWithFormat:@"播放器未取得可播放数据：%@", detail]
            : @"播放器未取得可播放数据（请确认 Emby 转码为 H.264+AAC 的 HLS，且 HLS 版本兼容 iOS 6）"
                         detail:[self playbackFailureDetail]];
    } else {
        self.statusLabel.text = @"播放结束";
    }
    self.pendingPlaybackError = nil;
    // Hold the controller for one more run-loop pass. iOS 6 finalizes
    // MPMoviePlayerController's view/layer teardown on the next CA commit; if
    // the strong property above was the last retain, releasing it now leaves
    // that commit messaging a freed object -> EXC_BAD_ACCESS on the main run
    // loop observer. Clearing the property on the next tick avoids that.
    if (controller) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.activePlayerController = nil;
        });
    } else {
        self.activePlayerController = nil;
    }
}

- (void)movieFinished:(NSNotification *)notification {
    MPMoviePlayerController *player = notification.object;
    if (player != self.activePlayerController.moviePlayer || self.dismissingPlayer) return;
    self.dismissingPlayer = YES;
    self.pendingFinishReason = [notification.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] integerValue];
    self.pendingPlaybackError = notification.userInfo[@"error"];
    [self removePlayerObserversForPlayer:player];
    [player stop];
    [self dismissMoviePlayerViewControllerAnimated];
}

- (void)showPlaybackError:(NSString *)message {
    [self showPlaybackError:message detail:nil];
}

// detail carries the raw material worth pasting into a bug report (stream URL,
// server body, NSError domain/code). It is shown in a selectable text view.
- (void)showPlaybackError:(NSString *)message detail:(NSString *)detail {
    self.statusLabel.text = @"播放失败";
    NSMutableString *context = [NSMutableString string];
    if (detail.length) [context appendString:detail];
    if (self.item.name.length) {
        if (context.length) [context appendString:@"\n\n"];
        [context appendFormat:@"项目：%@", self.item.name];
    }
    if (self.item.itemId.length) [context appendFormat:@"\nItemId：%@", self.item.itemId];
    OETranscodeSettings *settings = [OETranscodeSettings sharedSettings];
    [context appendFormat:@"\n模式：%@", settings.directPlay ? @"直接播放" : @"转码"];
    if (!settings.directPlay) {
        [context appendFormat:@" %@ / %ld kbps", [settings resolutionString], (long)settings.maxVideoBitrate / 1000];
    }
    [OEErrorAlertView showWithTitle:@"播放失败" message:message ?: @"未知错误" detail:context];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.dismissingPlayer) [self finishDismissingPlayer];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (!self.fetchingStream || !(self.isMovingFromParentViewController || self.isBeingDismissed || self.navigationController.isBeingDismissed)) return;
    ++self.playRequestGeneration;
    self.fetchingStream = NO;
}

- (void)dealloc {
    ++self.playRequestGeneration;
    [self removePlayerObserversForPlayer:self.activePlayerController.moviePlayer];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    MPMoviePlayerViewController *controller = self.activePlayerController;
    // Same deferred-release rationale as finishDismissingPlayer: let iOS 6's
    // MPMoviePlayer teardown commit finish before the controller is
    // deallocated. The block captures the controller (not self, which is being
    // deallocated) and releases it on the next run-loop tick.
    if (controller) {
        dispatch_async(dispatch_get_main_queue(), ^{ [controller class]; });
    }
}

@end
