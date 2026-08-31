#import <UIKit/UIKit.h>

@class OEEmbyItem;

// Poster wall for one Emby media library: a grid of every
// Movie (movie library) or Series (TV library) in the collection.
// iPad landscape: 6 per row, portrait: 4 per row; iPhone: 3 per row.
@interface OEPosterWallViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithLibrary:(OEEmbyItem *)library;

@end
