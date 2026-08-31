#import "OETheme.h"
#import "Constants.h"

@implementation OETheme

+ (OEThemeMode)themeMode {
    NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsThemeMode];
    // Fresh installs start in light mode; an explicitly saved choice wins.
    if (![saved isKindOfClass:[NSNumber class]]) return OEThemeModeLight;
    return [saved integerValue] == OEThemeModeLight ? OEThemeModeLight : OEThemeModeDark;
}

+ (void)setThemeMode:(OEThemeMode)mode {
    if (mode == [self themeMode]) return;
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kDefaultsThemeMode];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationThemeDidChange object:nil];
}

+ (BOOL)isLight { return [self themeMode] == OEThemeModeLight; }

// Emby brand green (#52B54B). Dark mode uses only gray / green / black.
+ (UIColor *)libraryBackgroundColor {
    return [self isLight] ? [UIColor colorWithWhite:0.93 alpha:1.0]
                          : [UIColor colorWithWhite:0.11 alpha:1.0];
}
+ (UIColor *)navigationBarColor {
    return [self isLight] ? [UIColor colorWithWhite:0.83 alpha:1.0]
                          : [UIColor colorWithWhite:0.16 alpha:1.0];
}
+ (UIColor *)tabBarColor {
    return [self isLight] ? [UIColor colorWithWhite:0.81 alpha:1.0]
                          : [UIColor colorWithWhite:0.14 alpha:1.0];
}
+ (UIColor *)cellColor {
    return [self isLight] ? [UIColor whiteColor]
                          : [UIColor colorWithWhite:0.18 alpha:1.0];
}
+ (UIColor *)primaryTextColor {
    return [self isLight] ? [UIColor colorWithWhite:0.13 alpha:1.0]
                          : [UIColor colorWithWhite:0.94 alpha:1.0];
}
+ (UIColor *)secondaryTextColor {
    return [self isLight] ? [UIColor colorWithWhite:0.46 alpha:1.0]
                          : [UIColor colorWithWhite:0.63 alpha:1.0];
}
// #52B54B: Emby green, matches the app icon.
+ (UIColor *)accentColor { return [UIColor colorWithRed:0.322 green:0.710 blue:0.294 alpha:1.0]; }
+ (UIColor *)separatorColor {
    return [self isLight] ? [UIColor colorWithWhite:0.80 alpha:1.0]
                          : [UIColor colorWithWhite:0.23 alpha:1.0];
}
+ (UIColor *)imagePlaceholderColor {
    return [self isLight] ? [UIColor colorWithWhite:0.88 alpha:1.0]
                          : [UIColor colorWithWhite:0.09 alpha:1.0];
}

+ (void)applyToNavigationBar:(UINavigationBar *)bar {
    if (!bar) return;
    if ([bar respondsToSelector:@selector(setBarTintColor:)]) {
        // iOS 7+: barTintColor paints the bar itself, tintColor the buttons.
        if ([bar respondsToSelector:@selector(setBarStyle:)]) {
            [bar setBarStyle:[self isLight] ? UIBarStyleDefault : UIBarStyleBlack];
        }
        [bar setBarTintColor:[self navigationBarColor]];
        [bar setTintColor:[self accentColor]];
    } else {
        // UINavigationBar has supported tintColor since iOS 5, where it paints
        // the whole bar over the classic gradient.
        if ([bar respondsToSelector:@selector(setBarStyle:)]) [bar setBarStyle:UIBarStyleDefault];
        [bar setTintColor:[self navigationBarColor]];
    }
    [bar setTitleTextAttributes:@{
        UITextAttributeTextColor: [self primaryTextColor],
        UITextAttributeFont: [UIFont boldSystemFontOfSize:17]
    }];
    [bar setNeedsDisplay];
}

+ (void)applyToTabBar:(UITabBar *)tab {
    if (!tab) return;
    if ([tab respondsToSelector:@selector(setBarTintColor:)]) {
        // iOS 7+: barTintColor paints the bar, tintColor the selected item.
        if ([tab respondsToSelector:@selector(setBarStyle:)]) {
            [tab setBarStyle:[self isLight] ? UIBarStyleDefault : UIBarStyleBlack];
        }
        [tab setBarTintColor:[self tabBarColor]];
        [tab setTintColor:[self accentColor]];
    } else {
        // UITabBar did not inherit tintColor until iOS 7. On iOS 5/6 use its
        // dedicated selectedImageTintColor API instead; sending tintColor here
        // raises an unrecognized-selector exception at launch.
        if ([tab respondsToSelector:@selector(setBarStyle:)]) [tab setBarStyle:UIBarStyleDefault];
        if ([tab respondsToSelector:@selector(setSelectedImageTintColor:)]) {
            [tab setSelectedImageTintColor:[self accentColor]];
        }
    }
    [tab setNeedsDisplay];
}

// Re-tint every bar already in the hierarchy. Appearance proxies only affect
// views created afterwards, and on iOS 6 a tint change does not always trigger
// a redraw by itself - walk the tree and repaint what is on screen now.
+ (void)applyToBarsInView:(UIView *)view {
    if (!view) return;
    if ([view isKindOfClass:[UINavigationBar class]]) {
        [self applyToNavigationBar:(UINavigationBar *)view];
    } else if ([view isKindOfClass:[UITabBar class]]) {
        [self applyToTabBar:(UITabBar *)view];
    } else if ([view isKindOfClass:[UIToolbar class]]) {
        UIToolbar *toolbar = (UIToolbar *)view;
        if ([toolbar respondsToSelector:@selector(setBarTintColor:)]) {
            [toolbar setBarTintColor:[self navigationBarColor]];
        } else {
            [toolbar setTintColor:[self navigationBarColor]];
        }
        [toolbar setNeedsDisplay];
    }
    for (UIView *subview in view.subviews) [self applyToBarsInView:subview];
}

+ (void)applyApplicationAppearance {
    // UIAppearance is a forwarding proxy, so its respondsToSelector: result
    // cannot be used to determine whether a selector exists on iOS 6. Bars
    // already in the window are styled by applyToBarsInView:. Newer systems
    // may additionally use the proxy after checking the concrete classes.
    if ([UINavigationBar instancesRespondToSelector:@selector(setBarTintColor:)]) {
        UINavigationBar *bar = [UINavigationBar appearance];
        [bar setBarTintColor:[self navigationBarColor]];
        [bar setTintColor:[self accentColor]];
        [bar setTitleTextAttributes:@{
            UITextAttributeTextColor: [self primaryTextColor],
            UITextAttributeFont: [UIFont boldSystemFontOfSize:17]
        }];
    }
    if ([UITabBar instancesRespondToSelector:@selector(setBarTintColor:)]) {
        UITabBar *tab = [UITabBar appearance];
        [tab setBarTintColor:[self tabBarColor]];
        [tab setTintColor:[self accentColor]];
    }
}

+ (void)prepareViewController:(UIViewController *)viewController {
    viewController.view.backgroundColor = [self libraryBackgroundColor];
    if ([viewController respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [viewController setEdgesForExtendedLayout:UIRectEdgeNone];
    }
}

@end
