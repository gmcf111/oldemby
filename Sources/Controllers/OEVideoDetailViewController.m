#import "OEVideoDetailViewController.h"
#import "Models/OEEmbyItem.h"
#import "Models/OECastItem.h"
#import "Models/OETranscodeSettings.h"
#import "Models/OESRTSubtitleParser.h"
#import "Services/OEEmbyAPIClient.h"
#import "Services/OEImageCache.h"
#import "Views/OETheme.h"
#import "Views/OECastStripView.h"
#import "Views/OEErrorAlertView.h"
#import "Views/OEMediaInfoView.h"
#import "Views/OESubtitleOverlayView.h"
#import "Views/OEStreamSelectionView.h"
#import "Constants.h"
#import <MediaPlayer/MediaPlayer.h>

static const CGFloat kDetailSidePadding = 12.0;
static const CGFloat kDetailCoverWidthFraction = 0.42;
static const CGFloat kDetailCoverMaxWidth = 200.0;
static const CGFloat kDetailCoverMinWidth = 120.0;
static const CGFloat kDetailCoverMinHeight = 180.0;
static const CGFloat kDetailCoverMaxHeight = 300.0;
static const CGFloat kCastStripHeight = 132.0;
static const CGFloat kOverlayButtonSize = 40.0;
static const CGFloat kOverlayButtonSpacing = 12.0;
static const CGFloat kOverlayBottomMargin = 52.0; // below system volume bar
static const CGFloat kOverlayAutoHideDelay = 5.0;

@interface OEVideoDetailViewController () <OEStreamSelectionDelegate>
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
@property (nonatomic, strong) UILabel *mediaInfoHeaderLabel;
@property (nonatomic, strong) OEMediaInfoView *mediaInfoView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) MPMoviePlayerViewController *activePlayerController;
@property (nonatomic, assign) BOOL playerBecamePlayable;
@property (nonatomic, assign) BOOL fetchingStream;
@property (nonatomic, assign) BOOL dismissingPlayer;
@property (nonatomic, assign) NSUInteger playRequestGeneration;
@property (nonatomic, assign) NSInteger pendingFinishReason;
@property (nonatomic, strong) NSError *pendingPlaybackError;
@property (nonatomic, copy) NSString *activeStreamURLString;
@property (nonatomic, assign) BOOL currentPlaybackIsDirect;
@property (nonatomic, strong) NSArray *audioStreams;
@property (nonatomic, strong) NSArray *subtitleStreams;
@property (nonatomic, strong) NSString *activeMediaSourceId;
@property (nonatomic, assign) NSInteger selectedAudioIndex;
@property (nonatomic, assign) NSInteger selectedSubtitleIndex;
@property (nonatomic, strong) OESubtitleOverlayView *subtitleOverlay;
@property (nonatomic, strong) NSTimer *subtitleTimer;
@property (nonatomic, strong) NSArray *parsedSubtitleCues;
@property (nonatomic, assign) BOOL subtitleLoading;
@property (nonatomic, strong) UIButton *audioButton;
@property (nonatomic, strong) UIButton *subtitleButton;
@property (nonatomic, strong) UIView *overlayControlsView;
@property (nonatomic, assign) BOOL overlayControlsVisible;
@property (nonatomic, strong) NSTimer *overlayHideTimer;
@property (nonatomic, strong) OEStreamSelectionView *streamSelectionView;
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
    self.selectedAudioIndex = -1;
    self.selectedSubtitleIndex = -1;

    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.showsVerticalScrollIndicator = YES;
    [self.view addSubview:_scrollView];

    _contentView = [[UIView alloc] initWithFrame:CGRectZero];
    [_scrollView addSubview:_contentView];

    self.cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.cover.contentMode = UIViewContentModeScaleAspectFill;
    self.cover.clipsToBounds = YES;
    self.cover.layer.borderWidth = 1.0;
    [self.contentView addSubview:self.cover];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.titleLabel.text = self.item.name;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.numberOfLines = 2;
    [self.contentView addSubview:self.titleLabel];

    self.overviewHeaderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.overviewHeaderLabel.font = [UIFont boldSystemFontOfSize:13];
    self.overviewHeaderLabel.text = @"简介";
    self.overviewHeaderLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:self.overviewHeaderLabel];

    self.overviewLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.overviewLabel.font = [UIFont systemFontOfSize:15];
    self.overviewLabel.numberOfLines = 0;
    self.overviewLabel.text = self.item.overview ?: @"暂无简介";
    self.overviewLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:self.overviewLabel];

    self.castHeaderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.castHeaderLabel.font = [UIFont boldSystemFontOfSize:14];
    self.castHeaderLabel.text = @"演职人员";
    self.castHeaderLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:self.castHeaderLabel];

    self.castStrip = [[OECastStripView alloc] initWithFrame:CGRectZero];
    self.castStrip.casts = @[];
    [self.contentView addSubview:self.castStrip];

    self.mediaInfoHeaderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.mediaInfoHeaderLabel.font = [UIFont boldSystemFontOfSize:14];
    self.mediaInfoHeaderLabel.text = @"媒体信息";
    self.mediaInfoHeaderLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:self.mediaInfoHeaderLabel];

    self.mediaInfoView = [[OEMediaInfoView alloc] initWithFrame:CGRectZero];
    [self.contentView addSubview:self.mediaInfoView];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [OETheme accentColor];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:self.statusLabel];

    self.playBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playBtn.backgroundColor = [OETheme accentColor];
    self.playBtn.layer.cornerRadius = 7;
    self.playBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.playBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.playBtn setTitle:[self playButtonTitle] forState:UIControlStateNormal];
    [self.playBtn addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.playBtn];

    self.directPlayBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.directPlayBtn.backgroundColor = [UIColor clearColor];
    self.directPlayBtn.layer.cornerRadius = 7;
    self.directPlayBtn.layer.borderWidth = 1.0;
    self.directPlayBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.directPlayBtn setTitle:@"不转码直接播放" forState:UIControlStateNormal];
    [self.directPlayBtn addTarget:self action:@selector(directPlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.directPlayBtn];

    [self applyTheme];

    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:self.item width:400 height:600];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image) { self.cover.image = image; }];

    [self loadCasts];
    [self loadMediaInfo];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:kNotificationThemeDidChange object:nil];
}

