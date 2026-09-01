#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, OEEmbyItemType) {
    OEEmbyItemTypeUnknown = 0,
    OEEmbyItemTypeMovie,
    OEEmbyItemTypeEpisode,
    OEEmbyItemTypeSeries,
    OEEmbyItemTypeSeason,
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
// Candidate text subtitle stream embedded in an audio container. NSNotFound
// means the item listing did not advertise a compatible lyrics stream.
@property (nonatomic, assign) NSInteger embeddedLyricsStreamIndex;
@property (nonatomic, copy) NSString *embeddedLyricsFormat;
@property (nonatomic, assign) NSInteger seasonNumber;
@property (nonatomic, assign) NSInteger episodeNumber;
// Raw IndexNumber: episode number for Episodes, season number for Seasons.
@property (nonatomic, assign) NSInteger indexNumber;
// Episodes and Seasons expose their parent series through Emby's SeriesId.
@property (nonatomic, copy) NSString *seriesId;

+ (instancetype)itemWithDictionary:(NSDictionary *)dict;
+ (OEEmbyItemType)typeFromString:(NSString *)s;

- (NSString *)primaryImageURLWithHost:(NSString *)host maxWidth:(NSInteger)width;
- (NSString *)primaryImageURLWithHost:(NSString *)host maxWidth:(NSInteger)width maxHeight:(NSInteger)height;
- (NSString *)displayDuration;

@end
