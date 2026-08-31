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
+ (void)prepareViewController:(UIViewController *)viewController;

@end
