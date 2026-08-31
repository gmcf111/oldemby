#import <UIKit/UIKit.h>
@class OEEmbyItem;

@interface OEMusicPlayerViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithItem:(OEEmbyItem *)item playlist:(NSArray *)playlist;

@end
