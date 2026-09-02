#import <Foundation/Foundation.h>
#import "Models/OEEmbyItem.h"

typedef void (^OEAPICompletion)(id result, NSError *error);

// iOS 6 compatible networking via NSURLConnection (NSURLSession is iOS 7+)
@interface OEEmbyAPIClient : NSObject

+ (instancetype)sharedClient;

// Auth
- (void)authenticateWithHost:(NSString *)host username:(NSString *)user password:(NSString *)pass completion:(OEAPICompletion)completion;
- (void)logout;

// Browsing
- (void)fetchViewsWithCompletion:(OEAPICompletion)completion; // User Views (Movies, TV, Music)
- (void)fetchItemsInParent:(NSString *)parentId itemTypes:(NSString *)types startIndex:(NSInteger)start limit:(NSInteger)limit completion:(OEAPICompletion)completion;
// sortBy variant (e.g. @"ParentIndexNumber,IndexNumber" for album track order)
- (void)fetchItemsInParent:(NSString *)parentId itemTypes:(NSString *)types startIndex:(NSInteger)start limit:(NSInteger)limit sortBy:(NSString *)sortBy completion:(OEAPICompletion)completion;
// recursive=NO is used for folder drill-down so only direct children are returned.
- (void)fetchItemsInParent:(NSString *)parentId itemTypes:(NSString *)types startIndex:(NSInteger)start limit:(NSInteger)limit sortBy:(NSString *)sortBy recursive:(BOOL)recursive completion:(OEAPICompletion)completion;
// sortOrder is Emby's SortOrder param: @"Ascending" or @"Descending".
- (void)fetchItemsInParent:(NSString *)parentId itemTypes:(NSString *)types startIndex:(NSInteger)start limit:(NSInteger)limit sortBy:(NSString *)sortBy sortOrder:(NSString *)sortOrder recursive:(BOOL)recursive completion:(OEAPICompletion)completion;
// Songs of a MusicArtist (artists are virtual nodes, ParentId does not work -> filter by ArtistIds)
- (void)fetchSongsForArtist:(NSString *)artistId startIndex:(NSInteger)start limit:(NSInteger)limit completion:(OEAPICompletion)completion;
// Seasons of a series (GET /Shows/{seriesId}/Seasons).
- (void)fetchSeasonsForSeries:(NSString *)seriesId completion:(OEAPICompletion)completion;

// Playback
- (void)fetchPlaybackInfoForItem:(NSString *)itemId isAudio:(BOOL)isAudio completion:(OEAPICompletion)completion;
- (void)fetchStreamURLForItem:(NSString *)itemId isAudio:(BOOL)isAudio completion:(OEAPICompletion)completion;
// Fetch a direct-stream URL with no transcoding — the server hands back the
// original file as-is.  Used for content already in a format the device can
// decode (e.g. older TV recordings in MPEG-2 / H.264 mp4).
- (void)fetchDirectStreamURLForItem:(NSString *)itemId isAudio:(BOOL)isAudio completion:(OEAPICompletion)completion;
// Fetch server-provided lyrics first, then a compatible text stream embedded
// in the audio container when the server has no standalone lyrics result.
- (void)fetchLyricsForAudioItem:(OEEmbyItem *)item completion:(OEAPICompletion)completion;
- (void)fetchLyricsForItem:(NSString *)itemId completion:(OEAPICompletion)completion;

// Casts (actors / directors etc.)
// Fetches the people list for the given item via /Items/{Id} with Fields=People.
// Returns an array of OECastItem objects on success.
- (void)fetchCastsForItem:(NSString *)itemId completion:(OEAPICompletion)completion;

// Helper: person (primary) image URL for a given person Id + tag.
- (NSString *)personImageURLWithHost:(NSString *)host personId:(NSString *)personId tag:(NSString *)tag maxWidth:(NSInteger)width;

// Helpers
- (NSString *)imageURLForItem:(OEEmbyItem *)item width:(NSInteger)width;
- (NSString *)imageURLForItem:(OEEmbyItem *)item width:(NSInteger)width height:(NSInteger)height;

// Generic
- (void)GET:(NSString *)path params:(NSDictionary *)params completion:(OEAPICompletion)completion;
- (void)POST:(NSString *)path jsonBody:(NSDictionary *)body completion:(OEAPICompletion)completion;

@end
