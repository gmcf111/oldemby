#import <UIKit/UIKit.h>

// Simple in-memory + disk cache, NSURLConnection based (iOS 6 compatible)
@interface OEImageCache : NSObject

+ (instancetype)sharedCache;

- (void)loadImageFromURL:(NSString *)url placeholder:(UIImage *)placeholder completion:(void(^)(UIImage *image))completion;
- (void)clear;

@end
