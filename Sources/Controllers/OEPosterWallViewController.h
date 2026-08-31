#import <UIKit/UIKit.h>

@class OEEmbyItem;

// Poster wall for one Emby media library: a grid of every
// Movie (movie library) or Series (TV library) in the collection.
// iPad: landscape 10 per row, portrait 6; iPhone: 3 per row.
// Tapping a Series enters the season list first (Emby-web drill-down).
@interface OEPosterWallViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithLibrary:(OEEmbyItem *)library;

@end
