#import "OECastItem.h"

@implementation OECastItem

+ (instancetype)castWithDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    OECastItem *c = [[OECastItem alloc] init];
    id rawId = [dict objectForKey:@"Id"];
    id rawName = [dict objectForKey:@"Name"];
    id rawRole = [dict objectForKey:@"Role"];
    id rawType = [dict objectForKey:@"Type"];
    c.personId = [rawId isKindOfClass:[NSString class]] ? rawId : nil;
    c.name = [rawName isKindOfClass:[NSString class]] ? rawName : nil;
    c.role = [rawRole isKindOfClass:[NSString class]] ? rawRole : nil;
    c.type = [rawType isKindOfClass:[NSString class]] ? rawType : nil;
    // Emby returns "PrimaryImageTag" as a string on People items.
    id primaryTag = [dict objectForKey:@"PrimaryImageTag"];
    c.primaryImageTag = [primaryTag isKindOfClass:[NSString class]] ? primaryTag : nil;
    id ratio = [dict objectForKey:@"PrimaryImageAspectRatio"];
    if ([ratio isKindOfClass:[NSNumber class]] && [ratio doubleValue] > 0) {
        c.primaryImageAspectRatio = [ratio doubleValue];
    }
    return c;
}

- (NSString *)primaryImageURLWithHost:(NSString *)host maxWidth:(NSInteger)width {
    if (!self.personId || !self.primaryImageTag) return nil;
    if (!host) return nil;
    NSString *base = host;
    while ([base hasSuffix:@"/"] && base.length > 1) base = [base substringToIndex:base.length - 1];
    BOOL hasEmbyPrefix = [base hasSuffix:@"/emby"];
    NSString *root = hasEmbyPrefix ? [base substringToIndex:base.length - 5] : base;
    NSString *escapedTag = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL,
        (__bridge CFStringRef)self.primaryImageTag, NULL,
        CFSTR(":/?#[]@!$&'()*+,;=%"), kCFStringEncodingUTF8));
    return [NSString stringWithFormat:@"%@/emby/Items/%@/Images/Primary?Tag=%@&maxWidth=%ld&quality=90",
            root, self.personId, escapedTag ?: @"", (long)width];
}

@end
