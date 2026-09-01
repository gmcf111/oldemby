#import "OEImageCache.h"

@interface OEImageCache ()
@property (nonatomic, strong) NSCache *memCache;
@end

@implementation OEImageCache

+ (instancetype)sharedCache {
    static OEImageCache *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[OEImageCache alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _memCache = [[NSCache alloc] init];
        _memCache.countLimit = 80;
        // iPad 2 has 256MB RAM and runs alongside MobileSubstrate/keyboard
        // tweaks. Decoded posters (220x330 = ~290KB each) and 400x600 covers
        // (~1MB) blow past usable memory at the count limit alone, which
        // pushes the OS to purge UIImage backing data and eventually jetsam
        // the app. A ~20MB total cost cap lets NSCache evict decoded images
        // under pressure before the system does something drastic.
        _memCache.totalCostLimit = 20 * 1024 * 1024;
    }
    return self;
}

- (void)loadImageFromURL:(NSString *)url placeholder:(UIImage *)placeholder completion:(void(^)(UIImage *image))completion {
    if (!url) { if (completion) completion(placeholder); return; }
    UIImage *cached = [self.memCache objectForKey:url];
    if (cached) { if (completion) completion(cached); return; }

    NSURL *nsurl = [NSURL URLWithString:url];
    if (!nsurl) { if (completion) completion(placeholder); return; }

    NSURLRequest *req = [NSURLRequest requestWithURL:nsurl cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:15];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err){
        if (err || !data) { if (completion) completion(placeholder); return; }
        UIImage *img = [UIImage imageWithData:data];
        if (img) {
            NSInteger cost = (NSInteger)(img.size.width * img.size.height) * 4;
            if (cost <= 0) cost = 1;
            [self.memCache setObject:img forKey:url cost:cost];
        }
        if (completion) completion(img ?: placeholder);
    }];
}

- (void)clear { [self.memCache removeAllObjects]; }

@end
