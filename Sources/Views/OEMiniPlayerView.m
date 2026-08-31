#import "OEMiniPlayerView.h"
#import "OETheme.h"
#import "OEIconFactory.h"
#import "Services/OEMusicPlaybackManager.h"
#import "Models/OEEmbyItem.h"
#import "Constants.h"

@interface OEMiniPlayerView ()
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIView *progressView;
@end

@implementation OEMiniPlayerView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.borderWidth = 0.5;

        _artworkView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _artworkView.contentMode = UIViewContentModeScaleAspectFit;
        _artworkView.clipsToBounds = YES;
        [self addSubview:_artworkView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont boldSystemFontOfSize:12];
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_titleLabel];

        _artistLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _artistLabel.font = [UIFont systemFontOfSize:11];
        _artistLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_artistLabel];

        _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_playButton];

        _progressView = [[UIView alloc] initWithFrame:CGRectZero];
        _progressView.backgroundColor = [OETheme accentColor];
        [self addSubview:_progressView];

        [self addTarget:self action:@selector(openPlayer) forControlEvents:UIControlEventTouchUpInside];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:kNotificationMusicPlaybackStateChanged object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:kNotificationMusicPlaybackProgressChanged object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:kNotificationThemeDidChange object:nil];
        [self applyTheme];
        [self refresh];
    }
    return self;
}

- (void)applyTheme {
    self.backgroundColor = [OETheme cellColor];
    self.layer.borderColor = [OETheme separatorColor].CGColor;
    self.artworkView.backgroundColor = [OETheme imagePlaceholderColor];
    self.titleLabel.textColor = [OETheme primaryTextColor];
    self.artistLabel.textColor = [OETheme secondaryTextColor];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height;
    self.artworkView.frame = CGRectMake(7, 5, h - 10, h - 10);
    CGFloat labelX = CGRectGetMaxX(self.artworkView.frame) + 8;
    CGFloat buttonW = 46;
    CGFloat labelW = self.bounds.size.width - labelX - buttonW - 4;
    self.titleLabel.frame = CGRectMake(labelX, 9, labelW, 17);
    self.artistLabel.frame = CGRectMake(labelX, 27, labelW, 15);
    self.playButton.frame = CGRectMake(self.bounds.size.width - buttonW, 2, buttonW, h - 4);
    self.progressView.frame = CGRectMake(0, h - 2, self.bounds.size.width * [OEMusicPlaybackManager sharedManager].progress, 2);
}

- (void)refresh {
    [self applyTheme];
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    OEEmbyItem *item = manager.currentItem;
    self.titleLabel.text = item.name ?: @"未播放";
    self.artistLabel.text = manager.statusText ?: item.artist ?: @"";
    self.artworkView.image = manager.artwork;
    OEIconType icon = manager.isPlaying ? OEIconTypePause : OEIconTypePlay;
    [self.playButton setImage:[OEIconFactory imageForIconType:icon size:CGSizeMake(22, 22) color:[OETheme primaryTextColor]] forState:UIControlStateNormal];
    [self setNeedsLayout];
}

- (void)playTapped {
    [[OEMusicPlaybackManager sharedManager] togglePlayPause];
}

- (void)openPlayer {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"OEMiniPlayerDidRequestFullPlayer" object:self];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
