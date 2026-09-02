#import <UIKit/UIKit.h>
#import "Models/OEEmbyItem.h"

@interface OEItemCell : UITableViewCell

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
// YES = compact layout for 60pt rows (music)
@property (nonatomic, assign) BOOL compactLayout;
// YES = full-height, aspect-ratio-preserving layout used by episode/season rows.
@property (nonatomic, assign) BOOL episodeLayout;
// YES = the cover is a portrait poster (2:3) — used by season rows.
// NO  = the cover is a landscape thumbnail (16:9) — used by episode rows.
// Only meaningful when episodeLayout is also YES.
@property (nonatomic, assign) BOOL portraitCover;
// Default (both NO) = library rows: small banner cover on the left, title
// and subtitle on the right.

- (void)configureWithItem:(OEEmbyItem *)item;
// episodeNumber > 0 renders a bold "N." prefix before the name (Emby-web style).
- (void)configureWithItem:(OEEmbyItem *)item episodeNumber:(NSInteger)episodeNumber;

@end
