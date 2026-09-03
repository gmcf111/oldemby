#import "OERootTabBarController.h"
#import "Views/OEMiniPlayerView.h"
#import "Views/OEErrorAlertView.h"
#import "Services/OEMusicPlaybackManager.h"
#import "Controllers/OEMusicPlayerViewController.h"
#import "Constants.h"

@interface OERootTabBarController ()
@property (nonatomic, assign) UINavigationController *musicNavigationController;
@property (nonatomic, strong) OEMiniPlayerView *miniPlayer;
@property (nonatomic, assign) BOOL fullPlayerVisible;
@end

@implementation OERootTabBarController

- (instancetype)initWithMusicNavigationController:(UINavigationController *)musicNavigationController {
    if ((self = [super init])) {
        _musicNavigationController = musicNavigationController;
        self.delegate = self;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.miniPlayer = [[OEMiniPlayerView alloc] initWithFrame:CGRectZero];
    self.miniPlayer.hidden = YES;
    [self.view addSubview:self.miniPlayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateMiniPlayerVisibility) name:kNotificationMusicPlaybackStateChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fullPlayerVisibilityChanged:) name:kNotificationMusicFullPlayerVisibilityChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showFullPlayerFromMiniPlayer) name:@"OEMiniPlayerDidRequestFullPlayer" object:nil];
    // Music failures can happen while any tab is on screen (playback is
    // global), so the always-present root controller owns the error sheet.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showMusicPlaybackFailure:) name:kNotificationMusicPlaybackFailed object:nil];
    [self updateMiniPlayerVisibility];
}

- (void)showMusicPlaybackFailure:(NSNotification *)notification {
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    [OEErrorAlertView showWithTitle:@"音乐播放失败"
                            message:manager.statusText ?: @"未知错误"
                             detail:manager.lastErrorDetail];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat height = 54;
    CGRect tabFrame = self.tabBar.frame;
    self.miniPlayer.frame = CGRectMake(0, CGRectGetMinY(tabFrame) - height, self.view.bounds.size.width, height);
    [self.view bringSubviewToFront:self.miniPlayer];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self updateMiniPlayerVisibility];
}

- (BOOL)isMusicTabSelected {
    return self.selectedViewController == self.musicNavigationController;
}

// Track visibility from the notification object instead of inspecting
// presentedViewController: that property only clears when the dismiss
// animation completes, which would leave the mini player hidden afterwards.
- (void)fullPlayerVisibilityChanged:(NSNotification *)note {
    // The music library also posts this notification (with itself as object)
    // to force a visibility refresh, so check the sender's class rather than
    // mere non-nil.
    self.fullPlayerVisible = [note.object isKindOfClass:[OEMusicPlayerViewController class]];
    [self updateMiniPlayerVisibility];
}

- (BOOL)isFullPlayerVisible {
    return self.fullPlayerVisible;
}

- (void)updateMiniPlayerVisibility {
    BOOL visible = [OEMusicPlaybackManager sharedManager].isActive && [self isMusicTabSelected] && ![self isFullPlayerVisible];
    self.miniPlayer.hidden = !visible;
    if (visible) [self.miniPlayer refresh];
    [self.view setNeedsLayout];
}

- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController {
    return YES;
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    [self updateMiniPlayerVisibility];
}

- (void)showFullPlayerFromMiniPlayer {
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    if (!manager.currentItem || [self isFullPlayerVisible]) return;
    OEMusicPlayerViewController *player = [[OEMusicPlayerViewController alloc] initWithItem:manager.currentItem playlist:manager.playlist];
    // Present over the tab bar so the player slides up from the mini player's
    // spot at the bottom of the screen instead of pushing sideways.
    player.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    [self presentViewController:player animated:YES completion:nil];
    [self updateMiniPlayerVisibility];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
