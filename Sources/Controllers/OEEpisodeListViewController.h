#import <UIKit/UIKit.h>
@class OEEmbyItem;

// Episode picker for a Series (fetches /Shows/{seriesId}/Episodes)
@interface OEEpisodeListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithSeries:(OEEmbyItem *)series;

@end
