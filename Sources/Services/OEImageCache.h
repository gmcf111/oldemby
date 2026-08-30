#import <UIKit/UIKit.h>

// In-memory NSCache (iOS 6 compatible)
@interface OEImageCache : NSObject

+ (instancetype)sharedCache;

- (void)loadImageFromURL:(NSString *)url placeholder:(UIImage *)placeholder completion:(void(^)(UIImage *image))completion;
- (void)clear;

@end
