#import "AppDelegate.h"
#import "Controllers/OELoginViewController.h"
#import "Controllers/OELibraryViewController.h"
#import "Controllers/OEMusicLibraryViewController.h"
#import "Controllers/OESettingsViewController.h"
#import "Constants.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor blackColor];

    // Background audio session for music playback (iOS 6 compatible)
    NSError *err = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&err];
    if (err) { NSLog(@"[OldEmby] AudioSession error: %@", err); }
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];

    // Controllers - pure code, no XIB/Storyboard
    OELibraryViewController *videoVC = [[OELibraryViewController alloc] init];
    videoVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"视频" image:nil tag:0];

    OEMusicLibraryViewController *musicVC = [[OEMusicLibraryViewController alloc] init];
    musicVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"音乐" image:nil tag:1];

    OESettingsViewController *settingsVC = [[OESettingsViewController alloc] init];
    settingsVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"设置" image:nil tag:2];

    UINavigationController *nav1 = [[UINavigationController alloc] initWithRootViewController:videoVC];
    UINavigationController *nav2 = [[UINavigationController alloc] initWithRootViewController:musicVC];
    UINavigationController *nav3 = [[UINavigationController alloc] initWithRootViewController:settingsVC];

    self.tabBarController = [[UITabBarController alloc] init];
    self.tabBarController.viewControllers = @[nav1, nav2, nav3];

    // Check if not logged in -> present login modally
    NSString *token = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsServerToken];
    NSString *host = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsServerHost];
    if (!token || !host) {
        // Delay present to ensure window visible (iOS6 needs viewDidAppear timing, but we try here)
        self.window.rootViewController = self.tabBarController;
        [self.window makeKeyAndVisible];
        OELoginViewController *loginVC = [[OELoginViewController alloc] init];
        UINavigationController *loginNav = [[UINavigationController alloc] initWithRootViewController:loginVC];
        // iOS6 presentModalViewController compatibility: use presentViewController
        [self.tabBarController presentViewController:loginNav animated:NO completion:nil];
    } else {
        self.window.rootViewController = self.tabBarController;
        [self.window makeKeyAndVisible];
    }

    NSLog(@"[OldEmby] Launched - window=%@ host=%@", self.window, host);
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Keep audio playing - UIBackgroundModes audio already declared
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    return YES;
}

// iOS 6 remote control (lock screen / headset) - deprecated in iOS 7.1+ MPRemoteCommandCenter but required for iOS 6
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if (event.type == UIEventTypeRemoteControl) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationPlaybackStateChanged object:event];
    }
}

@end
