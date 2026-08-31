#import "OETheme.h"
#import "Constants.h"

@implementation OETheme

+ (OEThemeMode)themeMode {
    NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsThemeMode];
    if (![saved isKindOfClass:[NSNumber class]]) return OEThemeModeDark;
    return [saved integerValue] == OEThemeModeLight ? OEThemeModeLight : OEThemeModeDark;
}

+ (void)setThemeMode:(OEThemeMode)mode {
    if (mode == [self themeMode]) return;
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kDefaultsThemeMode];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationThemeDidChange object:nil];
}

+ (BOOL)isLight { return [self themeMode] == OEThemeModeLight; }

// iOS 6-era neutrals: silver bars in light mode, warm espresso in dark mode.
// Deliberately neither the default blue-gray nor pure black.
+ (UIColor *)libraryBackgroundColor {
    return [self isLight] ? [UIColor colorWithWhite:0.93 alpha:1.0]
                          : [UIColor colorWithRed:0.115 green:0.100 blue:0.090 alpha:1.0];
}
+ (UIColor *)navigationBarColor {
    return [self isLight] ? [UIColor colorWithRed:0.82 green:0.83 blue:0.86 alpha:1.0]
                          : [UIColor colorWithRed:0.255 green:0.220 blue:0.195 alpha:1.0];
}
+ (UIColor *)tabBarColor {
    return [self isLight] ? [UIColor colorWithRed:0.80 green:0.81 blue:0.84 alpha:1.0]
                          : [UIColor colorWithRed:0.225 green:0.195 blue:0.175 alpha:1.0];
}
+ (UIColor *)cellColor {
    return [self isLight] ? [UIColor whiteColor]
                          : [UIColor colorWithRed:0.175 green:0.150 blue:0.135 alpha:1.0];
}
+ (UIColor *)primaryTextColor {
    return [self isLight] ? [UIColor colorWithWhite:0.13 alpha:1.0]
                          : [UIColor colorWithWhite:0.94 alpha:1.0];
}
+ (UIColor *)secondaryTextColor {
    return [self isLight] ? [UIColor colorWithWhite:0.46 alpha:1.0]
                          : [UIColor colorWithWhite:0.63 alpha:1.0];
}
+ (UIColor *)accentColor { return [UIColor colorWithRed:0.78 green:0.36 blue:0.12 alpha:1.0]; }
+ (UIColor *)separatorColor {
    return [self isLight] ? [UIColor colorWithWhite:0.80 alpha:1.0]
                          : [UIColor colorWithWhite:0.23 alpha:1.0];
}
+ (UIColor *)imagePlaceholderColor {
    return [self isLight] ? [UIColor colorWithWhite:0.88 alpha:1.0]
                          : [UIColor colorWithRed:0.090 green:0.075 blue:0.065 alpha:1.0];
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
        // iOS 5/6: tintColor paints the whole bar. Use the bar color (never
        // the blue accent) over the classic default gradient; UIBarStyleBlack
        // would force the black look we are avoiding.
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
        // iOS 5/6: tintColor paints the whole bar; the selected-tab glow is
        // selectedImageTintColor. Again use the bar color, not the accent.
        if ([tab respondsToSelector:@selector(setBarStyle:)]) [tab setBarStyle:UIBarStyleDefault];
        [tab setTintColor:[self tabBarColor]];
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
    [self applyToNavigationBar:[UINavigationBar appearance]];
    [self applyToTabBar:[UITabBar appearance]];
}

+ (void)prepareViewController:(UIViewController *)viewController {
    viewController.view.backgroundColor = [self libraryBackgroundColor];
    if ([viewController respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [viewController setEdgesForExtendedLayout:UIRectEdgeNone];
    }
}

@end
