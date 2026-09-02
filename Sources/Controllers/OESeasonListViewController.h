#import <UIKit/UIKit.h>
@class OEEmbyItem;

// Season picker for a series: lists every Season returned by
// /Shows/{seriesId}/Seasons. When the series has only one season the
// controller replaces itself in the navigation stack with the episode list,
// so the user can go directly back to the library without passing through
// an empty season page.
@interface OESeasonListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithSeries:(OEEmbyItem *)series;

@end
