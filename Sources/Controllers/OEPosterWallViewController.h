#import <UIKit/UIKit.h>

@class OEEmbyItem;

// Poster wall for one Emby media library: a 3-column grid of every
// Movie (movie library) or Series (TV library) in the collection.
@interface OEPosterWallViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithLibrary:(OEEmbyItem *)library;

@end
