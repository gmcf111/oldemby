#import "OEMusicPlayerViewController.h"
#import "Models/OEEmbyItem.h"
#import "Models/OELyricsLine.h"
#import "Services/OEMusicPlaybackManager.h"
#import "Services/OEEmbyAPIClient.h"
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
@property (nonatomic, strong) UITableView *lyricsTable;
@property (nonatomic, strong) UILabel *lyricsEmptyLabel;
@property (nonatomic, strong) NSArray *lyrics;
@property (nonatomic, copy) NSString *lyricsItemId;
@property (nonatomic, assign) NSInteger highlightedLyricsIndex;
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
        _highlightedLyricsIndex = NSNotFound;
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
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.statusLabel];

    self.lyricsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.lyricsTable.dataSource = self;
    self.lyricsTable.delegate = self;
    self.lyricsTable.rowHeight = 28;
    self.lyricsTable.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.lyricsTable.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.lyricsTable];

    self.lyricsEmptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.lyricsEmptyLabel.text = @"正在加载歌词…";
    self.lyricsEmptyLabel.textAlignment = NSTextAlignmentCenter;
    self.lyricsEmptyLabel.font = [UIFont systemFontOfSize:13];
    self.lyricsEmptyLabel.backgroundColor = [UIColor clearColor];
    [self.lyricsTable addSubview:self.lyricsEmptyLabel];

    self.progressSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    self.progressSlider.minimumValue = 0.0;
    self.progressSlider.maximumValue = 1.0;
    [self.progressSlider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [self.progressSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.progressSlider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    [self.view addSubview:self.progressSlider];

    self.timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.timeLabel.font = [UIFont systemFontOfSize:11];
    self.timeLabel.textAlignment = NSTextAlignmentCenter;
    self.timeLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.timeLabel];

    self.previousButton = [self circularButton];
    [self.previousButton addTarget:self action:@selector(previousTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.previousButton];

    self.playPauseButton = [self circularButton];
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
    self.statusLabel.textColor = [OETheme accentColor];
    self.timeLabel.textColor = [OETheme secondaryTextColor];
    self.progressSlider.minimumTrackTintColor = [OETheme accentColor];
    self.progressSlider.maximumTrackTintColor = [OETheme separatorColor];
    self.lyricsTable.backgroundColor = [OETheme cellColor];
    self.lyricsEmptyLabel.textColor = [OETheme secondaryTextColor];
    for (UIButton *button in @[self.previousButton, self.playPauseButton, self.nextButton]) {
        button.layer.borderColor = [OETheme separatorColor].CGColor;
        button.backgroundColor = button == self.playPauseButton ? [OETheme accentColor] : [OETheme cellColor];
    }
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)applyThemeAndRefresh {
    [self applyTheme];
    [self.lyricsTable reloadData];
    [self refresh];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 10;
    // Keep all controls reachable on 3.5-inch iPhones after the navigation
    // bar has consumed part of the 480-point screen.
    CGFloat artworkLimit = self.view.bounds.size.height < 450 ? 120 : 150;
    CGFloat artwork = MIN(w - 64, artworkLimit);
    self.artworkView.frame = CGRectMake((w - artwork) / 2.0, y, artwork, artwork);
    y = CGRectGetMaxY(self.artworkView.frame) + 8;
    self.titleLabel.frame = CGRectMake(24, y, w - 48, 22);
    y += 23;
    self.artistLabel.frame = CGRectMake(24, y, w - 48, 18);
    y += 19;
    self.statusLabel.frame = CGRectMake(24, y, w - 48, 16);
    y += 19;
    CGFloat buttonsHeight = 64 + 29;
    CGFloat remaining = self.view.bounds.size.height - y - buttonsHeight - 64;
    CGFloat lyricsHeight = MAX(42, MIN(130, remaining));
    self.lyricsTable.frame = CGRectMake(16, y, w - 32, lyricsHeight);
    self.lyricsEmptyLabel.frame = self.lyricsTable.bounds;
    y = CGRectGetMaxY(self.lyricsTable.frame) + 6;
    // The 40-point control frame gives the iOS 6 slider a reliable touch target.
    self.progressSlider.frame = CGRectMake(20, y, w - 40, 40);
    y += 35;
    self.timeLabel.frame = CGRectMake(24, y, w - 48, 14);
    y += 20;
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
    [self requestLyricsForItemIfNeeded:item];
    [self refreshProgress];
}

- (void)requestLyricsForItemIfNeeded:(OEEmbyItem *)item {
    if (!item.itemId.length || [item.itemId isEqualToString:self.lyricsItemId]) return;
    self.lyricsItemId = item.itemId;
    self.lyrics = @[];
    self.highlightedLyricsIndex = NSNotFound;
    self.lyricsEmptyLabel.text = @"正在加载歌词…";
    self.lyricsEmptyLabel.hidden = NO;
    [self.lyricsTable reloadData];
    NSString *itemId = [item.itemId copy];
    [[OEEmbyAPIClient sharedClient] fetchLyricsForItem:item completion:^(id result, NSError *error) {
        if (![itemId isEqualToString:self.lyricsItemId]) return;
        if ([result isKindOfClass:[NSString class]]) {
            self.lyrics = [OELyricsLine linesFromTextSubtitleString:result];
        } else {
            self.lyrics = error ? @[] : [OELyricsLine linesFromEmbyResponse:result];
        }
        self.lyricsEmptyLabel.text = self.lyrics.count ? @"" : @"此歌曲暂无可显示歌词";
        self.lyricsEmptyLabel.hidden = self.lyrics.count > 0;
        [self.lyricsTable reloadData];
        [self updateHighlightedLyricsAtTime:[OEMusicPlaybackManager sharedManager].currentTime scroll:NO];
    }];
}

- (void)refreshProgress {
    if (self.seeking) return;
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    self.progressSlider.value = manager.progress;
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [self stringForTime:manager.currentTime], [self stringForTime:manager.duration]];
    [self updateHighlightedLyricsAtTime:manager.currentTime scroll:YES];
}

