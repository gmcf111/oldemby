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
        if (img) [self.memCache setObject:img forKey:url];
        if (completion) completion(img ?: placeholder);
    }];
}

- (void)clear { [self.memCache removeAllObjects]; }

@end
