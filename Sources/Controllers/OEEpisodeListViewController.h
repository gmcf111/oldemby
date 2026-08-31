#import <UIKit/UIKit.h>
@class OEEmbyItem;

// Episode picker for a Season (fetches /Shows/{seriesId}/Episodes?SeasonId=...).
// Pass season=nil to list every episode of the series (legacy entry point).
@interface OEEpisodeListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithSeries:(OEEmbyItem *)series;
- (instancetype)initWithSeries:(OEEmbyItem *)series season:(OEEmbyItem *)season;

@end
