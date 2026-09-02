#import "OESRTSubtitleParser.h"

@implementation OESubtitleCue
@end

#pragma mark - Time Parsing Helpers

// Parse a time string in H:MM:SS,mmm or H:MM:SS.mmm format into seconds.
// Handles both SRT (comma ms) and VTT (dot ms) styles.
static NSTimeInterval parseTimecode(NSString *s) {
    if (!s.length) return 0;
    NSString *normalized = [s stringByReplacingOccurrencesOfString:@"," withString:@"."];
    NSArray *parts = [normalized componentsSeparatedByString:@":"];
    if (parts.count == 3) {
        double h = [parts[0] doubleValue];
        double m = [parts[1] doubleValue];
        double sec = [parts[2] doubleValue];
        return h * 3600.0 + m * 60.0 + sec;
    }
    // VTT cues may omit hours: MM:SS.mmm
    if (parts.count == 2) {
        double m = [parts[0] doubleValue];
        double sec = [parts[1] doubleValue];
        return m * 60.0 + sec;
    }
    return [normalized doubleValue];
}

// Parse ASS/SSA time string "H:MM:SS.cc" (centiseconds, not milliseconds)
// into seconds. e.g. "0:00:01.50" → 1.5 seconds.
static NSTimeInterval parseASSTime(NSString *s) {
    if (!s.length) return 0;
    NSArray *parts = [[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsSeparatedByString:@":"];
    if (parts.count != 3) return 0;
    double h = [parts[0] doubleValue];
    double m = [parts[1] doubleValue];
    double sec = [parts[2] doubleValue];
    return h * 3600.0 + m * 60.0 + sec;
}

// Parse LRC time tag "[mm:ss.xx]" or "[mm:ss.xxx]" into seconds.
static NSTimeInterval parseLRCTimeTag(NSString *tag) {
    // tag is like "01:23.45" (without brackets)
    NSArray *parts = [tag componentsSeparatedByString:@":"];
    if (parts.count != 2) return -1;
    double m = [parts[0] doubleValue];
    double sec = [parts[1] doubleValue];
    return m * 60.0 + sec;
}

#pragma mark - SRT Parser

+ (NSArray *)parseSRT:(NSString *)srtText {
    if (!srtText.length) return nil;

    NSString *text = [srtText stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray *lines = [text componentsSeparatedByString:@"\n"];

    NSMutableArray *cues = [NSMutableArray array];
    NSInteger i = 0;
    NSInteger count = lines.count;

    while (i < count) {
        while (i < count && [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) i++;
        if (i >= count) break;

        NSString *line = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
        BOOL isNumber = line.length > 0 && [line stringByTrimmingCharactersInSet:digits].length == 0;
        if (isNumber) {
            i++;
            if (i >= count) break;
        }

        NSString *timeLine = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![timeLine containsString:@"-->"]) { i++; continue; }
        i++;

        NSMutableString *cueText = [NSMutableString string];
        while (i < count) {
            NSString *tl = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (tl.length == 0) break;
            if (cueText.length > 0) [cueText appendString:@"\n"];
            [cueText appendString:tl];
            i++;
        }

        NSRange arrow = [timeLine rangeOfString:@"-->"];
        if (arrow.location == NSNotFound) continue;
        NSString *startStr = [[timeLine substringToIndex:arrow.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *endStr = [[timeLine substringFromIndex:NSMaxRange(arrow)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        NSTimeInterval start = parseTimecode(startStr);
        NSTimeInterval end = parseTimecode(endStr);
        if (cueText.length == 0) continue;

        OESubtitleCue *cue = [[OESubtitleCue alloc] init];
        cue.startTime = start;
        cue.endTime = end;
        cue.text = [cueText copy];
        [cues addObject:cue];
    }
    return cues.count ? cues : nil;
}

#pragma mark - VTT (WebVTT) Parser

+ (NSArray *)parseVTT:(NSString *)vttText {
    if (!vttText.length) return nil;

    // VTT may have a "WEBVTT" header line and optional STYLE/NOTE/CUE blocks.
    // The cue format is identical to SRT (time --> time) but without the
    // numeric index, and milliseconds use dots instead of commas.
    // Our SRT parser already handles dot-separated times and optional index,
    // so we can delegate to it after stripping the WEBVTT header.
    NSString *text = [vttText stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

    // Remove the WEBVTT header line (first non-empty line starting with "WEBVTT").
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableString *cleaned = [NSMutableString string];
    BOOL skippedHeader = NO;
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!skippedHeader && [trimmed.uppercaseString hasPrefix:@"WEBVTT"]) {
            skippedHeader = YES;
            continue;
        }
        // Skip STYLE, NOTE, REGION blocks entirely (text between the block
        // tag and the next blank line).
        if ([trimmed.uppercaseString hasPrefix:@"STYLE"] ||
            [trimmed.uppercaseString hasPrefix:@"NOTE"] ||
            [trimmed.uppercaseString hasPrefix:@"REGION"]) {
            continue;
        }
        [cleaned appendFormat:@"%@\n", line];
    }

    // Delegate to the SRT parser which handles the cue format.
    return [self parseSRT:cleaned];
}

#pragma mark - ASS/SSA Parser

// Strip ASS override tags like {\an8}, {\i1}, {\b1} from dialogue text.
// Keep the readable text, replacing tags that separate lines (\N, \n) with
// actual newlines.
static NSString *stripASSOverrides(NSString *text) {
    if (!text.length) return text;
    NSMutableString *result = [NSMutableString stringWithCapacity:text.length];
    NSUInteger len = text.length;
    NSUInteger i = 0;
    while (i < len) {
        unichar c = [text characterAtIndex:i];
        if (c == '{') {
            // Skip until matching '}'
            while (i < len && [text characterAtIndex:i] != '}') i++;
            if (i < len) i++; // skip '}'
        } else if (c == '\\') {
            // \N or \n → newline
            if (i + 1 < len) {
                unichar next = [text characterAtIndex:i + 1];
                if (next == 'N' || next == 'n') {
                    [result appendString:@"\n"];
                    i += 2;
                    continue;
                }
            }
            [result appendFormat:@"%c", c];
            i++;
        } else {
            [result appendFormat:@"%c", c];
            i++;
        }
    }
    // Trim leading/trailing whitespace
    return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSArray *)parseASS:(NSString *)assText {
    if (!assText.length) return nil;

    NSString *text = [assText stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray *lines = [text componentsSeparatedByString:@"\n"];

    // Find the [Events] section and parse the Format: line to determine
    // the column positions of Start, End, and Text.
    BOOL inEvents = NO;
    NSInteger startCol = 1;
    NSInteger endCol = 2;
    NSInteger textCol = 9;  // Default SSA format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

    NSMutableArray *cues = [NSMutableArray array];

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmed isEqualToString:@"[Events]"]) { inEvents = YES; continue; }
        if (!inEvents) continue;
        if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"] && ![trimmed isEqualToString:@"[Events]"]) {
            // Entered a different section
            inEvents = NO;
            continue;
        }

        // Parse Format: line to get column indices
        if ([trimmed hasPrefix:@"Format:"]) {
            NSString *formatDef = [[trimmed substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSArray *fields = [formatDef componentsSeparatedByString:@","];
            for (NSInteger c = 0; c < (NSInteger)fields.count; c++) {
                NSString *f = [[fields[c] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([f isEqualToString:@"start"]) startCol = c;
                else if ([f isEqualToString:@"end"]) endCol = c;
                else if ([f isEqualToString:@"text"]) textCol = c;
            }
            continue;
        }

        // Parse Dialogue: lines
        if (![trimmed hasPrefix:@"Dialogue:"]) continue;

        // Extract the part after "Dialogue:"
        NSString *dialogueContent = [trimmed substringFromIndex:9];
        // Split into fields. The Text field (last column) may contain commas,
        // so we split only up to textCol items and take the rest as text.
        NSArray *parts = [dialogueContent componentsSeparatedByString:@","];
        if ((NSInteger)parts.count <= textCol) continue;

        // The "Marked=" prefix (SSA format) may be on the first field.
        NSString *startStr = [[parts[startCol] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                              stringByReplacingOccurrencesOfString:@"Marked=" withString:@""];
        NSString *endStr = [parts[endCol] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        // Text is everything from textCol onwards, re-joined with commas.
        NSArray *textParts = [parts subarrayWithRange:NSMakeRange(textCol, parts.count - textCol)];
        NSString *rawText = [textParts componentsJoinedByString:@","];
        NSString *cueText = stripASSOverrides(rawText);
        if (!cueText.length) continue;

        NSTimeInterval start = parseASSTime(startStr);
        NSTimeInterval end = parseASSTime(endStr);
        if (end <= start) end = start + 2.0; // Fallback for malformed cues

        OESubtitleCue *cue = [[OESubtitleCue alloc] init];
        cue.startTime = start;
        cue.endTime = end;
        cue.text = cueText;
        [cues addObject:cue];
    }

    return cues.count ? cues : nil;
}

#pragma mark - LRC Parser

+ (NSArray *)parseLRC:(NSString *)lrcText {
    if (!lrcText.length) return nil;

    NSString *text = [lrcText stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray *lines = [text componentsSeparatedByString:@"\n"];

    NSMutableArray *cues = [NSMutableArray array];

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trimmed.length) continue;

        // Skip metadata tags like [ti:...], [ar:...], [al:...], [by:...]
        // but keep time tags like [00:01.23]
        if (![trimmed hasPrefix:@"["]) continue;

        // A line may have multiple time tags: [00:01.00][00:15.00]text
        // Extract all [mm:ss.xx] tags and the remaining text.
        NSMutableString *lyricText = [NSMutableString string];
        NSMutableArray *times = [NSMutableArray array];
        NSUInteger pos = 0;
        NSUInteger len = trimmed.length;

        while (pos < len) {
            unichar c = [trimmed characterAtIndex:pos];
            if (c == '[') {
                // Find matching ']'
                NSUInteger closePos = pos + 1;
                while (closePos < len && [trimmed characterAtIndex:closePos] != ']') closePos++;
                if (closePos >= len) break;
                NSString *tagContent = [trimmed substringWithRange:NSMakeRange(pos + 1, closePos - pos - 1)];
                // Check if this is a time tag (starts with a digit)
                if (tagContent.length > 0 && [tagContent characterAtIndex:0] >= '0' && [tagContent characterAtIndex:0] <= '9') {
                    NSTimeInterval t = parseLRCTimeTag(tagContent);
                    if (t >= 0) [times addObject:@(t)];
                }
                // Skip metadata tags ([ti:], [ar:], etc.)
                pos = closePos + 1;
            } else {
                // Everything after the last time tag is the lyric text
                [lyricText appendString:[trimmed substringFromIndex:pos]];
                break;
            }
        }

        if (!times.count || !lyricText.length) continue;

        NSString *cueText = [lyricText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!cueText.length) continue;

        for (NSNumber *timeNum in times) {
            NSTimeInterval start = [timeNum doubleValue];
            OESubtitleCue *cue = [[OESubtitleCue alloc] init];
            cue.startTime = start;
            cue.endTime = start + 5.0; // LRC has no end time; assume 5s display
            cue.text = cueText;
            [cues addObject:cue];
        }
    }

    // Sort by start time
    [cues sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        OESubtitleCue *c1 = obj1, *c2 = obj2;
        return c1.startTime > c2.startTime ? NSOrderedDescending :
               c1.startTime < c2.startTime ? NSOrderedAscending : NSOrderedSame;
    }];

    return cues.count ? cues : nil;
}

#pragma mark - SubViewer Parser

// SubViewer format comes in two variants:
//   1.x: "[INFINITE SYNC]" header, lines like "{start} {end}text"
//   2.x: time line "HH:MM:SS,mmm --> HH:MM:SS,mmm" (identical to SRT)
// The 2.x variant is handled by parseSRT: already. Here we handle 1.x.
+ (NSArray *)parseSubViewer:(NSString *)svText {
    if (!svText.length) return nil;

    NSString *text = [svText stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray *lines = [text componentsSeparatedByString:@"\n"];

    NSMutableArray *cues = [NSMutableArray array];

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trimmed.length) continue;

        // Skip header/metadata lines like [INFINITE SYNC], [TITLE], etc.
        if ([trimmed hasPrefix:@"["]) continue;

        // SubViewer 1.x format: {HH:MM:SS,mmm}{HH:MM:SS,mmm}text
        // The time is in curly braces, same as MicroDVD but with timestamp
        // instead of frame number.
        if (![trimmed hasPrefix:@"{"]) continue;

        // Extract content between first two } markers.
        NSUInteger firstClose = [trimmed rangeOfString:@"}"].location;
        if (firstClose == NSNotFound) continue;
        NSUInteger secondOpen = [trimmed rangeOfString:@"{" options:0 range:NSMakeRange(firstClose, trimmed.length - firstClose)].location;
        if (secondOpen == NSNotFound) continue;
        NSUInteger secondClose = [trimmed rangeOfString:@"}" options:0 range:NSMakeRange(secondOpen, trimmed.length - secondOpen)].location;
        if (secondClose == NSNotFound) continue;

        NSString *startStr = [trimmed substringWithRange:NSMakeRange(1, firstClose - 1)];
        NSString *endStr = [trimmed substringWithRange:NSMakeRange(secondOpen + 1, secondClose - secondOpen - 1)];
        NSString *cueText = [[trimmed substringFromIndex:secondClose + 1]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (!cueText.length) continue;

        // SubViewer times use HH:MM:SS,mmm format (same as SRT).
        // Some variants use just SS,mmm without hours/minutes.
        NSTimeInterval start = parseTimecode(startStr);
        NSTimeInterval end = parseTimecode(endStr);
        if (end <= start) end = start + 2.0;

        OESubtitleCue *cue = [[OESubtitleCue alloc] init];
        cue.startTime = start;
        cue.endTime = end;
        cue.text = cueText;
        [cues addObject:cue];
    }

    return cues.count ? cues : nil;
}

#pragma mark - MicroDVD Parser

// MicroDVD format uses frame numbers in curly braces:
//   {start_frame}{end_frame}text
// Frame numbers are integers. We convert to seconds using a default
// frame rate of 23.976 fps (NTSC film) which can be overridden by a
// special {FPS} line at the top of the file.
+ (NSArray *)parseMicroDVD:(NSString *)mdText {
    if (!mdText.length) return nil;

    NSString *text = [mdText stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray *lines = [text componentsSeparatedByString:@"\n"];

    NSMutableArray *cues = [NSMutableArray array];
    double fps = 23.976; // Default NTSC film frame rate.

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trimmed.length) continue;

        if (![trimmed hasPrefix:@"{"]) continue;

        // Extract first {start} and second {end}.
        NSUInteger firstClose = [trimmed rangeOfString:@"}"].location;
        if (firstClose == NSNotFound) continue;
        NSUInteger secondOpen = [trimmed rangeOfString:@"{" options:0 range:NSMakeRange(firstClose, trimmed.length - firstClose)].location;
        if (secondOpen == NSNotFound) continue;
        NSUInteger secondClose = [trimmed rangeOfString:@"}" options:0 range:NSMakeRange(secondOpen, trimmed.length - secondOpen)].location;
        if (secondClose == NSNotFound) continue;

        NSString *firstVal = [trimmed substringWithRange:NSMakeRange(1, firstClose - 1)];
        NSString *secondVal = [trimmed substringWithRange:NSMakeRange(secondOpen + 1, secondClose - secondOpen - 1)];

        // Check for {FPS} override line.
        if ([firstVal.uppercaseString hasPrefix:@"FPS"] || [firstVal.uppercaseString hasPrefix:@"FRAME RATE"]) {
            // Extract the numeric FPS value from secondVal.
            double parsedFPS = [secondVal doubleValue];
            if (parsedFPS > 0) fps = parsedFPS;
            continue;
        }

        // Both values should be numeric frame indices.
        NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
        if (firstVal.length == 0 || [firstVal stringByTrimmingCharactersInSet:digits].length > 0) continue;
        if (secondVal.length == 0 || [secondVal stringByTrimmingCharactersInSet:digits].length > 0) continue;

        long startFrame = [firstVal longLongValue];
        long endFrame = [secondVal longLongValue];

        // Normalize pipe-separated lines: text|text → text\ntext.
        NSString *rawText = [trimmed substringFromIndex:secondClose + 1];
        NSString *cueText = [rawText stringByReplacingOccurrencesOfString:@"|" withString:@"\n"];
        cueText = [cueText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (!cueText.length) continue;

        NSTimeInterval start = (double)startFrame / fps;
        NSTimeInterval end = (double)endFrame / fps;
        if (end <= start) end = start + 2.0;

        OESubtitleCue *cue = [[OESubtitleCue alloc] init];
        cue.startTime = start;
        cue.endTime = end;
        cue.text = cueText;
        [cues addObject:cue];
    }

    return cues.count ? cues : nil;
}

#pragma mark - Auto-Detection

+ (NSArray *)parse:(NSString *)text {
    if (!text.length) return nil;

    // Normalize for inspection
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return nil;

    // Detect VTT: starts with "WEBVTT"
    if ([trimmed.uppercaseString hasPrefix:@"WEBVTT"]) {
        NSArray *cues = [self parseVTT:text];
        if (cues.count) return cues;
    }

    // Detect ASS/SSA: contains "[Script Info]" or "[Events]" or "Dialogue:"
    if ([text containsString:@"[Script Info]"] || [text containsString:@"[Events]"] ||
        [text containsString:@"[V4+ Styles]"] || [text containsString:@"[V4 Styles+]"] ||
        [text containsString:@"Dialogue:"]) {
        NSArray *cues = [self parseASS:text];
        if (cues.count) return cues;
    }

    // Detect LRC: lines starting with [mm:ss.xx] time tags
    // Check if the first few non-empty lines start with [digit
    NSArray *lines = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                      componentsSeparatedByString:@"\n"];
    NSInteger lrcCount = 0;
    NSInteger checked = 0;
    for (NSString *line in lines) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!t.length) continue;
        checked++;
        if (checked > 10) break;
        if ([t hasPrefix:@"["] && t.length > 1) {
            // Check if it looks like a time tag [00:01.23]
            unichar c = [t characterAtIndex:1];
            if (c >= '0' && c <= '9') lrcCount++;
        }
    }
    if (lrcCount >= 2) {
        NSArray *cues = [self parseLRC:text];
        if (cues.count) return cues;
    }

    // Detect MicroDVD or SubViewer: lines starting with {digits} or {timestamp}
    // MicroDVD: {123}{456}text (frame numbers are pure digits)
    // SubViewer 1.x: {00:01:23}{00:01:25}text (timestamps with colons)
    // Both start with "{" and have "}" followed by another "{...}".
    NSInteger curlyCount = 0;
    checked = 0;
    for (NSString *line in lines) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!t.length) continue;
        checked++;
        if (checked > 10) break;
        // Must start with { and contain }{ pattern.
        if ([t hasPrefix:@"{"] && [t containsString:@"}{"]) {
            curlyCount++;
        }
    }
    if (curlyCount >= 2) {
        // Distinguish: MicroDVD has pure digits between braces,
        // SubViewer 1.x has colons (timestamps).
        for (NSString *line in lines) {
            NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (![t hasPrefix:@"{"]) continue;
            NSRange firstClose = [t rangeOfString:@"}"];
            if (firstClose.location == NSNotFound) break;
            NSString *firstVal = [t substringWithRange:NSMakeRange(1, firstClose.location - 1)];
            if (firstVal.length > 0 && [firstVal containsString:@":"]) {
                // SubViewer 1.x (timestamps with colons)
                NSArray *cues = [self parseSubViewer:text];
                if (cues.count) return cues;
                break;
            } else {
                // MicroDVD (pure digit frame numbers)
                // Skip FPS override lines.
                if ([firstVal.uppercaseString hasPrefix:@"FPS"]) continue;
                NSArray *cues = [self parseMicroDVD:text];
                if (cues.count) return cues;
                break;
            }
        }
    }

    // Detect SubViewer 2.x by header markers.
    if ([text containsString:@"[INFINITE SYNC]"] || [text containsString:@"[SUBTITLE"] ||
        [text containsString:@"[COLF]"] || [text containsString:@"[BODY]"]) {
        // SubViewer 2.x uses SRT-style time lines; the SRT parser handles it.
        // SubViewer 1.x uses curly-brace timestamps; try the 1.x parser first.
        NSArray *cues = [self parseSubViewer:text];
        if (cues.count) return cues;
    }

    // Default: try SRT (most permissive, also handles VTT without header
    // and SubViewer 2.x which uses the same time format)
    return [self parseSRT:text];
}

+ (OESubtitleCue *)cueForTime:(NSTimeInterval)time inCues:(NSArray *)cues {
    if (!cues.count) return nil;
    for (OESubtitleCue *cue in cues) {
        if (time >= cue.startTime && time <= cue.endTime) return cue;
    }
    return nil;
}

@end

#pragma mark - Backward Compatibility

@implementation OESRTSubtitleParser
@end
