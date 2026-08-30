#import <UIKit/UIKit.h>
#import "Models/OEEmbyItem.h"

@interface OEItemCell : UITableViewCell

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
// YES = compact layout for 60pt rows (music/episode lists); NO = default 102pt layout
@property (nonatomic, assign) BOOL compactLayout;

- (void)configureWithItem:(OEEmbyItem *)item;

@end
