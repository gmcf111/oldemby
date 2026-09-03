#import <Foundation/Foundation.h>

// A single subtitle cue (start time, end time, text).
@interface OESubtitleCue : NSObject
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSTimeInterval endTime;
@property (nonatomic, copy) NSString *text;
@end

// Multi-format subtitle parser. Supports SRT, VTT (WebVTT), ASS/SSA,
// LRC, SubViewer, and MicroDVD formats. Designed for iOS 6: pure
// Foundation, no external deps.
@interface OESubtitleParser : NSObject

// Auto-detect format and parse. Returns nil on empty or unparseable input.
// Detection heuristics:
//   - "WEBVTT" header → VTT
//   - "[Script Info]" or "[Events]" → ASS/SSA
//   - "[mm:ss.xx]" prefixes → LRC
//   - "{frame}{frame}" pattern → MicroDVD
//   - "[INFINITE SYNC]" or "{start} {end}" SubViewer → SubViewer
//   - Otherwise → SRT (the most permissive parser, also handles VTT without header)
+ (NSArray *)parse:(NSString *)text;

// Format-specific parsers. Each returns nil on empty/unparseable input.
+ (NSArray *)parseSRT:(NSString *)text;
+ (NSArray *)parseVTT:(NSString *)text;
+ (NSArray *)parseASS:(NSString *)text;   // Also handles SSA.
+ (NSArray *)parseLRC:(NSString *)text;
+ (NSArray *)parseSubViewer:(NSString *)text;
+ (NSArray *)parseMicroDVD:(NSString *)text;

// Find the cue active at the given time. Returns nil if no cue matches.
+ (OESubtitleCue *)cueForTime:(NSTimeInterval)time inCues:(NSArray *)cues;

// All cues active at the given time, joined into one multi-line string.
// ASS commonly shows several lines at once (e.g. a sign and dialogue); the
// single-cue lookup above drops everything but the first. Returns nil if
// nothing is active.
+ (NSString *)textForTime:(NSTimeInterval)time inCues:(NSArray *)cues;

@end

// Backward-compatibility alias. Older code called OESRTSubtitleParser;
// keep the name so existing imports keep compiling.
@interface OESRTSubtitleParser : OESubtitleParser
@end
