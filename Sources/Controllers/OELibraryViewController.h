#import <UIKit/UIKit.h>

@interface OELibraryViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithParentId:(NSString *)parentId title:(NSString *)title;

@end