- (void)updateHighlightedLyricsAtTime:(NSTimeInterval)time scroll:(BOOL)scroll {
    NSInteger selected = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)self.lyrics.count; i++) {
        OELyricsLine *line = self.lyrics[i];
        if (line.startTime <= time) selected = i;
        else break;
    }
    if (selected == self.highlightedLyricsIndex) return;
    NSInteger previous = self.highlightedLyricsIndex;
    self.highlightedLyricsIndex = selected;
    NSMutableArray *reload = [NSMutableArray array];
    if (previous != NSNotFound && previous < (NSInteger)self.lyrics.count) [reload addObject:[NSIndexPath indexPathForRow:previous inSection:0]];
    if (selected != NSNotFound) [reload addObject:[NSIndexPath indexPathForRow:selected inSection:0]];
    if (reload.count) [self.lyricsTable reloadRowsAtIndexPaths:reload withRowAnimation:UITableViewRowAnimationNone];
    if (scroll && selected != NSNotFound) {
        [self.lyricsTable scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:selected inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
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
    NSTimeInterval previewTime = slider.value * manager.duration;
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [self stringForTime:previewTime], [self stringForTime:manager.duration]];
    [self updateHighlightedLyricsAtTime:previewTime scroll:NO];
}
- (void)sliderTouchUp {
    float progress = self.progressSlider.value;
    __weak typeof(self) weakSelf = self;
    [[OEMusicPlaybackManager sharedManager] seekToProgress:progress completion:^(BOOL finished) {
        weakSelf.seeking = NO;
        [weakSelf refreshProgress];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.lyrics.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"LyricsLine";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [UIFont systemFontOfSize:13];
        cell.textLabel.backgroundColor = [UIColor clearColor];
    }
    OELyricsLine *line = self.lyrics[indexPath.row];
    cell.textLabel.text = line.text;
    BOOL current = indexPath.row == self.highlightedLyricsIndex;
    cell.backgroundColor = [OETheme cellColor];
    cell.contentView.backgroundColor = [OETheme cellColor];
    cell.textLabel.textColor = current ? [OETheme accentColor] : [OETheme secondaryTextColor];
    cell.textLabel.font = current ? [UIFont boldSystemFontOfSize:14] : [UIFont systemFontOfSize:13];
    return cell;
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
