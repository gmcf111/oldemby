#import "OERootTabBarController.h"
#import "Views/OEMiniPlayerView.h"
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateMiniPlayerVisibility) name:kNotificationMusicFullPlayerVisibilityChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showFullPlayerFromMiniPlayer) name:@"OEMiniPlayerDidRequestFullPlayer" object:nil];
    [self updateMiniPlayerVisibility];
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

- (BOOL)isFullPlayerVisible {
    return [self.musicNavigationController.visibleViewController isKindOfClass:[OEMusicPlayerViewController class]];
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
    player.hidesBottomBarWhenPushed = YES;
    [self.musicNavigationController pushViewController:player animated:YES];
    [self updateMiniPlayerVisibility];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
