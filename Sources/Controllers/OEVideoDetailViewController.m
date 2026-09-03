#import "OEVideoDetailViewController.h"
#import "Models/OEEmbyItem.h"
#import "Models/OECastItem.h"
#import "Models/OETranscodeSettings.h"
#import "Models/OESRTSubtitleParser.h"
#import "Models/OEStreamInfo.h"
#import "Services/OEEmbyAPIClient.h"
#import "Services/OEImageCache.h"
#import "Views/OETheme.h"
#import "Views/OECastStripView.h"
#import "Views/OEErrorAlertView.h"
#import "Views/OEMediaInfoView.h"
#import "Views/OESubtitleOverlayView.h"
#import "Constants.h"
#import <MediaPlayer/MediaPlayer.h>
#import <math.h>

static const CGFloat kDetailSidePadding = 12.0;
static const CGFloat kDetailCoverWidthFraction = 0.42;
static const CGFloat kDetailCoverMaxWidth = 200.0;
static const CGFloat kDetailCoverMinWidth = 120.0;
static const CGFloat kDetailCoverMinHeight = 90.0;
static const CGFloat kDetailCoverMaxHeight = 200.0;
static const CGFloat kCastStripHeight = 132.0;
static const CGFloat kOverlayButtonSize = 32.0;
static const CGFloat kOverlayBottomMargin = 48.0; // fallback: above the system control bar
static const CGFloat kOverlaySideMargin = 6.0; // fallback: left/right edge margin
static const CGFloat kOverlayButtonGap = 8.0; // gap between volume slider and buttons
static const CGFloat kTransportButtonWidth = 40.0;
static const CGFloat kTransportButtonHeight = 32.0;
static const CGFloat kTransportButtonGap = 4.0;
static const NSTimeInterval kControlSyncInterval = 0.2;
// Tags telling the two UIActionSheets apart in the shared delegate callback.
static const NSInteger kAudioSheetTag = 8001;
static const NSInteger kSubtitleSheetTag = 8002;
// How long a transient notice (e.g. a subtitle load failure) stays on screen.
static const NSTimeInterval kSubtitleNoticeDuration = 2.5;

@interface OEVideoDetailViewController () <UIActionSheetDelegate>
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
@property (nonatomic, strong) UIButton *prevEpisodeButton;
@property (nonatomic, strong) UIButton *skipBackButton;
@property (nonatomic, strong) UIButton *skipForwardButton;
@property (nonatomic, strong) UIButton *nextEpisodeButton;
@property (nonatomic, assign) BOOL overlayControlsVisible;
@property (nonatomic, strong) NSTimer *controlSyncTimer;
@property (nonatomic, weak) UIView *systemVolumeView;
// The system bottom control bar our buttons are attached into, and the
// player's own play/pause button used as the transport row's anchor.
@property (nonatomic, weak) UIView *systemControlBar;
@property (nonatomic, weak) UIControl *systemPlayPauseButton;
@property (nonatomic, assign) BOOL transportClusterLogged;
@property (nonatomic, assign) CGRect lastVolumeFrame;
// The sheet currently on screen, kept so teardown can dismiss it: UIActionSheet
// holds its delegate unretained and would message a freed controller.
@property (nonatomic, strong) UIActionSheet *activeSheet;
@property (nonatomic, assign) NSUInteger subtitleLoadGeneration;
@property (nonatomic, assign) NSUInteger subtitleNoticeGeneration;
// Graphic subtitle tracks dropped while parsing, so an empty picker can say why.
@property (nonatomic, assign) NSInteger skippedImageSubtitleCount;
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
    self.cover.contentMode = UIViewContentModeScaleAspectFit;
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

    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:self.item width:400 height:225];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image) { self.cover.image = image; }];

    [self loadCasts];
    [self loadMediaInfo];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:kNotificationThemeDidChange object:nil];
}

