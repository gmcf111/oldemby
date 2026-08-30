#import "OEEmbyItem.h"

@implementation OEEmbyItem

+ (instancetype)itemWithDictionary:(NSDictionary *)dict {
    OEEmbyItem *it = [[OEEmbyItem alloc] init];
    id rawId = [dict objectForKey:@"Id"];
    id rawName = [dict objectForKey:@"Name"];
    id rawType = [dict objectForKey:@"Type"];
    it.itemId = [rawId isKindOfClass:[NSString class]] ? rawId : nil;
    it.name = [rawName isKindOfClass:[NSString class]] ? rawName : nil;
    it.type = [rawType isKindOfClass:[NSString class]] ? rawType : nil;
    it.itemType = [self typeFromString:it.type];
    id overview = [dict objectForKey:@"Overview"];
    id album = [dict objectForKey:@"Album"];
    it.overview = [overview isKindOfClass:[NSString class]] ? overview : nil;
    it.album = [album isKindOfClass:[NSString class]] ? album : nil;
    id artists = [dict objectForKey:@"Artists"];
    if ([artists isKindOfClass:[NSArray class]]) {
        NSMutableArray *names = [NSMutableArray array];
        for (id value in artists) {
            if ([value isKindOfClass:[NSString class]] && [value length]) {
                [names addObject:value];
            }
        }
        it.artist = names.count ? [names componentsJoinedByString:@", "] : nil;
    } else {
        id albumArtist = [dict objectForKey:@"AlbumArtist"];
        it.artist = [albumArtist isKindOfClass:[NSString class]] ? albumArtist : nil;
    }
    // ImageTags -> Primary
    NSDictionary *tags = [dict objectForKey:@"ImageTags"];
    if ([tags isKindOfClass:[NSDictionary class]]) {
        id primaryTag = [tags objectForKey:@"Primary"];
        it.imageTag = [primaryTag isKindOfClass:[NSString class]] ? primaryTag : nil;
    }
    NSNumber *ticks = [dict objectForKey:@"RunTimeTicks"];
    if ([ticks isKindOfClass:[NSNumber class]]) it.runTimeTicks = [ticks longLongValue];
    NSNumber *sn = [dict objectForKey:@"ParentIndexNumber"];
    if ([sn isKindOfClass:[NSNumber class]]) it.seasonNumber = [sn integerValue];
    NSNumber *en = [dict objectForKey:@"IndexNumber"];
    if ([en isKindOfClass:[NSNumber class]]) it.episodeNumber = [en integerValue];
    return it;
}

+ (OEEmbyItemType)typeFromString:(NSString *)s {
    if (!s) return OEEmbyItemTypeUnknown;
    if ([s isEqualToString:@"Movie"]) return OEEmbyItemTypeMovie;
    if ([s isEqualToString:@"Episode"]) return OEEmbyItemTypeEpisode;
    if ([s isEqualToString:@"Series"]) return OEEmbyItemTypeSeries;
    if ([s isEqualToString:@"Audio"]) return OEEmbyItemTypeAudio;
    if ([s isEqualToString:@"MusicAlbum"]) return OEEmbyItemTypeAlbum;
    if ([s isEqualToString:@"MusicArtist"]) return OEEmbyItemTypeArtist;
    if ([s isEqualToString:@"Folder"] || [s isEqualToString:@"CollectionFolder"]) return OEEmbyItemTypeFolder;
    return OEEmbyItemTypeUnknown;
}

- (NSString *)primaryImageURLWithHost:(NSString *)host maxWidth:(NSInteger)width {
    if (!self.itemId || !self.imageTag) return nil;
    if (!host) return nil;
    NSString *base = host;
    while ([base hasSuffix:@"/"] && base.length>1) base=[base substringToIndex:base.length-1];
    // Emby image endpoint: /emby/Items/{Id}/Images/Primary?Tag=xxx&maxWidth=...
    // Use emby-style; legacy /emby prefix is optional but Emby 4.x prefers /emby
    // Hosts may already include the conventional /emby API prefix.
    BOOL hasEmbyPrefix = [base hasSuffix:@"/emby"];
    NSString *root = hasEmbyPrefix ? [base substringToIndex:base.length - 5] : base;
    NSString *escapedTag = self.imageTag ? (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (__bridge CFStringRef)self.imageTag, NULL, CFSTR(":/?#[]@!$&'()*+,;=%"), kCFStringEncodingUTF8)) : @"";
    return [NSString stringWithFormat:@"%@/emby/Items/%@/Images/Primary?Tag=%@&maxWidth=%ld&quality=90", root, self.itemId, escapedTag ?: @"", (long)width];
}

- (NSString *)displayDuration {
    if (self.runTimeTicks <=0) return @"--:--";
    long long seconds = self.runTimeTicks / 10000000LL;
    NSInteger m = seconds / 60;
    NSInteger s = seconds % 60;
    if (m >= 60) {
        NSInteger h = m/60;
        m = m%60;
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

@end