- (void)loadCasts {
    NSString *castItemId = self.item.seriesId.length ? self.item.seriesId : self.item.itemId;
    NSString *fallbackItemId = self.item.seriesId.length ? self.item.itemId : nil;
    [[OEEmbyAPIClient sharedClient] fetchCastsForItem:castItemId completion:^(id result, NSError *error) {
        if (error) return;
        if ([result isKindOfClass:[NSArray class]] && ((NSArray *)result).count > 0) {
            self.castStrip.casts = result;
            [self.view setNeedsLayout];
            return;
        }
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

- (void)loadMediaInfo {
    NSString *itemId = self.item.itemId;
    if (!itemId.length) return;
    [[OEEmbyAPIClient sharedClient] fetchMediaSourcesForItem:itemId completion:^(id result, NSError *error) {
        if (error || ![result isKindOfClass:[NSArray class]]) return;
        self.mediaInfoView.mediaSources = result;
        [self parseStreamInfoFromMediaSources:result];
        [self.view setNeedsLayout];
    }];
}

#pragma mark - Stream Parsing

- (void)parseStreamInfoFromMediaSources:(NSArray *)mediaSources {
    NSMutableArray *audio = [NSMutableArray array];
    NSMutableArray *subs = [NSMutableArray array];
    NSString *firstMediaSourceId = nil;
    for (NSDictionary *source in mediaSources) {
        if (![source isKindOfClass:[NSDictionary class]]) continue;
        if (!firstMediaSourceId.length) {
            NSString *sid = [source[@"Id"] isKindOfClass:[NSString class]] ? source[@"Id"] : nil;
            if (sid.length) firstMediaSourceId = sid;
        }
        NSArray *streams = source[@"MediaStreams"];
        if (![streams isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *stream in streams) {
            if (![stream isKindOfClass:[NSDictionary class]]) continue;
            NSString *type = [stream[@"Type"] isKindOfClass:[NSString class]] ? stream[@"Type"] : @"";
            if ([type isEqualToString:@"Audio"]) {
                [audio addObject:[self streamInfoFromDictionary:stream]];
            } else if ([type isEqualToString:@"Subtitle"]) {
                OEStreamInfo *info = [self streamInfoFromDictionary:stream];
                BOOL isText = [stream[@"IsTextSubtitleStream"] boolValue];
                NSString *codec = [stream[@"Codec"] isKindOfClass:[NSString class]] ? [stream[@"Codec"] lowercaseString] : @"";
                // Expand the list to include all text subtitle formats our
                // parser can handle. "sub" alone is ambiguous (can be image-
                // based SubViewer or text MicroDVD), so only include "subrip"
                // and "subviewer" which are text-based.
                BOOL knownTextCodec = ([codec rangeOfString:@"srt"].location != NSNotFound) ||
                                      ([codec rangeOfString:@"vtt"].location != NSNotFound) ||
                                      ([codec rangeOfString:@"ass"].location != NSNotFound) ||
                                      ([codec rangeOfString:@"ssa"].location != NSNotFound) ||
                                      ([codec rangeOfString:@"subrip"].location != NSNotFound) ||
                                      ([codec rangeOfString:@"subviewer"].location != NSNotFound) ||
                                      ([codec rangeOfString:@"webvtt"].location != NSNotFound) ||
                                      ([codec rangeOfString:@"lrc"].location != NSNotFound) ||
                                      ([codec rangeOfString:@"microdvd"].location != NSNotFound) ||
                                      [codec isEqualToString:@"sub"];
                if (!isText && !knownTextCodec) continue;
                info.mediaSourceId = firstMediaSourceId;
                [subs addObject:info];
            }
        }
    }
    self.audioStreams = audio;
    self.subtitleStreams = subs;
    self.activeMediaSourceId = firstMediaSourceId;
    for (NSInteger i = 0; i < (NSInteger)audio.count; i++) {
        if (((OEStreamInfo *)audio[i]).isDefault) { self.selectedAudioIndex = i; break; }
    }
    self.selectedSubtitleIndex = -1;
}

- (OEStreamInfo *)streamInfoFromDictionary:(NSDictionary *)stream {
    OEStreamInfo *info = [[OEStreamInfo alloc] init];
    id rawIndex = stream[@"Index"];
    if ([rawIndex isKindOfClass:[NSNumber class]]) info.index = [NSString stringWithFormat:@"%ld", (long)[rawIndex integerValue]];
    else if ([rawIndex isKindOfClass:[NSString class]]) info.index = rawIndex;
    NSString *title = [stream[@"DisplayTitle"] isKindOfClass:[NSString class]] ? stream[@"DisplayTitle"] : nil;
    NSString *codec = [stream[@"Codec"] isKindOfClass:[NSString class]] ? [stream[@"Codec"] lowercaseString] : @"";
    NSString *lang = [stream[@"Language"] isKindOfClass:[NSString class]] ? stream[@"Language"] : @"";
    info.language = lang; info.codec = codec;
    info.isDefault = [stream[@"IsDefault"] boolValue];
    info.isExternal = [stream[@"IsExternal"] boolValue];
    id deliveryUrl = stream[@"DeliveryUrl"];
    if ([deliveryUrl isKindOfClass:[NSString class]]) info.deliveryUrl = deliveryUrl;
    NSMutableString *dt = [NSMutableString string];
    if (lang.length) [dt appendFormat:@"%@ ", [self languageDisplay:lang]];
    if (codec.length) [dt appendFormat:@"%@ ", codec.uppercaseString];
    if (info.isDefault) [dt appendString:@"(默认)"];
    while ([dt hasSuffix:@" "]) [dt deleteCharactersInRange:NSMakeRange(dt.length - 1, 1)];
    if (dt.length == 0 && title.length) dt = [title mutableCopy];
    info.title = dt.length ? [dt copy] : (title ?: @"未知");
    return info;
}

- (NSString *)languageDisplay:(NSString *)code {
    if (!code.length) return @"未知";
    NSDictionary *map = @{
        @"jpn": @"日语", @"ja": @"日语", @"chi": @"中文", @"zh": @"中文", @"zho": @"中文",
        @"eng": @"英语", @"en": @"英语", @"kor": @"韩语", @"ko": @"韩语",
        @"fra": @"法语", @"fr": @"法语", @"ger": @"德语", @"de": @"德语", @"deu": @"德语",
        @"spa": @"西班牙语", @"es": @"西班牙语", @"ita": @"意大利语", @"it": @"意大利语",
        @"tha": @"泰语", @"th": @"泰语", @"rus": @"俄语", @"ru": @"俄语",
        @"por": @"葡萄牙语", @"pt": @"葡萄牙语",
    };
    return map[[code lowercaseString]] ?: code;
}

#pragma mark - Theme

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
    self.mediaInfoHeaderLabel.textColor = [OETheme primaryTextColor];
    [self.mediaInfoView applyTheme];
    self.statusLabel.textColor = [OETheme accentColor];
    self.directPlayBtn.layer.borderColor = [OETheme accentColor].CGColor;
    [self.directPlayBtn setTitleColor:[OETheme accentColor] forState:UIControlStateNormal];
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat margin = kDetailSidePadding;
    CGFloat coverWidth = w * kDetailCoverWidthFraction;
    coverWidth = MAX(kDetailCoverMinWidth, MIN(coverWidth, kDetailCoverMaxWidth));
    CGFloat aspectRatio = self.item.primaryImageAspectRatio > 0 ? self.item.primaryImageAspectRatio : (2.0 / 3.0);
    CGFloat coverHeight = coverWidth / (aspectRatio > 0 ? aspectRatio : (2.0 / 3.0));
    coverHeight = MAX(kDetailCoverMinHeight, MIN(coverHeight, kDetailCoverMaxHeight));
    CGFloat topY = margin;
    self.cover.frame = CGRectMake(margin, topY, coverWidth, coverHeight);
    CGFloat rightX = margin + coverWidth + margin;
    CGFloat rightWidth = w - rightX - margin;
    CGFloat titleHeight = 38;
    self.titleLabel.frame = CGRectMake(rightX, topY, rightWidth, titleHeight);
    CGFloat ovHdrY = CGRectGetMaxY(self.titleLabel.frame) + 6;
    self.overviewHeaderLabel.frame = CGRectMake(rightX, ovHdrY, rightWidth, 18);
    CGFloat ovY = CGRectGetMaxY(self.overviewHeaderLabel.frame) + 4;
    CGFloat ovHeight = coverHeight - (titleHeight + 6 + 18 + 4);
    CGSize textSize = [self.overviewLabel.text sizeWithFont:self.overviewLabel.font
                                           constrainedToSize:CGSizeMake(rightWidth, CGFLOAT_MAX)
                                               lineBreakMode:NSLineBreakByWordWrapping];
    ovHeight = MAX(ceil(textSize.height), ovHeight);
    self.overviewLabel.frame = CGRectMake(rightX, ovY, rightWidth, ovHeight);
    CGFloat afterTopY = MAX(CGRectGetMaxY(self.cover.frame), CGRectGetMaxY(self.overviewLabel.frame)) + 16;
    self.castHeaderLabel.frame = CGRectMake(margin, afterTopY, w - 2 * margin, 20);
    CGFloat castY = CGRectGetMaxY(self.castHeaderLabel.frame) + 6;
    self.castStrip.frame = CGRectMake(margin, castY, w - 2 * margin, kCastStripHeight);
    CGFloat mediaInfoY = CGRectGetMaxY(self.castStrip.frame) + 16;
    self.mediaInfoHeaderLabel.frame = CGRectMake(margin, mediaInfoY, w - 2 * margin, 20);
    CGFloat miY = CGRectGetMaxY(self.mediaInfoHeaderLabel.frame) + 6;
    CGFloat miH = [self.mediaInfoView heightForWidth:w - 2 * margin];
    self.mediaInfoView.frame = CGRectMake(margin, miY, w - 2 * margin, miH);
    CGFloat playY = CGRectGetMaxY(self.mediaInfoView.frame) + 16;
    self.statusLabel.frame = CGRectMake(margin, playY, w - 2 * margin, 18);
    playY += 22;
    self.playBtn.frame = CGRectMake(margin, playY, w - 2 * margin, 46);
    playY += 46 + 8;
    self.directPlayBtn.frame = CGRectMake(margin, playY, w - 2 * margin, 40);
    playY += 40 + margin;
    self.scrollView.frame = self.view.bounds;
    self.contentView.frame = CGRectMake(0, 0, w, playY);
    self.scrollView.contentSize = CGSizeMake(w, playY);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.activePlayerController) [self.playBtn setTitle:[self playButtonTitle] forState:UIControlStateNormal];
    if (!self.activePlayerController) self.directPlayBtn.enabled = YES;
}

#pragma mark - Playback

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
    OEEmbyAPIClient *client = [OEEmbyAPIClient sharedClient];
    NSString *itemId = self.item.itemId;
    OEAPICompletion handler = ^(id result, NSError *error) {
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
        if (!url) {
            [self showPlaybackError:@"服务器返回了无效的播放地址"
                             detail:streamURL.length ? [NSString stringWithFormat:@"地址：%@", streamURL] : @"服务器未返回任何地址"];
            return;
        }
        if (self.activePlayerController || self.dismissingPlayer) return;
        NSLog(@"[OldEmby] video stream URL: %@", streamURL);
        BOOL isDirect = [streamURL rangeOfString:@"Static=true" options:NSCaseInsensitiveSearch].location != NSNotFound;
        self.currentPlaybackIsDirect = isDirect;
        [self presentPlayerForURL:url isDirectStream:isDirect baseURLString:streamURL];
    };
    fetchBlock(client, itemId, handler);
}

- (void)removePlayerObserversForPlayer:(MPMoviePlayerController *)player {
    if (!player) return;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:MPMoviePlayerLoadStateDidChangeNotification object:player];
    [center removeObserver:self name:MPMoviePlayerPlaybackStateDidChangeNotification object:player];
    [center removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:player];
}

