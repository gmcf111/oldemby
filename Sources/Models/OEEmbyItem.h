#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, OEEmbyItemType) {
    OEEmbyItemTypeUnknown = 0,
    OEEmbyItemTypeMovie,
    OEEmbyItemTypeEpisode,
    OEEmbyItemTypeSeries,
    OEEmbyItemTypeAudio,
    OEEmbyItemTypeAlbum,
    OEEmbyItemTypeArtist,
    OEEmbyItemTypeFolder
};

@interface OEEmbyItem : NSObject

@property (nonatomic, copy) NSString *itemId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *type; // raw Emby Type string
@property (nonatomic, assign) OEEmbyItemType itemType;
@property (nonatomic, copy) NSString *imageTag; // Primary image tag
@property (nonatomic, assign) long long runTimeTicks; // 100ns ticks
@property (nonatomic, copy) NSString *overview;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *artist;

+ (instancetype)itemWithDictionary:(NSDictionary *)dict;
+ (OEEmbyItemType)typeFromString:(NSString *)s;

- (NSString *)primaryImageURLWithHost:(NSString *)host maxWidth:(NSInteger)width;
- (NSString *)displayDuration;

@end
