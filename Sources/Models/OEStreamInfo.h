#import <Foundation/Foundation.h>

// A stream descriptor for audio or subtitle tracks parsed from Emby
// MediaSources → MediaStreams.
@interface OEStreamInfo : NSObject
@property (nonatomic, copy) NSString *index;      // Stream Index (NSString for table cell reuse convenience)
@property (nonatomic, copy) NSString *title;      // Display title
@property (nonatomic, copy) NSString *language;    // Language code
@property (nonatomic, copy) NSString *codec;       // Codec (e.g. "aac", "srt")
@property (nonatomic, assign) BOOL isDefault;
@property (nonatomic, assign) BOOL isExternal;   // External subtitle (has DeliveryUrl or IsExternal)
@property (nonatomic, copy) NSString *deliveryUrl; // Subtitle delivery URL if external
@property (nonatomic, copy) NSString *mediaSourceId; // MediaSource Id for subtitle fetch
@end
