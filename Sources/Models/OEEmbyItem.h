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
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *collectionType; // CollectionFolder: movies/tvshows/music/...
@property (nonatomic, assign) OEEmbyItemType itemType;
@property (nonatomic, copy) NSString *imageTag;
@property (nonatomic, assign) CGFloat primaryImageAspectRatio;
@property (nonatomic, assign) long long runTimeTicks;
@property (nonatomic, copy) NSString *overview;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, assign) NSInteger seasonNumber;
@property (nonatomic, assign) NSInteger episodeNumber;

+ (instancetype)itemWithDictionary:(NSDictionary *)dict;
+ (OEEmbyItemType)typeFromString:(NSString *)s;

- (NSString *)primaryImageURLWithHost:(NSString *)host maxWidth:(NSInteger)width;
- (NSString *)primaryImageURLWithHost:(NSString *)host maxWidth:(NSInteger)width maxHeight:(NSInteger)height;
- (NSString *)displayDuration;

@end