- (void)presentPlayerForURL:(NSURL *)url {
    [self presentPlayerForURL:url isDirectStream:NO baseURLString:nil];
}

- (void)presentPlayerForURL:(NSURL *)url isDirectStream:(BOOL)isDirectStream {
    [self presentPlayerForURL:url isDirectStream:isDirectStream baseURLString:nil];
}

- (void)presentPlayerForURL:(NSURL *)url isDirectStream:(BOOL)isDirectStream baseURLString:(NSString *)baseURLString {
    if (!url || self.activePlayerController || self.dismissingPlayer) return;
    self.activeStreamURLString = baseURLString ?: url.absoluteString;
    @try {
        MPMoviePlayerViewController *controller = [[MPMoviePlayerViewController alloc] initWithContentURL:url];
        if (!controller || !controller.moviePlayer) {
            [self showPlaybackError:@"无法初始化系统播放器" detail:[NSString stringWithFormat:@"地址：%@", url.absoluteString]];
            return;
        }
        self.activePlayerController = controller;
        self.playerBecamePlayable = NO;
        self.dismissingPlayer = NO;
        controller.moviePlayer.movieSourceType = isDirectStream ? MPMovieSourceTypeFile : MPMovieSourceTypeStreaming;
        controller.moviePlayer.shouldAutoplay = NO;
        controller.moviePlayer.controlStyle = MPMovieControlStyleFullscreen;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieLoadStateChanged:) name:MPMoviePlayerLoadStateDidChangeNotification object:controller.moviePlayer];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlaybackStateChanged:) name:MPMoviePlayerPlaybackStateDidChangeNotification object:controller.moviePlayer];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:controller.moviePlayer];
        self.statusLabel.text = @"正在缓冲视频…";
        [self presentMoviePlayerViewControllerAnimated:controller];
        @try {
            [controller.moviePlayer prepareToPlay];
        } @catch (NSException *inner) {
            NSLog(@"[OldEmby] prepareToPlay exception: %@", inner);
        }
        [self setupOverlayControls];
        [self startSubtitlePlayback];
    } @catch (NSException *e) {
        NSLog(@"[OldEmby] presentPlayerForURL exception: %@", e);
        @try { [self.activePlayerController.moviePlayer stop]; } @catch (NSException *stopEx) {
            NSLog(@"[OldEmby] cleanup stop exception: %@", stopEx);
        }
        [self removePlayerObserversForPlayer:self.activePlayerController.moviePlayer];
        self.activePlayerController = nil;
        self.dismissingPlayer = NO;
        NSString *msg = [NSString stringWithFormat:@"系统播放器无法打开此视频流：%@", e.reason ?: e.name ?: @"未知异常"];
        [self showPlaybackError:msg detail:[self playbackFailureDetail]];
    }
}

