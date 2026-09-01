#import "OEEmbyItem.h"

@implementation OEEmbyItem

+ (BOOL)isSupportedEmbeddedLyricsStream:(NSDictionary *)stream {
    if (![stream isKindOfClass:[NSDictionary class]]) return NO;
    NSString *type = [stream[@"Type"] isKindOfClass:[NSString class]] ? stream[@"Type"] : @"";
    if (![type isEqualToString:@"Subtitle"] || [stream[@"IsExternal"] boolValue]) return NO;
    id rawIndex = stream[@"Index"];
    if (![rawIndex respondsToSelector:@selector(integerValue)] || [rawIndex integerValue] < 0) return NO;
    if ([stream[@"IsTextSubtitleStream"] boolValue]) return YES;
    // Older Emby releases do not populate IsTextSubtitleStream for audio.
    // In that case accept only known text codecs, never image subtitles.
    NSString *codec = [stream[@"Codec"] isKindOfClass:[NSString class]] ? [stream[@"Codec"] lowercaseString] : @"";
    return [@[@"lrc", @"srt", @"subrip", @"vtt", @"webvtt", @"ass", @"ssa"] containsObject:codec];
}

+ (NSString *)supportedLyricsFormatForStream:(NSDictionary *)stream {
    // Emby's subtitle stream API transcodes compatible text tracks to SRT.
    return [self isSupportedEmbeddedLyricsStream:stream] ? @"srt" : nil;
}

+ (instancetype)itemWithDictionary:(NSDictionary *)dict {
    OEEmbyItem *it = [[OEEmbyItem alloc] init];
    id rawId = [dict objectForKey:@"Id"];
    id rawName = [dict objectForKey:@"Name"];
    id rawType = [dict objectForKey:@"Type"];
    it.itemId = [rawId isKindOfClass:[NSString class]] ? rawId : nil;
    it.name = [rawName isKindOfClass:[NSString class]] ? rawName : nil;
    it.type = [rawType isKindOfClass:[NSString class]] ? rawType : nil;
    it.itemType = [self typeFromString:it.type];
    it.embeddedLyricsStreamIndex = NSNotFound;
    id collectionType = [dict objectForKey:@"CollectionType"];
    it.collectionType = [collectionType isKindOfClass:[NSString class]] ? collectionType : nil;
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
    NSNumber *ratio = [dict objectForKey:@"PrimaryImageAspectRatio"];
    if ([ratio isKindOfClass:[NSNumber class]] && [ratio doubleValue] > 0) it.primaryImageAspectRatio = [ratio doubleValue];
    NSNumber *ticks = [dict objectForKey:@"RunTimeTicks"];
    if ([ticks isKindOfClass:[NSNumber class]]) it.runTimeTicks = [ticks longLongValue];
    if (it.itemType == OEEmbyItemTypeAudio) {
        NSArray *streams = [dict objectForKey:@"MediaStreams"];
        for (id value in streams) {
            if (![self isSupportedEmbeddedLyricsStream:value]) continue;
            NSString *format = [self supportedLyricsFormatForStream:value];
            if (!format.length) continue;
            it.embeddedLyricsStreamIndex = [value[@"Index"] integerValue];
            it.embeddedLyricsFormat = format;
            break;
        }
    }
    NSNumber *sn = [dict objectForKey:@"ParentIndexNumber"];
    if ([sn isKindOfClass:[NSNumber class]]) it.seasonNumber = [sn integerValue];
    NSNumber *en = [dict objectForKey:@"IndexNumber"];
    if ([en isKindOfClass:[NSNumber class]]) it.episodeNumber = [en integerValue];
    it.indexNumber = it.episodeNumber;
    id rawSeriesId = [dict objectForKey:@"SeriesId"];
    it.seriesId = [rawSeriesId isKindOfClass:[NSString class]] ? rawSeriesId : nil;
    if (!it.seriesId.length && (it.itemType == OEEmbyItemTypeSeason || it.itemType == OEEmbyItemTypeEpisode)) {
        id parentId = [dict objectForKey:@"ParentId"];
        if ([parentId isKindOfClass:[NSString class]]) it.seriesId = parentId;
    }
    id rawSeriesTag = [dict objectForKey:@"SeriesPrimaryImageTag"];
    it.seriesPrimaryImageTag = [rawSeriesTag isKindOfClass:[NSString class]] ? rawSeriesTag : nil;
    if (!it.seriesPrimaryImageTag.length) {
        id parentTag = [dict objectForKey:@"ParentPrimaryImageTag"];
        if ([parentTag isKindOfClass:[NSString class]]) it.seriesPrimaryImageTag = parentTag;
    }
    id rawSeriesName = [dict objectForKey:@"SeriesName"];
    it.seriesName = [rawSeriesName isKindOfClass:[NSString class]] ? rawSeriesName : nil;
    return it;
}

+ (OEEmbyItemType)typeFromString:(NSString *)s {
    if (!s) return OEEmbyItemTypeUnknown;
    if ([s isEqualToString:@"Movie"]) return OEEmbyItemTypeMovie;
    if ([s isEqualToString:@"Episode"]) return OEEmbyItemTypeEpisode;
    if ([s isEqualToString:@"Series"]) return OEEmbyItemTypeSeries;
    if ([s isEqualToString:@"Season"]) return OEEmbyItemTypeSeason;
    if ([s isEqualToString:@"Audio"]) return OEEmbyItemTypeAudio;
    if ([s isEqualToString:@"MusicAlbum"]) return OEEmbyItemTypeAlbum;
    if ([s isEqualToString:@"MusicArtist"]) return OEEmbyItemTypeArtist;
    if ([s isEqualToString:@"Folder"] || [s isEqualToString:@"CollectionFolder"]) return OEEmbyItemTypeFolder;
    return OEEmbyItemTypeUnknown;
}

- (NSString *)primaryImageURLWithHost:(NSString *)host maxWidth:(NSInteger)width {
    return [self primaryImageURLWithHost:host maxWidth:width maxHeight:0];
}

- (NSString *)primaryImageURLWithHost:(NSString *)host maxWidth:(NSInteger)width maxHeight:(NSInteger)height {
    if (!host) return nil;
    NSString *targetItemId = self.itemId;
    NSString *targetTag = self.imageTag;

    // 当自身没有封面且属于某个剧集时（例如某一季没有独立封面），默认回退到该剧集的封面
    if (!targetTag.length) {
        if (self.seriesId.length) {
            targetItemId = self.seriesId;
            targetTag = self.seriesPrimaryImageTag;
        } else {
            return nil;
        }
    }
    if (!targetItemId.length) return nil;

    NSString *base = host;
    while ([base hasSuffix:@"/"] && base.length > 1) base = [base substringToIndex:base.length - 1];
    BOOL hasEmbyPrefix = [base hasSuffix:@"/emby"];
    NSString *root = hasEmbyPrefix ? [base substringToIndex:base.length - 5] : base;
    NSString *escapedTag = targetTag.length ? (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (__bridge CFStringRef)targetTag, NULL, CFSTR(":/?#[]@!$&'()*+,;=%"), kCFStringEncodingUTF8)) : @"";
    NSMutableString *url = [NSMutableString stringWithFormat:@"%@/emby/Items/%@/Images/Primary?", root, targetItemId];
    if (escapedTag.length) {
        [url appendFormat:@"Tag=%@&", escapedTag];
    }
    [url appendFormat:@"maxWidth=%ld", (long)width];
    if (height > 0) [url appendFormat:@"&maxHeight=%ld", (long)height];
    [url appendString:@"&quality=90"];
    return url;
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