- (void)loadCasts {
    // Episode switching reuses this page, so late responses must not install
    // the previous episode's data.
    OEEmbyItem *itemAtCall = self.item;
    NSString *castItemId = self.item.seriesId.length ? self.item.seriesId : self.item.itemId;
    NSString *fallbackItemId = self.item.seriesId.length ? self.item.itemId : nil;
    [[OEEmbyAPIClient sharedClient] fetchCastsForItem:castItemId completion:^(id result, NSError *error) {
        if (self.item != itemAtCall) return;
        if (error) return;
        if ([result isKindOfClass:[NSArray class]] && ((NSArray *)result).count > 0) {
            self.castStrip.casts = result;
            [self.view setNeedsLayout];
            return;
        }
        if (fallbackItemId.length) {
            [[OEEmbyAPIClient sharedClient] fetchCastsForItem:fallbackItemId completion:^(id r2, NSError *e2) {
                if (self.item != itemAtCall) return;
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
        if (![self.item.itemId isEqualToString:itemId]) return;
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
    NSInteger skippedImageSubs = 0;
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
                if (!isText && !knownTextCodec) { skippedImageSubs++; continue; }
                info.mediaSourceId = firstMediaSourceId;
                [subs addObject:info];
            }
        }
    }
    self.audioStreams = audio;
    self.subtitleStreams = subs;
    self.skippedImageSubtitleCount = skippedImageSubs;
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
    NSString *displayTitle = [stream[@"DisplayTitle"] isKindOfClass:[NSString class]] ? stream[@"DisplayTitle"] : nil;
    // The track's own title ("简体&英文", "Forced", a fansub group name) is often
    // the only thing separating two subtitles in the same language.
    NSString *trackTitle = [stream[@"Title"] isKindOfClass:[NSString class]] ? stream[@"Title"] : nil;
    NSString *codec = [stream[@"Codec"] isKindOfClass:[NSString class]] ? [stream[@"Codec"] lowercaseString] : @"";
    NSString *lang = [stream[@"Language"] isKindOfClass:[NSString class]] ? stream[@"Language"] : @"";
    info.language = lang; info.codec = codec;
    info.isDefault = [stream[@"IsDefault"] boolValue];
    info.isExternal = [stream[@"IsExternal"] boolValue];
    id deliveryUrl = stream[@"DeliveryUrl"];
    if ([deliveryUrl isKindOfClass:[NSString class]]) info.deliveryUrl = deliveryUrl;
    NSMutableString *dt = [NSMutableString string];
    if (lang.length) [dt appendFormat:@"%@ ", [self languageDisplay:lang]];
    if (trackTitle.length) [dt appendFormat:@"%@ ", trackTitle];
    if (codec.length) [dt appendFormat:@"%@ ", codec.uppercaseString];
    if ([stream[@"IsForced"] boolValue]) [dt appendString:@"[强制] "];
    if (info.isExternal) [dt appendString:@"[外挂] "];
    if (info.isDefault) [dt appendString:@"(默认)"];
    while ([dt hasSuffix:@" "]) [dt deleteCharactersInRange:NSMakeRange(dt.length - 1, 1)];
    if (dt.length == 0 && displayTitle.length) dt = [displayTitle mutableCopy];
    info.title = dt.length ? [dt copy] : (displayTitle ?: @"未知");
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
    // Default to 16:9 landscape for episode thumbnails; use the real
    // aspect ratio from the server when available.
    CGFloat aspectRatio = self.item.primaryImageAspectRatio > 0 ? self.item.primaryImageAspectRatio : 1.78;
    CGFloat coverHeight = coverWidth / (aspectRatio > 0 ? aspectRatio : 1.78);
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

    _subtitleOverlay = [[OESubtitleOverlayView alloc] initWithFrame:playerView.bounds];
    _subtitleOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [playerView addSubview:_subtitleOverlay];

    // Transparent buttons: once attached into the system control bar they read
    // as part of it, and they fade, slide and hide together with it.
    _audioButton = [self controlBarButtonWithTitle:@"音轨" action:@selector(audioButtonTapped)];
    _subtitleButton = [self controlBarButtonWithTitle:@"字幕" action:@selector(subtitleButtonTapped)];
    _prevEpisodeButton = [self controlBarButtonWithTitle:@"上一集" action:@selector(prevEpisodeTapped)];
    _nextEpisodeButton = [self controlBarButtonWithTitle:@"下一集" action:@selector(nextEpisodeTapped)];
    _skipBackButton = [self controlBarButtonWithTitle:@"快退\n30秒" action:@selector(skipBackTapped)];
    _skipForwardButton = [self controlBarButtonWithTitle:@"快进\n30秒" action:@selector(skipForwardTapped)];

    // Poll the system control bar (via its volume slider) to discover where to
    // attach the buttons and to keep them anchored as the bar reshuffles.
    _overlayControlsVisible = NO;
    _lastVolumeFrame = CGRectZero;
    _transportClusterLogged = NO;
    [self.controlSyncTimer invalidate];
    self.controlSyncTimer = [NSTimer scheduledTimerWithTimeInterval:kControlSyncInterval
                                                             target:self
                                                           selector:@selector(syncOverlayWithSystemControls)
                                                           userInfo:nil
                                                            repeats:YES];
    [self updateEpisodeButtonStates];
    [self syncOverlayWithSystemControls];
}

- (UIButton *)controlBarButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    // Plain text on the control bar: no background, no border, no rounded
    // square. Every background source is cleared so nothing can paint a box.
    button.backgroundColor = [UIColor clearColor];
    button.opaque = NO;
    button.layer.backgroundColor = [UIColor clearColor].CGColor;
    button.layer.borderWidth = 0;
    button.titleLabel.font = [UIFont systemFontOfSize:10];
    button.titleLabel.numberOfLines = 2;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.35] forState:UIControlStateDisabled];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    // Shown once anchored inside the control bar.
    button.hidden = YES;
    return button;
}

