#import "OEVideoDetailViewController.h"
#import "Models/OEEmbyItem.h"
#import "Models/OETranscodeSettings.h"
#import "Services/OEEmbyAPIClient.h"
#import "Services/OEImageCache.h"
#import "Views/OETheme.h"
#import "Constants.h"
#import <MediaPlayer/MediaPlayer.h>

@interface OEVideoDetailViewController ()
@property (nonatomic, strong) OEEmbyItem *item;
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *overviewLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) MPMoviePlayerViewController *activePlayerController;
@property (nonatomic, assign) BOOL playerBecamePlayable;
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

    self.cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.cover.contentMode = UIViewContentModeScaleAspectFit;
    self.cover.layer.borderWidth = 1.0;
    [self.view addSubview:self.cover];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.titleLabel.text = self.item.name;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.titleLabel];

    self.overviewLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.overviewLabel.font = [UIFont systemFontOfSize:12];
    self.overviewLabel.numberOfLines = 4;
    self.overviewLabel.text = self.item.overview ?: @"暂无简介";
    self.overviewLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.overviewLabel];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [OETheme accentColor];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.statusLabel];

    self.playBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playBtn.backgroundColor = [OETheme accentColor];
    self.playBtn.layer.cornerRadius = 7;
    self.playBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.playBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.playBtn setTitle:[self playButtonTitle] forState:UIControlStateNormal];
    [self.playBtn addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playBtn];

    [self applyTheme];

    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:self.item width:480 height:300];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image) { self.cover.image = image; }];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:kNotificationThemeDidChange object:nil];
}

- (void)applyTheme {
    self.view.backgroundColor = [OETheme libraryBackgroundColor];
    self.cover.backgroundColor = [OETheme imagePlaceholderColor];
    self.cover.layer.borderColor = [OETheme separatorColor].CGColor;
    self.titleLabel.textColor = [OETheme primaryTextColor];
    self.overviewLabel.textColor = [OETheme secondaryTextColor];
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat coverHeight = MIN(220, w * 0.62);
    self.cover.frame = CGRectMake(20, 18, w - 40, coverHeight);
    CGFloat y = CGRectGetMaxY(self.cover.frame) + 14;
    self.titleLabel.frame = CGRectMake(20, y, w - 40, 24);
    y += 28;
    self.overviewLabel.frame = CGRectMake(20, y, w - 40, 72);
    y += 79;
    self.statusLabel.frame = CGRectMake(20, y, w - 40, 18);
    y += 24;
    self.playBtn.frame = CGRectMake(20, y, w - 40, 46);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.activePlayerController) [self.playBtn setTitle:[self playButtonTitle] forState:UIControlStateNormal];
}

- (void)playTapped {
    self.statusLabel.text = @"正在请求 HLS 转码流…";
    [self.playBtn setTitle:@"正在获取播放地址…" forState:UIControlStateNormal];
    self.playBtn.enabled = NO;
    [[OEEmbyAPIClient sharedClient] fetchStreamURLForItem:self.item.itemId isAudio:NO completion:^(id result, NSError *error) {
        self.playBtn.enabled = YES;
        [self.playBtn setTitle:[self playButtonTitle] forState:UIControlStateNormal];
        if (error) { [self showPlaybackError:error.localizedDescription]; return; }
        NSString *streamURL = [result isKindOfClass:[NSString class]] ? result : nil;
        NSURL *url = [NSURL URLWithString:streamURL];
        if (!url) { [self showPlaybackError:@"服务器返回了无效的播放地址"]; return; }
        NSLog(@"[OldEmby] video stream URL: %@", streamURL);
        [self presentPlayerForURL:url];
    }];
}

- (void)presentPlayerForURL:(NSURL *)url {
    MPMoviePlayerViewController *controller = [[MPMoviePlayerViewController alloc] initWithContentURL:url];
    if (!controller) { [self showPlaybackError:@"无法初始化系统播放器"]; return; }
    self.activePlayerController = controller;
    self.playerBecamePlayable = NO;
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
    if (player.playbackState == MPMoviePlaybackStatePlaying) self.statusLabel.text = @"正在播放";
    else if (player.playbackState == MPMoviePlaybackStateInterrupted) self.statusLabel.text = @"播放被中断";
}

- (void)movieFinished:(NSNotification *)notification {
    MPMoviePlayerController *player = notification.object;
    NSInteger reason = [notification.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] integerValue];
    NSError *error = notification.userInfo[@"error"];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerLoadStateDidChangeNotification object:player];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackStateDidChangeNotification object:player];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:player];
    if (self.activePlayerController) {
        [self dismissMoviePlayerViewControllerAnimated];
        self.activePlayerController = nil;
    }
    if (reason == MPMovieFinishReasonPlaybackError) {
        [self showPlaybackError:error.localizedDescription ?: @"系统播放器无法播放该 HLS 流，请检查 Emby 转码日志"];
    } else if (!self.playerBecamePlayable) {
        self.statusLabel.text = @"播放器未取得可播放数据";
    }
}

- (void)showPlaybackError:(NSString *)message {
    self.statusLabel.text = @"播放失败";
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"播放失败" message:message delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
    [alert show];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
