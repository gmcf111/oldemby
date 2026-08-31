#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, OEIconType) {
    OEIconTypeVideo = 0,
    OEIconTypeMusic,
    OEIconTypeSettings,
    OEIconTypePlay,
    OEIconTypePause,
    OEIconTypePrevious,
    OEIconTypeNext
};

@interface OEIconFactory : NSObject

+ (UIImage *)imageForIconType:(OEIconType)type size:(CGSize)size color:(UIColor *)color;

@end
