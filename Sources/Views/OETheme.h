#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, OEThemeMode) {
    OEThemeModeDark = 0,
    OEThemeModeLight = 1
};

@interface OETheme : NSObject

// Current mode, persisted in NSUserDefaults. setThemeMode: posts
// kNotificationThemeDidChange so live views can re-apply colors.
+ (OEThemeMode)themeMode;
+ (void)setThemeMode:(OEThemeMode)mode;

+ (UIColor *)libraryBackgroundColor;
+ (UIColor *)navigationBarColor;
+ (UIColor *)tabBarColor;
+ (UIColor *)cellColor;
+ (UIColor *)primaryTextColor;
+ (UIColor *)secondaryTextColor;
+ (UIColor *)accentColor;
+ (UIColor *)separatorColor;
+ (UIColor *)imagePlaceholderColor;

+ (void)applyApplicationAppearance;
+ (void)applyToNavigationBar:(UINavigationBar *)bar;
+ (void)applyToTabBar:(UITabBar *)tabBar;
// Recursively re-tint every nav/tab/tool bar already in the hierarchy; needed
// because appearance proxies only reach views created after the theme change.
+ (void)applyToBarsInView:(UIView *)view;
+ (void)prepareViewController:(UIViewController *)viewController;

@end
