#import <UIKit/UIKit.h>

@interface OETheme : NSObject

+ (UIColor *)libraryBackgroundColor;
+ (UIColor *)navigationBarColor;
+ (UIColor *)tabBarColor;
+ (UIColor *)cellColor;
+ (UIColor *)primaryTextColor;
+ (UIColor *)secondaryTextColor;
+ (UIColor *)accentColor;
+ (UIColor *)separatorColor;
+
++ (void)applyApplicationAppearance;
++ (void)prepareViewController:(UIViewController *)viewController;
+
@end
