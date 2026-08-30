#import <UIKit/UIKit.h>

@interface OEMusicLibraryViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

// Drill-down mode: list songs contained in an album/artist (parentId)
- (instancetype)initWithParentId:(NSString *)parentId title:(NSString *)title;

@end
