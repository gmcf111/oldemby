#import "OEEmbyItem.h"

@implementation OEEmbyItem

+ (instancetype)itemWithDictionary:(NSDictionary *)dict {
    OEEmbyItem *it = [[OEEmbyItem alloc] init];
    it.itemId = [dict objectForKey:@"Id"];
    it.name = [dict objectForKey:@"Name"];
    it.type = [dict objectForKey:@"Type"];
    it.itemType = [self typeFromString:it.type];
    it.overview = [dict objectForKey:@"Overview"];
    it.album = [dict objectForKey:@"Album"];
    it.artist = [dict objectForKey:@"Artists"] ? [[dict objectForKey:@"Artists"] componentsJoinedByString:@", "] : [dict objectForKey:@"AlbumArtist"];
    // ImageTags -> Primary
    NSDictionary *tags = [dict objectForKey:@"ImageTags"];
    if ([tags isKindOfClass:[NSDictionary class]]) {
        it.imageTag = [tags objectForKey:@"Primary"];
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
    return [NSString stringWithFormat:@"%@/emby/Items/%@/Images/Primary?Tag=%@&maxWidth=%ld&quality=90", base, self.itemId, self.imageTag, (long)width];
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
