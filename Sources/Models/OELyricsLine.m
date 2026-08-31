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

+ (NSArray *)linesFromTextSubtitleString:(NSString *)text {
    NSArray *lrcLines = [self linesFromLRCString:text];
    if (lrcLines.count) return lrcLines;
    if (![text isKindOfClass:[NSString class]] || !text.length) return @[];

    NSMutableArray *lines = [NSMutableArray array];
    NSArray *sourceLines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSInteger index = 0; index < (NSInteger)sourceLines.count; index++) {
        NSString *rawLine = [sourceLines[index] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([rawLine hasPrefix:@"Dialogue:"]) {
            NSArray *fields = [[rawLine substringFromIndex:[@"Dialogue:" length]] componentsSeparatedByString:@","];
            if (fields.count >= 10) {
                NSArray *parts = [[fields[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsSeparatedByString:@":"];
                if (parts.count == 3) {
                    NSTimeInterval seconds = [parts[0] doubleValue] * 3600.0 + [parts[1] doubleValue] * 60.0 + [parts[2] doubleValue];
                    NSString *lineText = [[fields subarrayWithRange:NSMakeRange(9, fields.count - 9)] componentsJoinedByString:@","];
                    lineText = [[lineText stringByReplacingOccurrencesOfString:@"\\N" withString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (lineText.length && seconds >= 0) {
                        OELyricsLine *line = [[OELyricsLine alloc] init];
                        line.startTime = seconds;
                        line.text = lineText;
                        [lines addObject:line];
                    }
                }
            }
            continue;
        }
        NSString *timeLine = [rawLine stringByReplacingOccurrencesOfString:@"," withString:@"."];
        if ([timeLine hasPrefix:@"WEBVTT"] || [timeLine rangeOfString:@"-->"].location == NSNotFound) continue;
        NSArray *range = [timeLine componentsSeparatedByString:@"-->"];
        if (range.count != 2) continue;
        NSArray *parts = [[range[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsSeparatedByString:@":"];
        if (parts.count < 2 || parts.count > 3) continue;
        NSTimeInterval seconds = [[parts lastObject] doubleValue] + [parts[parts.count - 2] doubleValue] * 60.0;
        if (parts.count == 3) seconds += [parts[0] doubleValue] * 3600.0;
        NSMutableArray *textParts = [NSMutableArray array];
        while (++index < (NSInteger)sourceLines.count) {
            NSString *candidate = [sourceLines[index] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!candidate.length) break;
            [textParts addObject:candidate];
        }
        NSString *lineText = [[textParts componentsJoinedByString:@" "] stringByReplacingOccurrencesOfString:@"<i>" withString:@""];
        lineText = [lineText stringByReplacingOccurrencesOfString:@"</i>" withString:@""];
        if (!lineText.length || seconds < 0) continue;
        OELyricsLine *line = [[OELyricsLine alloc] init];
        line.startTime = seconds;
        line.text = lineText;
        [lines addObject:line];
    }
    return lines;
}

@end