- (UIView *)findVolumeControlInView:(UIView *)view {
    for (UIView *sub in view.subviews) {
        NSString *className = NSStringFromClass([sub class]);
        if ([className rangeOfString:@"Volume" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return sub;
        }
        UIView *found = [self findVolumeControlInView:sub];
        if (found) return found;
    }
    return nil;
}

// The bottom control bar is the deepest ancestor of the volume slider that
// still spans (nearly) the whole player width; anything higher up is the
// full-screen controls overlay hosting both bars.
- (UIView *)findControlBarForVolumeView:(UIView *)volumeView playerView:(UIView *)playerView {
    if (!volumeView || !playerView) return nil;
    CGFloat playerWidth = playerView.bounds.size.width;
    for (UIView *v = volumeView.superview; v && v != playerView; v = v.superview) {
        if (v.bounds.size.width >= playerWidth * 0.9) return v;
    }
    return volumeView.superview;
}

- (void)syncOverlayWithSystemControls {
    if (!_subtitleOverlay) return;
    UIView *playerView = _subtitleOverlay.superview;
    if (!playerView) return;

    UIView *volumeView = _systemVolumeView;
    if (!volumeView || !volumeView.window) {
        volumeView = [self findVolumeControlInView:playerView];
        _systemVolumeView = volumeView;
    }
    UIView *bar = _systemControlBar;
    if (volumeView && (!bar || !bar.window || ![volumeView isDescendantOfView:bar])) {
        bar = [self findControlBarForVolumeView:volumeView playerView:playerView];
        _systemControlBar = bar;
        _transportClusterLogged = NO;
    }
    BOOL visible = [self systemControlsVisible:volumeView playerView:playerView];

    if (bar) {
        // Buttons live inside the system control bar: they inherit its
        // fade/slide/hide automatically, so there is no separate visibility
        // logic for them here.
        [self attachControlBarButtons];
        [self updateTransportClusterInBar:bar];
        [self layoutControlBarButtons];
    } else {
        // Fallback: the bar could not be located, so host the buttons on the
        // player view and track the system bar's visibility ourselves. This is
        // only the safety net; the normal path above needs no sync logic.
        [self attachFallbackButtonsToView:playerView];
        [self layoutFallbackButtonsInView:playerView volumeView:volumeView];
        CGFloat alpha = visible ? 1.0 : 0.0;
        _audioButton.alpha = alpha;
        _subtitleButton.alpha = alpha;
        _prevEpisodeButton.alpha = alpha;
        _nextEpisodeButton.alpha = alpha;
        _skipBackButton.alpha = alpha;
        _skipForwardButton.alpha = alpha;
    }

    // The subtitle inset still needs the bar's visibility and position.
    CGRect volumeFrame = CGRectZero;
    if (volumeView) {
        volumeFrame = [volumeView convertRect:volumeView.bounds toView:_subtitleOverlay];
    }
    if (visible != _overlayControlsVisible || !CGRectEqualToRect(volumeFrame, _lastVolumeFrame)) {
        _overlayControlsVisible = visible;
        _lastVolumeFrame = volumeFrame;
        [self updateSubtitleInsetForControlsVisible:visible];
    }
    // The player reshuffles its own layers when the control bar toggles, which
    // can bury the subtitle overlay. It does not intercept touches, so keeping
    // it frontmost is safe.
    if (playerView.subviews.lastObject != _subtitleOverlay) {
        [playerView bringSubviewToFront:_subtitleOverlay];
    }
}

// Attach the six buttons to the player view when the system control bar could
// not be found, so the controls stay available as a last resort.
- (void)attachFallbackButtonsToView:(UIView *)view {
    NSArray *buttons = [NSArray arrayWithObjects:_audioButton, _subtitleButton,
                        _prevEpisodeButton, _skipBackButton, _skipForwardButton,
                        _nextEpisodeButton, nil];
    for (UIButton *button in buttons) {
        if (button.superview != view) [view addSubview:button];
        button.hidden = NO;
    }
}

// Fallback layout on the player view: audio/subtitle flanking the volume
// slider if present, else the screen corners; transport buttons packed at the
// bottom-left so they never overlap the volume slider.
- (void)layoutFallbackButtonsInView:(UIView *)view volumeView:(UIView *)volumeView {
    CGFloat w = view.bounds.size.width;
    CGFloat h = view.bounds.size.height;
    if (w < 1 || h < 1) return;
    CGFloat btnSize = kOverlayButtonSize;
    CGFloat y = h - btnSize - kOverlayBottomMargin;
    CGFloat audioX = kOverlaySideMargin;
    CGFloat subtitleX = w - btnSize - kOverlaySideMargin;
    if (volumeView) {
        CGRect vf = [volumeView convertRect:volumeView.bounds toView:view];
        if (!CGRectIsEmpty(vf)) {
            y = CGRectGetMidY(vf) - btnSize / 2.0;
            audioX = CGRectGetMinX(vf) - kOverlayButtonGap - btnSize;
            subtitleX = CGRectGetMaxX(vf) + kOverlayButtonGap;
        }
    }
    audioX = MAX(2.0, audioX);
    subtitleX = MIN(w - btnSize - 2.0, subtitleX);
    _audioButton.frame = CGRectMake(audioX, y, btnSize, btnSize);
    _subtitleButton.frame = CGRectMake(subtitleX, y, btnSize, btnSize);

    CGFloat tw = kTransportButtonWidth;
    CGFloat th = kTransportButtonHeight;
    CGFloat ty = y + (btnSize - th) / 2.0;
    CGFloat step = tw + kTransportButtonGap;
    CGFloat startX = 2.0;
    _prevEpisodeButton.frame = CGRectMake(startX, ty, tw, th);
    _skipBackButton.frame = CGRectMake(startX + step, ty, tw, th);
    _skipForwardButton.frame = CGRectMake(startX + 2.0 * step, ty, tw, th);
    _nextEpisodeButton.frame = CGRectMake(startX + 3.0 * step, ty, tw, th);
    [self updateEpisodeButtonStates];
}

// Keep subtitle text clear of the system control bar while it is on screen.
- (void)updateSubtitleInsetForControlsVisible:(BOOL)visible {
    if (!_subtitleOverlay) return;
    CGFloat inset = 0;
    if (visible) {
        CGFloat h = _subtitleOverlay.bounds.size.height;
        if (!CGRectIsEmpty(_lastVolumeFrame) && h > 1) {
            // Sit above the volume slider, the lowest row of the control bar.
            inset = h - CGRectGetMinY(_lastVolumeFrame) + kOverlayButtonGap;
        } else {
            inset = kOverlayBottomMargin + kOverlayButtonSize;
        }
        if (inset < 0) inset = 0;
    }
    _subtitleOverlay.bottomInset = inset;
}

// The system control bar fades as a whole, so the volume slider is visible
// only if neither it nor any ancestor up to the player view is hidden/faded.
- (BOOL)systemControlsVisible:(UIView *)volumeView playerView:(UIView *)playerView {
    if (!volumeView) return YES;
    for (UIView *v = volumeView; v && v != playerView; v = v.superview) {
        if (v.hidden || v.alpha < 0.05) return NO;
    }
    return YES;
}

#pragma mark - Control Bar Attachment

- (BOOL)isOurControlBarButton:(UIView *)view {
    return view == _audioButton || view == _subtitleButton ||
           view == _prevEpisodeButton || view == _nextEpisodeButton ||
           view == _skipBackButton || view == _skipForwardButton;
}

- (void)attachControlBarButtons {
    UIView *bar = _systemControlBar;
    if (!bar) return;
    NSArray *buttons = [NSArray arrayWithObjects:_audioButton, _subtitleButton,
                        _prevEpisodeButton, _skipBackButton, _skipForwardButton,
                        _nextEpisodeButton, nil];
    for (UIButton *button in buttons) {
        if (button.superview != bar) [bar addSubview:button];
    }
    _audioButton.hidden = NO;
    _subtitleButton.hidden = NO;
}

// Every system transport control on the bar: the buttons left of the volume
// slider and on its horizontal band. The volume slider is the reliable anchor
// (it is always present and we already locate it); its left edge bounds the
// cluster and its vertical centre marks the transport row. The timeline
// scrubber cannot be used as the bound: on iOS 6-9 it sits on the row above
// and spans nearly the whole width, so its left edge is ~0 and would exclude
// every transport button — leaving an empty cluster and no play/pause anchor.
- (NSArray *)transportClusterInBar:(UIView *)bar {
    CGFloat limitX = bar.bounds.size.width * 0.5;
    CGFloat rowMidY = -1;
    if (_systemVolumeView) {
        CGRect volumeFrame = [_systemVolumeView convertRect:_systemVolumeView.bounds toView:bar];
        if (!CGRectIsEmpty(volumeFrame)) {
            limitX = CGRectGetMinX(volumeFrame);
            rowMidY = CGRectGetMidY(volumeFrame);
        }
    }
    NSMutableArray *cluster = [NSMutableArray array];
    [self collectTransportControlsFromView:bar bar:bar limitX:limitX rowMidY:rowMidY into:cluster];
    [cluster sortUsingComparator:^NSComparisonResult(UIControl *a, UIControl *b) {
        CGRect fa = [a convertRect:a.bounds toView:bar];
        CGRect fb = [b convertRect:b.bounds toView:bar];
        if (fa.origin.x < fb.origin.x) return NSOrderedAscending;
        if (fa.origin.x > fb.origin.x) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return cluster;
}

- (void)collectTransportControlsFromView:(UIView *)view
                                     bar:(UIView *)bar
                                  limitX:(CGFloat)limitX
                                 rowMidY:(CGFloat)rowMidY
                                    into:(NSMutableArray *)out {
    for (UIView *sub in view.subviews) {
        if ([self isOurControlBarButton:sub]) continue;
        if (_systemVolumeView && (sub == _systemVolumeView || [sub isDescendantOfView:_systemVolumeView])) continue;
        // Gather anything button-like: UIControl subclasses, and views whose
        // class name advertises a button (some private MP controls are plain
        // UIView subclasses rather than UIControl).
        NSString *lc = [NSStringFromClass([sub class]) lowercaseString];
        BOOL buttonish = [sub isKindOfClass:[UIControl class]] ||
                         [lc rangeOfString:@"button"].location != NSNotFound;
        if (!buttonish) {
            [self collectTransportControlsFromView:sub bar:bar limitX:limitX rowMidY:rowMidY into:out];
            continue;
        }
        if ([lc rangeOfString:@"slider"].location != NSNotFound ||
            [lc rangeOfString:@"scrubber"].location != NSNotFound) continue;
        CGRect frame = [sub convertRect:sub.bounds toView:bar];
        if (frame.size.height < 12 || frame.size.width < 12) continue;
        if (CGRectGetMidX(frame) >= limitX) continue;
        // Same row as the volume slider: filters out the scrubber row above
        // and the top bar's Done button even if the bar view spans the screen.
        if (rowMidY > 0 && fabsf((float)(CGRectGetMidY(frame) - rowMidY)) > 50.0f) continue;
        [out addObject:(UIControl *)sub];
    }
}

- (BOOL)label:(NSString *)label matchesAny:(NSArray *)words {
    if (!label.length) return NO;
    for (NSString *word in words) {
        if ([label rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

// Play/pause is identified by its accessibility label first; without labels,
// the button left after excluding the scan/skip ones wins, and failing that
// the cluster's middle button is the safest geometric guess.
- (UIControl *)playPauseButtonInCluster:(NSArray *)cluster {
    if (!cluster.count) return nil;
    NSMutableArray *unmarked = [NSMutableArray array];
    for (UIControl *control in cluster) {
        NSString *label = [[control accessibilityLabel] lowercaseString] ?: @"";
        if ([self label:label matchesAny:@[@"play", @"pause", @"播放", @"暂停", @"再生", @"一時停止"]]) {
            return control;
        }
        if (![self label:label matchesAny:@[@"scan", @"seek", @"forward", @"backward", @"rewind",
                                            @"next", @"previous", @"skip",
                                            @"快进", @"快退", @"下一个", @"上一个"]]) {
            [unmarked addObject:control];
        }
    }
    NSArray *pool = unmarked.count ? unmarked : cluster;
    NSInteger middle = (NSInteger)(pool.count - 1) / 2;
    return pool[middle];
}

- (void)logTransportCluster:(NSArray *)cluster inBar:(UIView *)bar {
    NSLog(@"[OldEmby] control bar %@ (%@) has %lu transport control(s):",
          NSStringFromClass([bar class]), NSStringFromCGRect(bar.frame), (unsigned long)cluster.count);
    for (UIControl *control in cluster) {
        CGRect frame = [control convertRect:control.bounds toView:bar];
        NSLog(@"[OldEmby]   %@ label=%@ frame=%@ playPause=%d",
              NSStringFromClass([control class]), [control accessibilityLabel] ?: @"-",
              NSStringFromCGRect(frame), control == _systemPlayPauseButton);
    }
    // When nothing was identified, dump the bar's subviews so the private
    // hierarchy can be diagnosed from a debug build's console.
    if (!cluster.count) {
        NSLog(@"[OldEmby] bar %@ subviews:", NSStringFromClass([bar class]));
        for (UIView *sub in bar.subviews) {
            NSLog(@"[OldEmby]   %@ frame=%@ label=%@",
                  NSStringFromClass([sub class]), NSStringFromCGRect(sub.frame),
                  [sub accessibilityLabel] ?: @"-");
        }
    }
}

// Identify the system play/pause button (our transport row's anchor) and hide
// only the scan/skip buttons we are confident about. We never hide an
// unlabelled button — if play/pause detection is wrong, hiding it would
// remove play/pause entirely, which is worse than a duplicated control.
- (void)updateTransportClusterInBar:(UIView *)bar {
    NSArray *cluster = [self transportClusterInBar:bar];

    UIControl *playPause = _systemPlayPauseButton;
    if (!playPause || !playPause.window || ![playPause isDescendantOfView:bar]) {
        playPause = [self playPauseButtonInCluster:cluster];
        _systemPlayPauseButton = playPause;
        if (!_transportClusterLogged) {
            _transportClusterLogged = YES;
            [self logTransportCluster:cluster inBar:bar];
        }
    }

    // Only hide buttons whose accessibility label identifies them as scan /
    // skip controls. Unlabelled buttons stay (one might be play/pause).
    static NSArray *scanWords = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        scanWords = @[@"scan", @"seek", @"forward", @"backward", @"rewind",
                      @"next", @"previous", @"skip",
                      @"快进", @"快退", @"下一个", @"上一个", @"下一首", @"上一首"];
    });
    for (UIControl *control in cluster) {
        if (control == playPause) continue;
        NSString *label = [[control accessibilityLabel] lowercaseString] ?: @"";
        if ([self label:label matchesAny:scanWords]) {
            control.alpha = 0.0;
            control.userInteractionEnabled = NO;
        }
    }
}

- (void)layoutControlBarButtons {
    UIView *bar = _systemControlBar;
    if (!bar) return;
    CGFloat barWidth = bar.bounds.size.width;
    if (barWidth < 1) return;

    // Audio button on the left side of the volume slider, subtitle button on
    // the right side, both sitting directly on the system control bar.
    CGFloat centerY = bar.bounds.size.height - kTransportButtonHeight / 2.0 - 2.0;
    if (_systemVolumeView) {
        CGRect volumeFrame = [_systemVolumeView convertRect:_systemVolumeView.bounds toView:bar];
        if (!CGRectIsEmpty(volumeFrame)) {
            centerY = CGRectGetMidY(volumeFrame);
            CGFloat y = centerY - kOverlayButtonSize / 2.0;
            CGFloat audioX = CGRectGetMinX(volumeFrame) - kOverlayButtonGap - kOverlayButtonSize;
            audioX = MAX(2.0, audioX);
            _audioButton.frame = CGRectMake(audioX, y, kOverlayButtonSize, kOverlayButtonSize);
            CGFloat subtitleX = CGRectGetMaxX(volumeFrame) + kOverlayButtonGap;
            subtitleX = MIN(barWidth - kOverlayButtonSize - 2.0, subtitleX);
            _subtitleButton.frame = CGRectMake(subtitleX, y, kOverlayButtonSize, kOverlayButtonSize);
        }
    }

    // ±30s flank the play/pause button; previous/next episode sit further out.
    UIControl *playPause = _systemPlayPauseButton;
    if (playPause) {
        _skipBackButton.hidden = NO;
        _skipForwardButton.hidden = NO;
        CGRect playFrame = [playPause convertRect:playPause.bounds toView:bar];
        CGFloat y = CGRectGetMidY(playFrame) - kTransportButtonHeight / 2.0;
        CGFloat backX = CGRectGetMinX(playFrame) - kTransportButtonGap - kTransportButtonWidth;
        backX = MAX(2.0, backX);
        _skipBackButton.frame = CGRectMake(backX, y, kTransportButtonWidth, kTransportButtonHeight);
        CGFloat forwardX = CGRectGetMaxX(playFrame) + kTransportButtonGap;
        forwardX = MIN(barWidth - kTransportButtonWidth - 2.0, forwardX);
        _skipForwardButton.frame = CGRectMake(forwardX, y, kTransportButtonWidth, kTransportButtonHeight);
        CGFloat prevX = CGRectGetMinX(_skipBackButton.frame) - kTransportButtonGap - kTransportButtonWidth;
        prevX = MAX(2.0, prevX);
        _prevEpisodeButton.frame = CGRectMake(prevX, y, kTransportButtonWidth, kTransportButtonHeight);
        CGFloat nextX = CGRectGetMaxX(_skipForwardButton.frame) + kTransportButtonGap;
        nextX = MIN(barWidth - kTransportButtonWidth - 2.0, nextX);
        _nextEpisodeButton.frame = CGRectMake(nextX, y, kTransportButtonWidth, kTransportButtonHeight);
    } else {
        // No play/pause anchor identified yet: pack the four transport buttons
        // in a row just right of the system transport cluster (or at the bar's
        // left edge if the cluster is empty), so they are always usable.
        NSArray *cluster = [self transportClusterInBar:bar];
        CGFloat startX = 2.0;
        if (cluster.count) {
            UIControl *rightmost = [cluster lastObject];
            CGRect rf = [rightmost convertRect:rightmost.bounds toView:bar];
            startX = CGRectGetMaxX(rf) + kTransportButtonGap;
        }
        CGFloat y = centerY - kTransportButtonHeight / 2.0;
        CGFloat step = kTransportButtonWidth + kTransportButtonGap;
        // [上一集][快退30][快进30][下一集]
        _prevEpisodeButton.frame = CGRectMake(startX, y, kTransportButtonWidth, kTransportButtonHeight);
        _skipBackButton.frame = CGRectMake(startX + step, y, kTransportButtonWidth, kTransportButtonHeight);
        _skipForwardButton.frame = CGRectMake(startX + 2.0 * step, y, kTransportButtonWidth, kTransportButtonHeight);
        _nextEpisodeButton.frame = CGRectMake(startX + 3.0 * step, y, kTransportButtonWidth, kTransportButtonHeight);
        _skipBackButton.hidden = NO;
        _skipForwardButton.hidden = NO;
    }
    [self updateEpisodeButtonStates];
}

- (void)updateEpisodeButtonStates {
    BOOL show = _systemPlayPauseButton != nil &&
                self.episodeIndex >= 0 &&
                self.episodeSiblings.count > 1;
    _prevEpisodeButton.hidden = !show;
    _nextEpisodeButton.hidden = !show;
    _prevEpisodeButton.enabled = self.episodeIndex > 0;
    _nextEpisodeButton.enabled = self.episodeIndex + 1 < (NSInteger)self.episodeSiblings.count;
}

#pragma mark - Control Bar Actions

- (void)audioButtonTapped {
    [self presentTrackSheetForAudio:YES];
}

- (void)subtitleButtonTapped {
    [self presentTrackSheetForAudio:NO];
}

- (void)skipBackTapped {
    [self skipByInterval:-30.0];
}

- (void)skipForwardTapped {
    [self skipByInterval:30.0];
}

- (void)skipByInterval:(NSTimeInterval)delta {
    MPMoviePlayerController *player = self.activePlayerController.moviePlayer;
    if (!player) return;
    @try {
        NSTimeInterval time = player.currentPlaybackTime;
        if (isnan(time)) return;
        time += delta;
        if (time < 0) time = 0;
        NSTimeInterval duration = player.duration;
        if (!isnan(duration) && duration > 1 && time > duration - 1) {
            // Seeking onto the very end finishes playback; stop just short.
            time = duration - 1;
        }
        player.currentPlaybackTime = time;
    } @catch (NSException *e) {
        NSLog(@"[OldEmby] skip by interval exception: %@", e);
    }
}

- (void)prevEpisodeTapped {
    [self switchToEpisodeAtIndex:self.episodeIndex - 1];
}

- (void)nextEpisodeTapped {
    [self switchToEpisodeAtIndex:self.episodeIndex + 1];
}

// Switching episodes keeps the full-screen player alive: only the content URL
// is swapped, the same way an audio-track change does it. The detail page
// underneath is refreshed too, so exiting playback lands on the episode that
// is actually playing.
- (void)switchToEpisodeAtIndex:(NSInteger)index {
    if (!self.activePlayerController || self.dismissingPlayer || self.fetchingStream) return;
    if (index < 0 || index >= (NSInteger)self.episodeSiblings.count) return;
    if (index == self.episodeIndex) return;
    OEEmbyItem *target = self.episodeSiblings[index];
    if (![target isKindOfClass:[OEEmbyItem class]] || !target.itemId.length) return;

    self.episodeIndex = index;
    self.item = target;
    [self updateEpisodeButtonStates];

    self.title = target.name;
    self.titleLabel.text = target.name;
    self.overviewLabel.text = target.overview ?: @"暂无简介";
    self.cover.image = nil;
    NSString *imageURL = [[OEEmbyAPIClient sharedClient] imageURLForItem:target width:400 height:225];
    __weak typeof(self) weakSelf = self;
    [[OEImageCache sharedCache] loadImageFromURL:imageURL placeholder:nil completion:^(UIImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.item == target) strongSelf.cover.image = image;
    }];
    [self.view setNeedsLayout];
    [self loadCasts];
    [self loadMediaInfo];

    // Per-item playback state starts over; the fresh stream list arrives with
    // loadMediaInfo and re-picks the default audio track.
    [self clearSubtitles];
    self.audioStreams = @[];
    self.subtitleStreams = @[];
    self.selectedAudioIndex = -1;
    self.selectedSubtitleIndex = -1;

    self.statusLabel.text = @"正在获取播放地址…";
    [self showSubtitleNotice:[NSString stringWithFormat:@"正在加载：%@", target.name.length ? target.name : @"…"]];

    NSUInteger generation = ++self.playRequestGeneration;
    self.fetchingStream = YES;
    OEEmbyAPIClient *client = [OEEmbyAPIClient sharedClient];
    NSString *itemId = target.itemId;
    // Keep the mode the current playback started in.
    BOOL direct = self.currentPlaybackIsDirect;
    OEAPICompletion handler = ^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.playRequestGeneration) return;
        strongSelf.fetchingStream = NO;
        if (error) {
            [strongSelf showPlaybackError:error.localizedDescription ?: @"请求播放地址失败"
                                   detail:[NSString stringWithFormat:@"错误域：%@\n错误码：%ld", error.domain ?: @"-", (long)error.code]];
            return;
        }
        NSString *streamURL = [result isKindOfClass:[NSString class]] ? result : nil;
        NSURL *url = [NSURL URLWithString:streamURL];
        if (!url) {
            [strongSelf showPlaybackError:@"服务器返回了无效的播放地址"
                                   detail:streamURL.length ? [NSString stringWithFormat:@"地址：%@", streamURL] : @"服务器未返回任何地址"];
            return;
        }
        [strongSelf swapPlayerToURL:url isDirectStream:direct baseURLString:streamURL];
    };
    if (direct) {
        [client fetchDirectStreamURLForItem:itemId isAudio:NO completion:handler];
    } else {
        [client fetchStreamURLForItem:itemId isAudio:NO completion:handler];
    }
}

// Point the live player at a new content URL and let the load-state observer
// auto-play once the stream is ready.
- (void)swapPlayerToURL:(NSURL *)url isDirectStream:(BOOL)isDirectStream baseURLString:(NSString *)baseURLString {
    MPMoviePlayerController *player = self.activePlayerController.moviePlayer;
    if (!player) return;
    NSLog(@"[OldEmby] episode stream URL: %@", url.absoluteString);
    self.activeStreamURLString = baseURLString ?: url.absoluteString;
    self.currentPlaybackIsDirect = isDirectStream;
    [self removePlayerObserversForPlayer:player];
    [self clearSubtitleTimer];
    player.movieSourceType = isDirectStream ? MPMovieSourceTypeFile : MPMovieSourceTypeStreaming;
    [player setContentURL:url];
    self.playerBecamePlayable = NO;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(movieLoadStateChanged:) name:MPMoviePlayerLoadStateDidChangeNotification object:player];
    [center addObserver:self selector:@selector(moviePlaybackStateChanged:) name:MPMoviePlayerPlaybackStateDidChangeNotification object:player];
    [center addObserver:self selector:@selector(movieFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:player];
    @try { [player prepareToPlay]; } @catch (NSException *e) {
        NSLog(@"[OldEmby] prepareToPlay after episode switch: %@", e);
    }
}

#pragma mark - Track Selection Sheets

// Audio and subtitles get one sheet each, and both are UIActionSheet — the
// native picker on every target OS here. The system draws it, rotates it with
// the interface and lays it out for the current orientation; a hand-rolled view
// added straight to the UIWindow cannot, because on iOS 6-8 the window's
// coordinate space stays portrait and rotation lives in a transform on the
// root view controller.
- (void)presentTrackSheetForAudio:(BOOL)isAudio {
    UIView *host = [self sheetHostView];
    if (!host) return;

    // Only one sheet at a time: a second tap replaces the first.
    [self dismissActiveSheet];

    NSArray *streams = isAudio ? self.audioStreams : self.subtitleStreams;
    if (!streams.count) {
        NSString *notice;
        if (isAudio) {
            notice = @"未找到可切换的音轨";
        } else if (self.skippedImageSubtitleCount > 0) {
            // Graphic tracks (PGS, VobSub) are pictures, not text — the overlay
            // cannot draw them, so they never make it into the list.
            notice = [NSString stringWithFormat:@"该视频的 %ld 条字幕均为图形格式，本机无法显示",
                      (long)self.skippedImageSubtitleCount];
        } else {
            notice = @"该视频没有可用字幕";
        }
        [self presentNoticeSheetWithTitle:notice inView:host];
        return;
    }

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:(isAudio ? @"选择音轨" : @"选择字幕")
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    sheet.tag = isAudio ? kAudioSheetTag : kSubtitleSheetTag;

    // Subtitles get an explicit "off" row first, so button index 0 means -1
    // and every stream sits one slot further along.
    if (!isAudio) {
        [sheet addButtonWithTitle:[self sheetTitleForText:@"关闭字幕"
                                                selected:(self.selectedSubtitleIndex < 0)]];
    }
    NSInteger selected = isAudio ? self.selectedAudioIndex : self.selectedSubtitleIndex;
    for (NSInteger i = 0; i < (NSInteger)streams.count; i++) {
        OEStreamInfo *info = streams[i];
        NSString *title = info.title.length ? info.title : @"未知";
        [sheet addButtonWithTitle:[self sheetTitleForText:title selected:(i == selected)]];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"取消"];

    self.activeSheet = sheet;
    [sheet showInView:host];
}

// UIActionSheet rows cannot carry a checkmark accessory, so the current track
// is marked in the title itself.
- (NSString *)sheetTitleForText:(NSString *)text selected:(BOOL)selected {
    return selected ? [NSString stringWithFormat:@"✓ %@", text] : text;
}

- (void)presentNoticeSheetWithTitle:(NSString *)title inView:(UIView *)host {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title
                                                       delegate:self
                                              cancelButtonTitle:@"确定"
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    // No tag: the delegate ignores anything that is not one of the two pickers.
    self.activeSheet = sheet;
    [sheet showInView:host];
}

// The movie player is presented full-screen, so its own view is the right host:
// the sheet then shares the player's window and orientation. Fall back to the
// key window if the player view is not in a window yet.
- (UIView *)sheetHostView {
    UIView *playerView = self.activePlayerController.view;
    if (playerView.window) return playerView;
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) {
        NSArray *windows = [UIApplication sharedApplication].windows;
        window = windows.count ? windows[0] : nil;
    }
    return window;
}

- (void)dismissActiveSheet {
    UIActionSheet *sheet = self.activeSheet;
    if (!sheet) return;
    self.activeSheet = nil;
    // Drop the delegate first: this also runs from dealloc, and UIActionSheet
    // holds its delegate unretained, so a dismissal callback would message a
    // half-torn-down controller.
    sheet.delegate = nil;
    [sheet dismissWithClickedButtonIndex:sheet.cancelButtonIndex animated:NO];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex) return;
    if (actionSheet.tag == kAudioSheetTag) {
        [self applyAudioSelection:buttonIndex];
    } else if (actionSheet.tag == kSubtitleSheetTag) {
        // Button 0 is "off" (-1); the streams start at button 1.
        [self applySubtitleSelection:buttonIndex - 1];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (self.activeSheet == actionSheet) self.activeSheet = nil;
}

#pragma mark - Applying a Selection

// Text subtitles are rendered locally by OESubtitleOverlayView, so switching
// them needs no new stream from the server: the URL stays put and playback is
// never interrupted. Image-based tracks the overlay cannot draw are filtered
// out in parseStreamInfoFromMediaSources:, so everything in the list is
// renderable here.
- (void)applySubtitleSelection:(NSInteger)subtitleIndex {
    if (subtitleIndex >= (NSInteger)self.subtitleStreams.count) return;
    self.selectedSubtitleIndex = (subtitleIndex < 0) ? -1 : subtitleIndex;
    NSLog(@"[OldEmby] selected subtitle index: %ld", (long)self.selectedSubtitleIndex);
    if (self.selectedSubtitleIndex < 0) {
        [self clearSubtitles];
        return;
    }
    [self loadSubtitleForIndex:self.selectedSubtitleIndex];
}

// Audio is decided by the transcoder, so a new track means a new stream URL and
// a re-buffer. Direct play hands over the original file untouched and has no
// such knob.
- (void)applyAudioSelection:(NSInteger)audioIndex {
    if (audioIndex < 0 || audioIndex >= (NSInteger)self.audioStreams.count) return;
    if (audioIndex == self.selectedAudioIndex) return;
    NSLog(@"[OldEmby] selected audio index: %ld", (long)audioIndex);
    if (self.currentPlaybackIsDirect) {
        [self showSubtitleNotice:@"直接播放模式下无法切换音轨"];
        return;
    }
    self.selectedAudioIndex = audioIndex;
    [self reloadStreamWithAudioIndex:audioIndex];
}

#pragma mark - Stream Switching

- (void)reloadStreamWithAudioIndex:(NSInteger)audioIndex {
    NSString *baseURL = self.activeStreamURLString;
    if (!baseURL.length) return;

    NSInteger audioStreamIndex = -1;
    if (audioIndex >= 0 && audioIndex < (NSInteger)self.audioStreams.count) {
        OEStreamInfo *info = self.audioStreams[audioIndex];
        audioStreamIndex = [info.index integerValue];
    }

    // Subtitles stay out of the URL: passing SubtitleStreamIndex would make the
    // server burn them into the video on top of the overlay we already draw.
    NSString *newURL = [[OEEmbyAPIClient sharedClient] streamURLWithAudioIndex:audioStreamIndex
                                                                subtitleIndex:-1
                                                                  fromBaseURL:baseURL
                                                                       itemId:self.item.itemId];
    if (!newURL.length) {
        NSLog(@"[OldEmby] failed to rebuild stream URL with audio index");
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

    // The already-parsed cues stay valid across an audio switch — only the
    // ticking timer was stopped above, so bring it back.
    if (self.parsedSubtitleCues.count) [self startSubtitleTimer];
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
        [self showSubtitleNotice:@"该字幕缺少必要信息，无法加载"];
        return;
    }

    self.subtitleLoading = YES;
    // Rapid switching can leave earlier requests in flight; only the newest
    // one is allowed to install its cues.
    NSUInteger generation = ++self.subtitleLoadGeneration;
    [self clearSubtitleTimer];
    self.parsedSubtitleCues = nil;
    [self showSubtitleNotice:@"正在加载字幕…"];

    OEEmbyAPIClient *client = [OEEmbyAPIClient sharedClient];
    NSInteger streamIdx = [info.index integerValue];
    // Always request SRT from the server: Emby's subtitle endpoint transcodes
    // all text subtitle formats (ASS, SSA, VTT, etc.) to SRT on the fly.
    // However, some server versions may ignore the format and return the
    // original text, so the parser auto-detects the actual format.
    NSString *format = @"srt";

    __weak typeof(self) weakSelf = self;
    [client fetchSubtitleForItem:self.item.itemId
                   mediaSourceId:info.mediaSourceId
                     streamIndex:streamIdx
                          format:format
                      completion:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.subtitleLoadGeneration) return;
        strongSelf.subtitleLoading = NO;
        if (error || ![result isKindOfClass:[NSString class]]) {
            NSLog(@"[OldEmby] subtitle fetch failed: %@", error);
            [strongSelf showSubtitleNotice:@"字幕加载失败"];
            return;
        }
        NSString *subtitleText = (NSString *)result;
        if (!subtitleText.length) {
            NSLog(@"[OldEmby] subtitle text is empty");
            [strongSelf showSubtitleNotice:@"服务器返回的字幕为空"];
            return;
        }
        // Auto-detect format and parse (handles SRT, VTT, ASS/SSA, LRC).
        NSArray *cues = [OESubtitleParser parse:subtitleText];
        if (!cues.count) {
            NSLog(@"[OldEmby] no cues parsed from subtitle text (format may be unsupported)");
            [strongSelf showSubtitleNotice:@"字幕格式无法解析"];
            return;
        }
        NSLog(@"[OldEmby] parsed %lu subtitle cues", (unsigned long)cues.count);
        strongSelf.parsedSubtitleCues = cues;
        // Drop the "loading" notice so the first real cue is not overwritten.
        ++strongSelf.subtitleNoticeGeneration;
        [strongSelf.subtitleOverlay setSubtitleText:nil];
        [strongSelf startSubtitleTimer];
    }];
}