- (void)movieLoadStateChanged:(NSNotification *)notification {
    MPMoviePlayerController *player = notification.object;
    if (player != self.activePlayerController.moviePlayer || self.dismissingPlayer) return;
    if (player.loadState & MPMovieLoadStatePlayable) {
        self.playerBecamePlayable = YES;
        self.statusLabel.text = @"视频已就绪";
        @try { [player play]; } @catch (NSException *playEx) {
            NSLog(@"[OldEmby] player play exception: %@", playEx);
        }
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
    [self cleanupOverlayAndSubtitles];
    if (self.pendingFinishReason == MPMovieFinishReasonPlaybackError) {
        NSString *msg = self.pendingPlaybackError.localizedDescription;
        if (!msg.length) msg = @"系统播放器无法播放该 HLS 流，请检查 Emby 转码日志与 HLS 版本设置";
        [self showPlaybackError:msg detail:[self playbackFailureDetail]];
    } else if (self.pendingFinishReason == MPMovieFinishReasonUserExited) {
        self.statusLabel.text = @"已退出播放";
    } else if (self.pendingFinishReason == MPMovieFinishReasonPlaybackEnded) {
        self.statusLabel.text = @"播放结束";
    } else if (!self.playerBecamePlayable) {
        NSString *detail = self.pendingPlaybackError.localizedDescription;
        [self showPlaybackError:detail.length
            ? [NSString stringWithFormat:@"播放器未取得可播放数据：%@", detail]
            : @"播放器未取得可播放数据（请确认 Emby 转码为 H.264+AAC 的 HLS，且 HLS 版本兼容 iOS 6）"
                         detail:[self playbackFailureDetail]];
    } else {
        self.statusLabel.text = @"播放结束";
    }
    self.pendingPlaybackError = nil;
    if (controller) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            @try { [strongSelf.activePlayerController.moviePlayer stop]; } @catch (NSException *e) {
                NSLog(@"[OldEmby] deferred stop exception: %@", e);
            }
            strongSelf.activePlayerController = nil;
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
    @try { [player stop]; } @catch (NSException *stopEx) {
        NSLog(@"[OldEmby] player stop exception: %@", stopEx);
    }
    @try {
        [self dismissMoviePlayerViewControllerAnimated];
    } @catch (NSException *dismissEx) {
        NSLog(@"[OldEmby] dismissMoviePlayer exception: %@", dismissEx);
        self.dismissingPlayer = NO;
        self.activePlayerController = nil;
    }
}

- (void)showPlaybackError:(NSString *)message {
    [self showPlaybackError:message detail:nil];
}

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
    if (self.currentPlaybackIsDirect) {
        [context appendString:@"\n模式：不转码直接播放"];
    } else {
        [context appendFormat:@"\n模式：%@", settings.directPlay ? @"直接播放" : @"转码"];
        if (!settings.directPlay) {
            [context appendFormat:@" %@ / %ld kbps", [settings resolutionString], (long)settings.maxVideoBitrate / 1000];
        }
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

#pragma mark - Overlay Controls

- (void)setupOverlayControls {
    MPMoviePlayerController *player = self.activePlayerController.moviePlayer;
    if (!player) return;
    UIView *playerView = self.activePlayerController.view;
    if (!playerView) return;

    // Persistent container for audio/subtitle buttons — always visible,
    // not affected by the auto-hide timer.
    _overlayControlsView = [[UIView alloc] initWithFrame:CGRectZero];
    _overlayControlsView.backgroundColor = [UIColor clearColor];
    _overlayControlsView.userInteractionEnabled = YES;
    [playerView addSubview:_overlayControlsView];

    _audioButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _audioButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    _audioButton.layer.cornerRadius = kOverlayButtonSize / 2;
    _audioButton.titleLabel.font = [UIFont systemFontOfSize:11];
    _audioButton.titleLabel.numberOfLines = 2;
    _audioButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [_audioButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_audioButton setTitle:@"音轨" forState:UIControlStateNormal];
    [_audioButton addTarget:self action:@selector(audioButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_overlayControlsView addSubview:_audioButton];

    _subtitleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _subtitleButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    _subtitleButton.layer.cornerRadius = kOverlayButtonSize / 2;
    _subtitleButton.titleLabel.font = [UIFont systemFontOfSize:11];
    _subtitleButton.titleLabel.numberOfLines = 2;
    _subtitleButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [_subtitleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_subtitleButton setTitle:@"字幕" forState:UIControlStateNormal];
    [_subtitleButton addTarget:self action:@selector(subtitleButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_overlayControlsView addSubview:_subtitleButton];

    // Add subtitle overlay on top of the player view
    _subtitleOverlay = [[OESubtitleOverlayView alloc] initWithFrame:CGRectZero];
    [playerView addSubview:_subtitleOverlay];

    [self layoutOverlayControls];

    // Buttons are permanently visible — no auto-hide.
    _overlayControlsVisible = YES;
}

- (void)layoutOverlayControls {
    UIView *playerView = self.activePlayerController.view;
    if (!playerView) return;
    CGFloat w = playerView.bounds.size.width;
    CGFloat h = playerView.bounds.size.height;
    if (w < 1 || h < 1) return;

    // Place the two buttons at the bottom center, below the system
    // volume bar and playback controls.
    CGFloat totalW = 2 * kOverlayButtonSize + kOverlayButtonSpacing;
    CGFloat startX = (w - totalW) / 2.0;
    CGFloat y = h - kOverlayButtonSize - kOverlayBottomMargin;
    _overlayControlsView.frame = CGRectMake(startX, y, totalW, kOverlayButtonSize);
    _audioButton.frame = CGRectMake(0, 0, kOverlayButtonSize, kOverlayButtonSize);
    _subtitleButton.frame = CGRectMake(kOverlayButtonSize + kOverlayButtonSpacing, 0, kOverlayButtonSize, kOverlayButtonSize);
    _subtitleOverlay.frame = CGRectMake(0, 0, w, h);
}

// Overlay controls are now permanently visible — no show/hide/toggle.
// The methods are kept as no-ops for backwards compatibility in case
// other code paths still call them.
- (void)showOverlayControls { _overlayControlsVisible = YES; }
- (void)hideOverlayControls { _overlayControlsVisible = YES; }
- (void)toggleOverlayControls { _overlayControlsVisible = YES; }
- (void)resetOverlayHideTimer { /* no-op */ }

- (void)audioButtonTapped {
    [self showStreamSelectionForAudio:YES];
}

- (void)subtitleButtonTapped {
    [self showStreamSelectionForAudio:NO];
}

#pragma mark - Stream Selection

- (void)showStreamSelectionForAudio:(BOOL)isAudio {
    UIWindow *window = self.activePlayerController.view.window;
    if (!window) window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;

    _streamSelectionView = [[OEStreamSelectionView alloc] initWithFrame:CGRectZero
                                                           audioStreams:self.audioStreams
                                                        subtitleStreams:self.subtitleStreams
                                                     selectedAudioIndex:self.selectedAudioIndex
                                                  selectedSubtitleIndex:self.selectedSubtitleIndex
                                                            delegate:self];
    [_streamSelectionView showInWindow:window];
}

- (void)streamSelectionView:(OEStreamSelectionView *)view
       didSelectAudioIndex:(NSInteger)audioIndex {
    NSLog(@"[OldEmby] selected audio index: %ld", (long)audioIndex);
    self.selectedAudioIndex = audioIndex;
    [self switchStreamsWithNewAudio:audioIndex subtitle:self.selectedSubtitleIndex];
}

- (void)streamSelectionView:(OEStreamSelectionView *)view
      didSelectSubtitleIndex:(NSInteger)subtitleIndex {
    NSLog(@"[OldEmby] selected subtitle index: %ld", (long)subtitleIndex);
    self.selectedSubtitleIndex = subtitleIndex;
    [self switchStreamsWithNewAudio:self.selectedAudioIndex subtitle:subtitleIndex];
}

- (void)streamSelectionViewDidDismiss:(OEStreamSelectionView *)view {
    self.streamSelectionView = nil;
}

#pragma mark - Stream Switching

- (void)switchStreamsWithNewAudio:(NSInteger)audioIndex subtitle:(NSInteger)subtitleIndex {
    // Only works for HLS transcode playback (not direct stream).
    // For direct stream, we cannot switch audio/subtitle via URL params;
    // the user would need to re-play with transcode mode.
    if (self.currentPlaybackIsDirect) {
        // For direct stream, we can still load external subtitles.
        if (subtitleIndex >= 0 && subtitleIndex < (NSInteger)self.subtitleStreams.count) {
            [self loadSubtitleForIndex:subtitleIndex];
        } else {
            [self clearSubtitles];
        }
        return;
    }

    // For HLS transcode, rebuild the URL with AudioStreamIndex and SubtitleStreamIndex.
    NSString *baseURL = self.activeStreamURLString;
    if (!baseURL.length) return;

    OEEmbyAPIClient *client = [OEEmbyAPIClient sharedClient];
    NSInteger audioStreamIndex = -1;
    if (audioIndex >= 0 && audioIndex < (NSInteger)self.audioStreams.count) {
        OEStreamInfo *info = self.audioStreams[audioIndex];
        audioStreamIndex = [info.index integerValue];
    }

    NSInteger subStreamIndex = -1;
    if (subtitleIndex >= 0 && subtitleIndex < (NSInteger)self.subtitleStreams.count) {
        OEStreamInfo *info = self.subtitleStreams[subtitleIndex];
        subStreamIndex = [info.index integerValue];
    }

    NSString *newURL = [client streamURLWithAudioIndex:audioStreamIndex
                                         subtitleIndex:subStreamIndex
                                          fromBaseURL:baseURL
                                               itemId:self.item.itemId];
    if (!newURL.length) {
        NSLog(@"[OldEmby] failed to rebuild stream URL with audio/subtitle index");
        return;
    }

    NSURL *url = [NSURL URLWithString:newURL];
    if (!url) {
        NSLog(@"[OldEmby] rebuilt URL is not parseable: %@", newURL);
        return;
    }

    // Remember current playback position for resume.
    NSTimeInterval currentPos = 0;
    @try { currentPos = self.activePlayerController.moviePlayer.currentPlaybackTime; } @catch (NSException *e) {
        NSLog(@"[OldEmby] currentPlaybackTime exception: %@", e);
    }

    // Remove old observers before swapping content URL.
    MPMoviePlayerController *player = self.activePlayerController.moviePlayer;
    [self removePlayerObserversForPlayer:player];
    [self clearSubtitleTimer];

    // Set the new content URL and restart.
    [player setContentURL:url];
    self.activeStreamURLString = newURL;
    self.playerBecamePlayable = NO;

    // Re-add observers for the new playback session.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieLoadStateChanged:) name:MPMoviePlayerLoadStateDidChangeNotification object:player];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlaybackStateChanged:) name:MPMoviePlayerPlaybackStateDidChangeNotification object:player];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:player];

    @try { [player prepareToPlay]; } @catch (NSException *e) {
        NSLog(@"[OldEmby] prepareToPlay after stream switch: %@", e);
    }

    // Restore playback position after the player becomes playable.
    if (currentPos > 0) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.activePlayerController) return;
            MPMoviePlayerController *p = strongSelf.activePlayerController.moviePlayer;
            if (p && p.loadState & MPMovieLoadStatePlayable) {
                @try { p.currentPlaybackTime = currentPos; } @catch (NSException *e) {
                    NSLog(@"[OldEmby] seek after switch: %@", e);
                }
            }
        });
    }

    // Load external subtitle if selected (for display alongside burned-in subs).
    if (subtitleIndex >= 0 && subtitleIndex < (NSInteger)self.subtitleStreams.count) {
        [self loadSubtitleForIndex:subtitleIndex];
    } else {
        [self clearSubtitles];
    }
}

