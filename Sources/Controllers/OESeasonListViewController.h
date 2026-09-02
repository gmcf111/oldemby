#import <UIKit/UIKit.h>
@class OEEmbyItem;

// Season picker for a series: lists every Season returned by
// /Shows/{seriesId}/Seasons. The poster wall checks the season count
// before pushing this controller, so single-season series go straight
// to the episode list and skip this page entirely.
@interface OESeasonListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithSeries:(OEEmbyItem *)series;

@end