// Status text borrows the subtitle overlay: it is the only surface visible over
// the full-screen player. The cue ticker pauses for the duration so a notice is
// not overwritten mid-sentence, then picks up again where the video is by then.
- (void)showSubtitleNotice:(NSString *)text {
    if (!self.subtitleOverlay || !text.length) return;
    NSUInteger generation = ++self.subtitleNoticeGeneration;
    [self clearSubtitleTimer];
    [self.subtitleOverlay setSubtitleText:text];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSubtitleNoticeDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.subtitleNoticeGeneration) return;
        [strongSelf.subtitleOverlay setSubtitleText:nil];
        if (strongSelf.parsedSubtitleCues.count) [strongSelf startSubtitleTimer];
    });
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
    // currentPlaybackTime is NaN before the player has media loaded; a cue may
    // legitimately start at 0, so only reject the unusable values.
    if (isnan(currentTime) || currentTime < 0) return;
    // Join every active cue: ASS frequently has overlapping lines (a sign plus
    // dialogue, two speakers, …) and showing only the first drops the rest.
    NSString *activeText = [OESubtitleParser textForTime:currentTime inCues:self.parsedSubtitleCues];
    [self.subtitleOverlay setSubtitleText:activeText];
}

- (void)clearSubtitles {
    [self clearSubtitleTimer];
    ++self.subtitleLoadGeneration;
    ++self.subtitleNoticeGeneration;
    self.parsedSubtitleCues = nil;
    self.subtitleLoading = NO;
    if (self.subtitleOverlay) [self.subtitleOverlay setSubtitleText:nil];
}

- (void)cleanupOverlayAndSubtitles {
    [self clearSubtitles];
    [self.controlSyncTimer invalidate];
    self.controlSyncTimer = nil;
    _systemVolumeView = nil;
    _systemControlBar = nil;
    _systemPlayPauseButton = nil;
    [self dismissActiveSheet];
    if (_subtitleOverlay) {
        [_subtitleOverlay removeFromSuperview];
        _subtitleOverlay = nil;
    }
    [_audioButton removeFromSuperview];
    [_subtitleButton removeFromSuperview];
    [_prevEpisodeButton removeFromSuperview];
    [_skipBackButton removeFromSuperview];
    [_skipForwardButton removeFromSuperview];
    [_nextEpisodeButton removeFromSuperview];
    _audioButton = nil;
    _subtitleButton = nil;
    _prevEpisodeButton = nil;
    _skipBackButton = nil;
    _skipForwardButton = nil;
    _nextEpisodeButton = nil;
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