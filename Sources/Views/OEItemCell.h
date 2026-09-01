#import <UIKit/UIKit.h>
#import "Models/OEEmbyItem.h"

@interface OEItemCell : UITableViewCell

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
// YES = compact layout for 60pt rows (music)
@property (nonatomic, assign) BOOL compactLayout;
// YES = full-height, aspect-ratio-preserving layout used only by episode rows.
@property (nonatomic, assign) BOOL episodeLayout;
// Default (both NO) = library rows: small banner cover on the left, title
// and subtitle on the right.

- (void)configureWithItem:(OEEmbyItem *)item;
// episodeNumber > 0 renders a bold "N." prefix before the name (Emby-web style).
- (void)configureWithItem:(OEEmbyItem *)item episodeNumber:(NSInteger)episodeNumber;

@end
