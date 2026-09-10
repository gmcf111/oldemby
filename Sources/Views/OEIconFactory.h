#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, OEIconType) {
    OEIconTypeVideo = 0,
    OEIconTypeMusic,
    OEIconTypeSettings,
    OEIconTypePlay,
    OEIconTypePause,
    OEIconTypePrevious,
    OEIconTypeNext,
    OEIconTypeChevronDown,
    OEIconTypeHeart,
    OEIconTypeHeartFilled,
    OEIconTypeRepeat,      // play mode: repeat all (loop)
    OEIconTypeRepeatOne,   // play mode: repeat one (loop + "1")
    OEIconTypeRepeatOff,   // play mode: no repeat (loop, slashed)
    OEIconTypeList,
    OEIconTypeSearch
};

@interface OEIconFactory : NSObject

+ (UIImage *)imageForIconType:(OEIconType)type size:(CGSize)size color:(UIColor *)color;

@end