#pragma mark - Subtitle Loading & Display

- (void)startSubtitlePlayback {
    [self clearSubtitles];
    if (self.selectedSubtitleIndex >= 0 && self.selectedSubtitleIndex < (NSInteger)self.subtitleStreams.count) {
        [self loadSubtitleForIndex:self.selectedSubtitleIndex];
    }
}

- (void)loadSubtitleForIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.subtitleStreams.count) return;
    OEStreamInfo *info = self.subtitleStreams[index];
    if (!info.index.length || !info.mediaSourceId.length) {
        NSLog(@"[OldEmby] cannot load subtitle: missing index or mediaSourceId");
        return;
    }

    self.subtitleLoading = YES;
    [self clearSubtitleTimer];

    OEEmbyAPIClient *client = [OEEmbyAPIClient sharedClient];
    NSInteger streamIdx = [info.index integerValue];
    // Always request SRT from the server: Emby's subtitle endpoint transcodes
    // all text subtitle formats (ASS, SSA, VTT, etc.) to SRT on the fly.
    // However, some server versions may ignore the format and return the
    // original text, so the parser auto-detects the actual format.
    NSString *format = @"srt";

    [client fetchSubtitleForItem:self.item.itemId
                   mediaSourceId:info.mediaSourceId
                     streamIndex:streamIdx
                          format:format
                      completion:^(id result, NSError *error) {
        self.subtitleLoading = NO;
        if (error || ![result isKindOfClass:[NSString class]]) {
            NSLog(@"[OldEmby] subtitle fetch failed: %@", error);
            return;
        }
        NSString *subtitleText = (NSString *)result;
        if (!subtitleText.length) {
            NSLog(@"[OldEmby] subtitle text is empty");
            return;
        }
        // Auto-detect format and parse (handles SRT, VTT, ASS/SSA, LRC).
        self.parsedSubtitleCues = [OESubtitleParser parse:subtitleText];
        if (!self.parsedSubtitleCues.count) {
            NSLog(@"[OldEmby] no cues parsed from subtitle text (format may be unsupported)");
            return;
        }
        [self startSubtitleTimer];
    }];
}

