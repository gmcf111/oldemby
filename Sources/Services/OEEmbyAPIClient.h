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

// Playback
- (void)fetchPlaybackInfoForItem:(NSString *)itemId isAudio:(BOOL)isAudio completion:(OEAPICompletion)completion;
- (void)fetchStreamURLForItem:(NSString *)itemId isAudio:(BOOL)isAudio completion:(OEAPICompletion)completion;

// Helpers
- (NSString *)imageURLForItem:(OEEmbyItem *)item width:(NSInteger)width;

// Generic
- (void)GET:(NSString *)path params:(NSDictionary *)params completion:(OEAPICompletion)completion;
- (void)POST:(NSString *)path jsonBody:(NSDictionary *)body completion:(OEAPICompletion)completion;

@end
