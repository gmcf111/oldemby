#import <Foundation/Foundation.h>

// Represents a person (actor, director, etc.) from Emby's People array.
@interface OECastItem : NSObject

@property (nonatomic, copy) NSString *personId;   // Emby Id
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *role;        // Role or character name
@property (nonatomic, copy) NSString *type;         // "Actor", "Director", etc.
@property (nonatomic, copy) NSString *primaryImageTag; // Primary image tag for the person
@property (nonatomic, assign) CGFloat primaryImageAspectRatio;

// Image tag for a specific image type (e.g. "Primary").
// Emby returns ImageTags on a People item under "PrimaryImageTag" (string).
+ (instancetype)castWithDictionary:(NSDictionary *)dict;

// Convenience: builds the person primary-image URL for the given host.
- (NSString *)primaryImageURLWithHost:(NSString *)host maxWidth:(NSInteger)width;

@end
