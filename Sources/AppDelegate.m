#import "AppDelegate.h"
#import "Controllers/OELoginViewController.h"
#import "Controllers/OELibraryViewController.h"
#import "Controllers/OEMusicLibraryViewController.h"
#import "Controllers/OESettingsViewController.h"
#import "Controllers/OERootTabBarController.h"
#import "Services/OEMusicPlaybackManager.h"
#import "Views/OETheme.h"
#import "Views/OEIconFactory.h"
#import "Constants.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [OETheme libraryBackgroundColor];
    [OETheme applyApplicationAppearance];

    NSError *err = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&err];
    if (err) NSLog(@"[OldEmby] AudioSession error: %@", err);
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];

    UIColor *tabIconColor = [UIColor whiteColor];
    OELibraryViewController *videoVC = [[OELibraryViewController alloc] init];
    videoVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"影视" image:[OEIconFactory imageForIconType:OEIconTypeVideo size:CGSizeMake(30, 30) color:tabIconColor] tag:0];

    OEMusicLibraryViewController *musicVC = [[OEMusicLibraryViewController alloc] init];
    musicVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"音乐" image:[OEIconFactory imageForIconType:OEIconTypeMusic size:CGSizeMake(30, 30) color:tabIconColor] tag:1];

    OESettingsViewController *settingsVC = [[OESettingsViewController alloc] init];
    settingsVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"设置" image:[OEIconFactory imageForIconType:OEIconTypeSettings size:CGSizeMake(30, 30) color:tabIconColor] tag:2];

    UINavigationController *nav1 = [[UINavigationController alloc] initWithRootViewController:videoVC];
    UINavigationController *nav2 = [[UINavigationController alloc] initWithRootViewController:musicVC];
    UINavigationController *nav3 = [[UINavigationController alloc] initWithRootViewController:settingsVC];

    self.tabBarController = [[OERootTabBarController alloc] initWithMusicNavigationController:nav2];
    self.tabBarController.viewControllers = @[nav1, nav2, nav3];

    self.window.rootViewController = self.tabBarController;
    [self.window makeKeyAndVisible];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeDidChange) name:kNotificationThemeDidChange object:nil];

    NSString *token = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsServerToken];
    NSString *host = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsServerHost];
    if (!token || !host) {
        OELoginViewController *loginVC = [[OELoginViewController alloc] init];
        UINavigationController *loginNav = [[UINavigationController alloc] initWithRootViewController:loginVC];
        [self.tabBarController presentViewController:loginNav animated:NO completion:nil];
    }

    NSLog(@"[OldEmby] Launched - window=%@ host=%@", self.window, host);
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
}

// Re-tint bars that were created before the theme changed (appearance
// proxies only affect newly created views) and repaint the window.
- (void)themeDidChange {
    [OETheme applyApplicationAppearance];
    self.window.backgroundColor = [OETheme libraryBackgroundColor];
    for (UIViewController *vc in self.tabBarController.viewControllers) {
        if ([vc isKindOfClass:[UINavigationController class]]) {
            [OETheme applyToNavigationBar:((UINavigationController *)vc).navigationBar];
        }
    }
    [OETheme applyToTabBar:self.tabBarController.tabBar];
    UIViewController *presented = self.tabBarController.presentedViewController;
    if ([presented isKindOfClass:[UINavigationController class]]) {
        [OETheme applyToNavigationBar:((UINavigationController *)presented).navigationBar];
    }
    // Status bar style is app-wide (Info.plist has no per-VC setting): keep it readable on the theme.
    UIStatusBarStyle style = [OETheme themeMode] == OEThemeModeLight ? UIStatusBarStyleDefault : UIStatusBarStyleBlackOpaque;
    [[UIApplication sharedApplication] setStatusBarStyle:style animated:YES];
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    return YES;
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    [[OEMusicPlaybackManager sharedManager] receiveRemoteControlEvent:event];
}

@end
