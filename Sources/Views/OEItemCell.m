#import "OEItemCell.h"
#import "Services/OEImageCache.h"
#import "Services/OEEmbyAPIClient.h"

@interface OEItemCell ()
@property (nonatomic, copy) NSString *representedItemId;
@end

@implementation OEItemCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        // Manual frame layout - iOS6 AutoLayout incomplete, so avoid constraints
        _coverView = [[UIImageView alloc] initWithFrame:CGRectMake(8, 6, 60, 90)];
        _coverView.contentMode = UIViewContentModeScaleAspectFill;
        _coverView.clipsToBounds = YES;
        _coverView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        [self.contentView addSubview:_coverView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(76, 8, 220, 20)];
        _titleLabel.font = [UIFont boldSystemFontOfSize:14];
        _titleLabel.textColor = [UIColor blackColor];
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_titleLabel];

        _detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(76, 32, 220, 36)];
        _detailLabel.font = [UIFont systemFontOfSize:12];
        _detailLabel.textColor = [UIColor darkGrayColor];
        _detailLabel.numberOfLines = 2;
        _detailLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_detailLabel];
    }
    return self;
}

- (void)setCompactLayout:(BOOL)compactLayout {
    _compactLayout = compactLayout;
    _detailLabel.numberOfLines = compactLayout ? 1 : 2;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    if (_compactLayout) {
        _coverView.frame = CGRectMake(8, 6, 48, 48);
        _titleLabel.frame = CGRectMake(64, 8, w - 72, 20);
        _detailLabel.frame = CGRectMake(64, 30, w - 72, 22);
    } else {
        _coverView.frame = CGRectMake(8, 6, 60, 90);
        _titleLabel.frame = CGRectMake(76, 8, w - 84, 20);
        _detailLabel.frame = CGRectMake(76, 32, w - 84, 48);
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.coverView.image = nil;
    self.titleLabel.text = nil;
    self.detailLabel.text = nil;
    self.representedItemId = nil;
}

- (void)configureWithItem:(OEEmbyItem *)item {
    self.representedItemId = item.itemId;
    self.titleLabel.text = item.name ?: @"Untitled";
    self.detailLabel.text = [NSString stringWithFormat:@"%@  %@", item.type ?: @"", [item displayDuration]];
    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:item width:120];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image){
        // Names are not unique; compare the stable item ID to avoid stale
        // asynchronous image responses being displayed in a reused cell.
        if ([self.representedItemId isEqualToString:item.itemId]) {
            self.coverView.image = image;
        }
    }];
}

@end
