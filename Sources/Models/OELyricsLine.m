#import "OELyricsLine.h"

@implementation OELyricsLine

+ (NSArray *)linesFromEmbyResponse:(id)response {
    if (![response isKindOfClass:[NSDictionary class]]) return @[];
    id lyrics = response[@"Lyrics"];
    if (![lyrics isKindOfClass:[NSArray class]]) {
        // Emby has returned both an object with Lyrics and a raw LRC string
        // across server releases; accept the common field names.
        id lrc = response[@"Text"];
        if (![lrc isKindOfClass:[NSString class]]) lrc = response[@"LyricsText"];
        if (![lrc isKindOfClass:[NSString class]]) lrc = response[@"Lyrics"];
        return [lrc isKindOfClass:[NSString class]] ? [self linesFromLRCString:lrc] : @[];
    }

    NSMutableArray *lines = [NSMutableArray array];
    for (id value in lyrics) {
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        NSString *text = [value[@"Text"] isKindOfClass:[NSString class]] ? value[@"Text"] : @"";
        id ticks = value[@"Start"] ?: value[@"StartPositionTicks"];
        NSTimeInterval time = [ticks respondsToSelector:@selector(doubleValue)] ? [ticks doubleValue] / 10000000.0 : -1;
        if (text.length && time >= 0) {
            OELyricsLine *line = [[OELyricsLine alloc] init];
            line.startTime = time;
            line.text = text;
            [lines addObject:line];
        }
    }
    [lines sortUsingComparator:^NSComparisonResult(OELyricsLine *left, OELyricsLine *right) {
        if (left.startTime < right.startTime) return NSOrderedAscending;
        if (left.startTime > right.startTime) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return lines;
}

+ (NSArray *)linesFromLRCString:(NSString *)lrc {
    if (![lrc isKindOfClass:[NSString class]] || !lrc.length) return @[];
    NSMutableArray *lines = [NSMutableArray array];
    NSArray *sourceLines = [lrc componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *source in sourceLines) {
        NSRange close = [source rangeOfString:@"]"];
        if (![source hasPrefix:@"["] || close.location == NSNotFound || close.location < 4) continue;
        NSString *timeString = [source substringWithRange:NSMakeRange(1, close.location - 1)];
        NSArray *parts = [timeString componentsSeparatedByString:@":"];
        if (parts.count != 2) continue;
        NSTimeInterval minute = [parts[0] doubleValue];
        NSTimeInterval second = [parts[1] doubleValue];
        NSString *text = [[source substringFromIndex:close.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (minute < 0 || second < 0 || !text.length) continue;
        OELyricsLine *line = [[OELyricsLine alloc] init];
        line.startTime = minute * 60.0 + second;
        line.text = text;
        [lines addObject:line];
    }
    [lines sortUsingComparator:^NSComparisonResult(OELyricsLine *left, OELyricsLine *right) {
        if (left.startTime < right.startTime) return NSOrderedAscending;
        if (left.startTime > right.startTime) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return lines;
}

@end
