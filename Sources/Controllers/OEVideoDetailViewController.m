#import "OEVideoDetailViewController.h"
#import "Models/OEEmbyItem.h"
#import "Models/OETranscodeSettings.h"
#import "Services/OEEmbyAPIClient.h"
#import "Services/OEImageCache.h"
#import <MediaPlayer/MediaPlayer.h>

@interface OEVideoDetailViewController ()
@property (nonatomic, strong) OEEmbyItem *item;
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *overviewLabel;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) MPMoviePlayerViewController *activePlayerController;
@end

@implementation OEVideoDetailViewController

- (instancetype)initWithItem:(OEEmbyItem *)item {
    if ((self = [super init])) {
        _item = item;
    }
    return self;
}

- (NSString *)playButtonTitle {
    OETranscodeSettings *s = [OETranscodeSettings sharedSettings];
    if (s.directPlay) {
        return @"播放 (直接播放)";
    }
    return [NSString stringWithFormat:@"播放 (转码 %@ H.264 %ldMbps)", [s resolutionString], (long)s.maxVideoBitrate / 1000000];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = self.item.name;

    CGFloat w = self.view.bounds.size.width;
    self.cover = [[UIImageView alloc] initWithFrame:CGRectMake(20, 80, w-40, 180)];
    self.cover.contentMode = UIViewContentModeScaleAspectFit;
    self.cover.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    [self.view addSubview:self.cover];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 270, w-40, 24)];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.titleLabel.text = self.item.name;
    [self.view addSubview:self.titleLabel];

    self.overviewLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 300, w-40, 80)];
    self.overviewLabel.font = [UIFont systemFontOfSize:12];
    self.overviewLabel.textColor = [UIColor darkGrayColor];
    self.overviewLabel.numberOfLines = 4;
    self.overviewLabel.text = self.item.overview ?: @"暂无简介";
    [self.view addSubview:self.overviewLabel];

    self.playBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.playBtn.frame = CGRectMake(20, 400, w-40, 46);
    [self.playBtn setTitle:[self playButtonTitle] forState:UIControlStateNormal];
    self.playBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.playBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:1];
    [self.playBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.playBtn.layer.cornerRadius = 6;
    self.playBtn.clipsToBounds = YES;
    [self.playBtn addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playBtn];

    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:self.item width:400];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image){
        self.cover.image = image;
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.playBtn setTitle:[self playButtonTitle] forState:UIControlStateNormal];
}

- (void)playTapped {
    [self.playBtn setTitle:@"正在获取播放地址..." forState:UIControlStateNormal];
    self.playBtn.enabled = NO;
    [[OEEmbyAPIClient sharedClient] fetchStreamURLForItem:self.item.itemId isAudio:NO completion:^(id result, NSError *error){
        self.playBtn.enabled = YES;
        [self.playBtn setTitle:[self playButtonTitle] forState:UIControlStateNormal];
        if (error) {
            UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"播放失败" message:error.localizedDescription delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
            [av show];
            return;
        }
        NSString *streamURL = (NSString *)result;
        NSLog(@"[OldEmby] play URL: %@", streamURL);
        NSURL *url = [NSURL URLWithString:streamURL];
        if (!url) { UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"URL错误" message:streamURL delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil]; [av show]; return; }

        // iOS 6-9 compatible: MPMoviePlayerViewController
        MPMoviePlayerViewController *mp = [[MPMoviePlayerViewController alloc] initWithContentURL:url];
        if (!mp) {
            UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"播放器初始化失败" message:nil delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
            [av show];
            return;
        }
        self.activePlayerController = mp;
        // Configure
        mp.moviePlayer.movieSourceType = MPMovieSourceTypeStreaming;
        mp.moviePlayer.shouldAutoplay = YES;
        [mp.moviePlayer prepareToPlay];
        [self presentMoviePlayerViewControllerAnimated:mp];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:mp.moviePlayer];
    }];
}

- (void)movieFinished:(NSNotification *)n {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:nil];
    if (self.activePlayerController) {
        [self dismissMoviePlayerViewControllerAnimated];
        self.activePlayerController = nil;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

@end