- (void)startSubtitleTimer {
    [self clearSubtitleTimer];
    self.subtitleTimer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                         target:self
                                                       selector:@selector(updateSubtitleDisplay)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)clearSubtitleTimer {
    [self.subtitleTimer invalidate];
    self.subtitleTimer = nil;
}

- (void)updateSubtitleDisplay {
    if (!self.subtitleOverlay || !self.parsedSubtitleCues.count) return;
    MPMoviePlayerController *player = self.activePlayerController.moviePlayer;
    if (!player) return;
    NSTimeInterval currentTime = 0;
    @try { currentTime = player.currentPlaybackTime; } @catch (NSException *e) { return; }
    if (currentTime <= 0) return;
    OESubtitleCue *cue = [OESubtitleParser cueForTime:currentTime inCues:self.parsedSubtitleCues];
    if (cue) {
        [self.subtitleOverlay setSubtitleText:cue.text];
    } else {
        [self.subtitleOverlay setSubtitleText:nil];
    }
}

- (void)clearSubtitles {
    [self clearSubtitleTimer];
    self.parsedSubtitleCues = nil;
    if (self.subtitleOverlay) [self.subtitleOverlay setSubtitleText:nil];
}

- (void)cleanupOverlayAndSubtitles {
    [self clearSubtitles];
    [self.overlayHideTimer invalidate];
    self.overlayHideTimer = nil;
    if (_streamSelectionView) {
        [_streamSelectionView dismiss];
        _streamSelectionView = nil;
    }
    if (_overlayControlsView) {
        [_overlayControlsView removeFromSuperview];
        _overlayControlsView = nil;
    }
    if (_subtitleOverlay) {
        [_subtitleOverlay removeFromSuperview];
        _subtitleOverlay = nil;
    }
    _audioButton = nil;
    _subtitleButton = nil;
}

- (void)dealloc {
    ++self.playRequestGeneration;
    MPMoviePlayerController *moviePlayer = self.activePlayerController.moviePlayer;
    [self removePlayerObserversForPlayer:moviePlayer];
    [self cleanupOverlayAndSubtitles];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (moviePlayer) {
        @try { [moviePlayer stop]; } @catch (NSException *e) {
            NSLog(@"[OldEmby] dealloc stop exception: %@", e);
        }
    }
    MPMoviePlayerViewController *controller = self.activePlayerController;
    if (controller) {
        dispatch_async(dispatch_get_main_queue(), ^{ [controller class]; });
    }
}

@end