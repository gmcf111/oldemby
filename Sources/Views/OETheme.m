#import "OETheme.h"

@implementation OETheme

+ (UIColor *)libraryBackgroundColor { return [UIColor colorWithRed:0.075 green:0.082 blue:0.098 alpha:1.0]; }
+ (UIColor *)navigationBarColor { return [UIColor colorWithRed:0.105 green:0.114 blue:0.133 alpha:1.0]; }
+ (UIColor *)tabBarColor { return [UIColor colorWithRed:0.090 green:0.098 blue:0.118 alpha:1.0]; }
+ (UIColor *)cellColor { return [UIColor colorWithRed:0.115 green:0.125 blue:0.148 alpha:1.0]; }
+ (UIColor *)primaryTextColor { return [UIColor colorWithWhite:0.94 alpha:1.0]; }
+ (UIColor *)secondaryTextColor { return [UIColor colorWithWhite:0.63 alpha:1.0]; }
+ (UIColor *)accentColor { return [UIColor colorWithRed:0.20 green:0.62 blue:0.93 alpha:1.0]; }
+ (UIColor *)separatorColor { return [UIColor colorWithWhite:0.23 alpha:1.0]; }

+ (void)applyApplicationAppearance {
    UINavigationBar *bar = [UINavigationBar appearance];
    if ([bar respondsToSelector:@selector(setBarStyle:)]) [bar setBarStyle:UIBarStyleBlack];
    if ([bar respondsToSelector:@selector(setBarTintColor:)]) [bar setBarTintColor:[self navigationBarColor]];
    if ([bar respondsToSelector:@selector(setTintColor:)]) [bar setTintColor:[self accentColor]];
    [bar setTitleTextAttributes:@{
        UITextAttributeTextColor: [self primaryTextColor],
        UITextAttributeFont: [UIFont boldSystemFontOfSize:17]
    }];

    UITabBar *tab = [UITabBar appearance];
    if ([tab respondsToSelector:@selector(setBarStyle:)]) [tab setBarStyle:UIBarStyleBlack];
    if ([tab respondsToSelector:@selector(setBarTintColor:)]) [tab setBarTintColor:[self tabBarColor]];
    if ([tab respondsToSelector:@selector(setTintColor:)]) [tab setTintColor:[self accentColor]];
}

+ (void)prepareViewController:(UIViewController *)viewController {
    viewController.view.backgroundColor = [self libraryBackgroundColor];
    if ([viewController respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [viewController setEdgesForExtendedLayout:UIRectEdgeNone];
    }
}

@end
