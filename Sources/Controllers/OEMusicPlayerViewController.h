#import <UIKit/UIKit.h>
@class OEEmbyItem;

@interface OEMusicPlayerViewController : UIViewController

- (instancetype)initWithItem:(OEEmbyItem *)item playlist:(NSArray *)playlist;

@end
