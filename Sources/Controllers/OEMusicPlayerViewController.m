#import "OEMusicPlayerViewController.h"
#import "Models/OEEmbyItem.h"
#import "Services/OEMusicPlaybackManager.h"
#import "Views/OETheme.h"
#import "Views/OEIconFactory.h"
#import "Constants.h"
#import <math.h>

@interface OEMusicPlayerViewController ()
@property (nonatomic, strong) OEEmbyItem *initialItem;
@property (nonatomic, strong) NSArray *initialPlaylist;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *previousButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, assign) BOOL seeking;
@end

@implementation OEMusicPlayerViewController

- (instancetype)initWithItem:(OEEmbyItem *)item playlist:(NSArray *)playlist {
    if ((self = [super init])) {
        _initialItem = item;
        _initialPlaylist = [playlist copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [OETheme prepareViewController:self];
    self.title = @"正在播放";

    self.artworkView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFit;
    self.artworkView.clipsToBounds = YES;
    self.artworkView.layer.borderWidth = 1.0;
    [self.view addSubview:self.artworkView];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.titleLabel];

    self.artistLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.artistLabel.font = [UIFont systemFontOfSize:14];
    self.artistLabel.textAlignment = NSTextAlignmentCenter;
    self.artistLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.artistLabel];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textColor = [OETheme accentColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.statusLabel];

    self.progressSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    self.progressSlider.minimumTrackTintColor = [OETheme accentColor];
    self.progressSlider.maximumTrackTintColor = [OETheme separatorColor];
    [self.progressSlider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [self.progressSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.progressSlider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.view addSubview:self.progressSlider];

    self.timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.timeLabel.font = [UIFont systemFontOfSize:11];
    self.timeLabel.textColor = [OETheme secondaryTextColor];
    self.timeLabel.textAlignment = NSTextAlignmentCenter;
    self.timeLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.timeLabel];

    self.previousButton = [self circularButton];
    [self.previousButton addTarget:self action:@selector(previousTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.previousButton];

    self.playPauseButton = [self circularButton];
    self.playPauseButton.backgroundColor = [OETheme accentColor];
    [self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playPauseButton];

    self.nextButton = [self circularButton];
    [self.nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.nextButton];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:kNotificationMusicPlaybackStateChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshProgress) name:kNotificationMusicPlaybackProgressChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyThemeAndRefresh) name:kNotificationThemeDidChange object:nil];
    [self applyTheme];
    if (![OEMusicPlaybackManager sharedManager].active && self.initialItem) {
        [[OEMusicPlaybackManager sharedManager] playItem:self.initialItem playlist:self.initialPlaylist];
    }
    [self refresh];
}

- (UIButton *)circularButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.layer.borderWidth = 1.0;
    return button;
}

- (void)applyTheme {
    self.view.backgroundColor = [OETheme libraryBackgroundColor];
    self.artworkView.backgroundColor = [OETheme imagePlaceholderColor];
    self.artworkView.layer.borderColor = [OETheme separatorColor].CGColor;
    self.titleLabel.textColor = [OETheme primaryTextColor];
    self.artistLabel.textColor = [OETheme secondaryTextColor];
    self.timeLabel.textColor = [OETheme secondaryTextColor];
    for (UIButton *button in @[self.previousButton, self.playPauseButton, self.nextButton]) {
        button.layer.borderColor = [OETheme separatorColor].CGColor;
        if (button != self.playPauseButton) button.backgroundColor = [OETheme cellColor];
    }
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)applyThemeAndRefresh {
    [self applyTheme];
    [self refresh];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 20;
    CGFloat artwork = MIN(w - 64, 230);
    self.artworkView.frame = CGRectMake((w - artwork) / 2.0, y, artwork, artwork);
    y = CGRectGetMaxY(self.artworkView.frame) + 18;
    self.titleLabel.frame = CGRectMake(24, y, w - 48, 24);
    y += 26;
    self.artistLabel.frame = CGRectMake(24, y, w - 48, 19);
    y += 23;
    self.statusLabel.frame = CGRectMake(24, y, w - 48, 17);
    y += 25;
    self.progressSlider.frame = CGRectMake(25, y, w - 50, 22);
    y += 22;
    self.timeLabel.frame = CGRectMake(24, y, w - 48, 16);
    y += 29;
    CGFloat small = 50, large = 64, gap = 28;
    self.previousButton.frame = CGRectMake((w - large) / 2.0 - gap - small, y + 7, small, small);
    self.playPauseButton.frame = CGRectMake((w - large) / 2.0, y, large, large);
    self.nextButton.frame = CGRectMake((w - large) / 2.0 + large + gap, y + 7, small, small);
    self.previousButton.layer.cornerRadius = small / 2.0;
    self.nextButton.layer.cornerRadius = small / 2.0;
    self.playPauseButton.layer.cornerRadius = large / 2.0;
}

- (void)refresh {
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    OEEmbyItem *item = manager.currentItem;
    self.titleLabel.text = item.name ?: @"未播放";
    self.artistLabel.text = item.artist ?: item.album ?: @"";
    self.statusLabel.text = manager.statusText ?: @"";
    self.artworkView.image = manager.artwork;
    OEIconType primary = manager.isPlaying ? OEIconTypePause : OEIconTypePlay;
    [self.playPauseButton setImage:[OEIconFactory imageForIconType:primary size:CGSizeMake(28, 28) color:[UIColor whiteColor]] forState:UIControlStateNormal];
    [self.previousButton setImage:[OEIconFactory imageForIconType:OEIconTypePrevious size:CGSizeMake(24, 24) color:[OETheme primaryTextColor]] forState:UIControlStateNormal];
    [self.nextButton setImage:[OEIconFactory imageForIconType:OEIconTypeNext size:CGSizeMake(24, 24) color:[OETheme primaryTextColor]] forState:UIControlStateNormal];
    [self refreshProgress];
}

- (void)refreshProgress {
    if (self.seeking) return;
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    self.progressSlider.value = manager.progress;
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [self stringForTime:manager.currentTime], [self stringForTime:manager.duration]];
}

- (NSString *)stringForTime:(NSTimeInterval)time {
    if (!isfinite(time) || time < 0) return @"--:--";
    NSInteger seconds = (NSInteger)time;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}

- (void)playPauseTapped { [[OEMusicPlaybackManager sharedManager] togglePlayPause]; }
- (void)previousTapped { [[OEMusicPlaybackManager sharedManager] previous]; }
- (void)nextTapped { [[OEMusicPlaybackManager sharedManager] next]; }
- (void)sliderTouchDown { self.seeking = YES; }
- (void)sliderChanged:(UISlider *)slider {
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [self stringForTime:slider.value * manager.duration], [self stringForTime:manager.duration]];
}
- (void)sliderTouchUp {
    self.seeking = NO;
    [[OEMusicPlaybackManager sharedManager] seekToProgress:self.progressSlider.value completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationMusicFullPlayerVisibilityChanged object:self];
    [self refresh];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationMusicFullPlayerVisibilityChanged object:self];
    });
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
