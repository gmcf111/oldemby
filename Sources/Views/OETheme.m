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

+ (UIColor *)libraryBackgroundColor {
    return [self isLight] ? [UIColor colorWithWhite:0.94 alpha:1.0]
                          : [UIColor colorWithRed:0.075 green:0.082 blue:0.098 alpha:1.0];
}
+ (UIColor *)navigationBarColor {
    return [self isLight] ? [UIColor colorWithWhite:0.98 alpha:1.0]
                          : [UIColor colorWithRed:0.105 green:0.114 blue:0.133 alpha:1.0];
}
+ (UIColor *)tabBarColor {
    return [self isLight] ? [UIColor colorWithWhite:0.98 alpha:1.0]
                          : [UIColor colorWithRed:0.090 green:0.098 blue:0.118 alpha:1.0];
}
+ (UIColor *)cellColor {
    return [self isLight] ? [UIColor whiteColor]
                          : [UIColor colorWithRed:0.115 green:0.125 blue:0.148 alpha:1.0];
}
+ (UIColor *)primaryTextColor {
    return [self isLight] ? [UIColor colorWithWhite:0.13 alpha:1.0]
                          : [UIColor colorWithWhite:0.94 alpha:1.0];
}
+ (UIColor *)secondaryTextColor {
    return [self isLight] ? [UIColor colorWithWhite:0.46 alpha:1.0]
                          : [UIColor colorWithWhite:0.63 alpha:1.0];
}
+ (UIColor *)accentColor { return [UIColor colorWithRed:0.20 green:0.62 blue:0.93 alpha:1.0]; }
+ (UIColor *)separatorColor {
    return [self isLight] ? [UIColor colorWithWhite:0.80 alpha:1.0]
                          : [UIColor colorWithWhite:0.23 alpha:1.0];
}
+ (UIColor *)imagePlaceholderColor {
    return [self isLight] ? [UIColor colorWithWhite:0.88 alpha:1.0]
                          : [UIColor colorWithWhite:0.055 alpha:1.0];
}

+ (void)applyToNavigationBar:(UINavigationBar *)bar {
    if (!bar) return;
    if ([bar respondsToSelector:@selector(setBarStyle:)]) {
        [bar setBarStyle:[self isLight] ? UIBarStyleDefault : UIBarStyleBlack];
    }
    if ([bar respondsToSelector:@selector(setBarTintColor:)]) [bar setBarTintColor:[self navigationBarColor]];
    if ([bar respondsToSelector:@selector(setTintColor:)]) [bar setTintColor:[self accentColor]];
    [bar setTitleTextAttributes:@{
        UITextAttributeTextColor: [self primaryTextColor],
        UITextAttributeFont: [UIFont boldSystemFontOfSize:17]
    }];
}

+ (void)applyToTabBar:(UITabBar *)tab {
    if (!tab) return;
    if ([tab respondsToSelector:@selector(setBarStyle:)]) {
        [tab setBarStyle:[self isLight] ? UIBarStyleDefault : UIBarStyleBlack];
    }
    if ([tab respondsToSelector:@selector(setBarTintColor:)]) [tab setBarTintColor:[self tabBarColor]];
    if ([tab respondsToSelector:@selector(setTintColor:)]) [tab setTintColor:[self accentColor]];
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
