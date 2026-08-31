#import <UIKit/UIKit.h>
@class UINavigationController;

@interface OERootTabBarController : UITabBarController <UITabBarControllerDelegate>

- (instancetype)initWithMusicNavigationController:(UINavigationController *)musicNavigationController;

@end
