#import <UIKit/UIKit.h>
#import "Models/OEEmbyItem.h"

@interface OEItemCell : UITableViewCell

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;

- (void)configureWithItem:(OEEmbyItem *)item;

@end
