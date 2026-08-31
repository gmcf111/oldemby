#import <UIKit/UIKit.h>
@class OEEmbyItem;

// Season picker for a series: lists every Season returned by
// /Shows/{seriesId}/Seasons. When the series has only one season the list
// controller pushes the episode list for it directly.
@interface OESeasonListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithSeries:(OEEmbyItem *)series;

@end
