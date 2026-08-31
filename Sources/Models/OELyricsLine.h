#import <Foundation/Foundation.h>

@interface OELyricsLine : NSObject

@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, copy) NSString *text;

+ (NSArray *)linesFromEmbyResponse:(id)response;
+ (NSArray *)linesFromLRCString:(NSString *)lrc;
// Parses a text subtitle stream emitted by Emby (LRC, SRT or WebVTT).
+ (NSArray *)linesFromTextSubtitleString:(NSString *)text;

@end
