#import "OEItemCell.h"
#import "Services/OEImageCache.h"
#import "Services/OEEmbyAPIClient.h"
#import "Views/OETheme.h"

@interface OEItemCell ()
@property (nonatomic, copy) NSString *representedItemId;
@property (nonatomic, assign) CGFloat primaryImageAspectRatio;
// Bold episode-number prefix rendered next to the (regular) title in
// episode layout: "12. 名称" with only the number bold.
@property (nonatomic, strong) UILabel *episodeNumberLabel;
@end

@implementation OEItemCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        if ([self respondsToSelector:@selector(setSeparatorInset:)]) {
            self.separatorInset = UIEdgeInsetsMake(0, 76, 0, 0);
        }

        _coverView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _coverView.contentMode = UIViewContentModeScaleAspectFill;
        _coverView.clipsToBounds = YES;
        _coverView.layer.borderWidth = 0.5;
        [self.contentView addSubview:_coverView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont boldSystemFontOfSize:15];
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_titleLabel];

        _episodeNumberLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _episodeNumberLabel.font = [UIFont boldSystemFontOfSize:15];
        _episodeNumberLabel.backgroundColor = [UIColor clearColor];
        _episodeNumberLabel.hidden = YES;
        [self.contentView addSubview:_episodeNumberLabel];

        _detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _detailLabel.font = [UIFont systemFontOfSize:12];
        _detailLabel.numberOfLines = 2;
        _detailLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_detailLabel];

        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    self.backgroundColor = [OETheme cellColor];
    self.contentView.backgroundColor = [OETheme cellColor];
    _coverView.backgroundColor = [OETheme imagePlaceholderColor];
    _coverView.layer.borderColor = [OETheme separatorColor].CGColor;
    // Library rows no longer overlay text on the cover, so they use the same
    // theme colors as the other layouts.
    _titleLabel.textColor = [OETheme primaryTextColor];
    _titleLabel.font = [UIFont boldSystemFontOfSize:15];
    _episodeNumberLabel.textColor = [OETheme primaryTextColor];
    _detailLabel.textColor = [OETheme secondaryTextColor];
}

- (void)setCompactLayout:(BOOL)compactLayout {
    _compactLayout = compactLayout;
    if (compactLayout) _episodeLayout = NO;
    _detailLabel.numberOfLines = compactLayout ? 1 : 2;
    [self setNeedsLayout];
}

- (void)setEpisodeLayout:(BOOL)episodeLayout {
    _episodeLayout = episodeLayout;
    if (episodeLayout) _compactLayout = NO;
    _detailLabel.numberOfLines = episodeLayout ? 2 : (_compactLayout ? 1 : 2);
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    if (_episodeLayout) {
        CGFloat imageHeight = self.contentView.bounds.size.height;
        // Episode thumbnails are landscape (16:9); use the real aspect
        // ratio when available, falling back to 16:9.
        CGFloat aspectRatio = self.primaryImageAspectRatio > 0 ? self.primaryImageAspectRatio : 1.78;
        // Clamp to a reasonable landscape range so very wide or very
        // tall images don't break the row.
        aspectRatio = MAX(1.2, MIN(aspectRatio, 2.8));
        CGFloat imageWidth = MAX(1.0, MIN(imageHeight * aspectRatio, w * 0.55));
        _coverView.frame = CGRectMake(0, 0, imageWidth, imageHeight);
        CGFloat textX = imageWidth + 10;
        // Bold episode number ("12.") followed by the regular episode name.
        CGFloat numberW = 0;
        if (!_episodeNumberLabel.hidden && _episodeNumberLabel.text.length > 0) {
            UIFont *numFont = _episodeNumberLabel.font ?: [UIFont boldSystemFontOfSize:15];
            numberW = ceil([_episodeNumberLabel.text sizeWithFont:numFont].width) + 4;
            numberW = MIN(numberW, MAX(0, w * 0.2));
            _episodeNumberLabel.frame = CGRectMake(textX, 16, numberW, 20);
        }
        _titleLabel.frame = CGRectMake(textX + numberW, 16, MAX(0, w - textX - numberW - 10), 20);
        // Detail block fills the rest of the row so taller season rows show
        // more overview lines without hand-tuned offsets.
        _detailLabel.frame = CGRectMake(textX, 40, MAX(0, w - textX - 10), MAX(0, self.contentView.bounds.size.height - 40 - 8));
        if ([self respondsToSelector:@selector(setSeparatorInset:)]) self.separatorInset = UIEdgeInsetsMake(0, textX, 0, 0);
    } else if (_compactLayout) {
        _coverView.frame = CGRectMake(8, 6, 48, 48);
        _titleLabel.frame = CGRectMake(66, 8, w - 76, 20);
        _detailLabel.frame = CGRectMake(66, 30, w - 76, 22);
        if ([self respondsToSelector:@selector(setSeparatorInset:)]) self.separatorInset = UIEdgeInsetsMake(0, 76, 0, 0);
    } else {
        // Library rows: small banner cover on the left (about a quarter of
        // the old full-bleed cover area), title and subtitle stacked on the
        // right. Cover keeps the item's real landscape aspect ratio, capped
        // at half the cell width.
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat margin = 8;
        CGFloat imgH = MAX(1, h - margin * 2);
        CGFloat ratio = self.primaryImageAspectRatio > 0 ? self.primaryImageAspectRatio : 1.78;
        ratio = MAX(1.2, MIN(ratio, 2.8));
        CGFloat imgW = MIN(imgH * ratio, w * 0.5);
        _coverView.frame = CGRectMake(margin, margin, imgW, imgH);
        CGFloat textX = margin + imgW + 10;
        CGFloat textW = MAX(0, w - textX - 10);
        CGFloat blockY = (h - 38) / 2;
        _titleLabel.frame = CGRectMake(textX, blockY, textW, 20);
        _detailLabel.frame = CGRectMake(textX, blockY + 22, textW, 16);
        if ([self respondsToSelector:@selector(setSeparatorInset:)]) self.separatorInset = UIEdgeInsetsMake(0, textX, 0, 0);
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.coverView.image = nil;
    self.titleLabel.text = nil;
    self.detailLabel.text = nil;
    self.representedItemId = nil;
    self.primaryImageAspectRatio = 0;
    self.episodeNumberLabel.hidden = YES;
    self.episodeNumberLabel.text = nil;
}

- (void)configureWithItem:(OEEmbyItem *)item {
    [self configureWithItem:item episodeNumber:0];
}

// episodeNumber > 0 renders a bold "N." prefix before the episode name
// (Emby-web style). 0 leaves the plain bold title.
- (void)configureWithItem:(OEEmbyItem *)item episodeNumber:(NSInteger)episodeNumber {
    [self applyTheme];
    self.representedItemId = item.itemId;
    self.primaryImageAspectRatio = item.primaryImageAspectRatio;
    [self setNeedsLayout];
    self.titleLabel.text = item.name ?: @"未命名";
    if (episodeNumber > 0 && _episodeLayout) {
        self.episodeNumberLabel.hidden = NO;
        self.episodeNumberLabel.text = [NSString stringWithFormat:@"%ld.", (long)episodeNumber];
        self.titleLabel.font = [UIFont systemFontOfSize:15];
    } else {
        self.episodeNumberLabel.hidden = YES;
        self.episodeNumberLabel.text = nil;
        self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    }
    self.detailLabel.text = [NSString stringWithFormat:@"%@  %@", item.type ?: @"", [item displayDuration]];
    // Library rows request a small banner thumbnail matching the quarter-size
    // left cover; compact/episode rows keep their original small thumbnails.
    // Episode rows request landscape thumbnails (16:9) instead of portrait.
    NSInteger imageWidth = self.episodeLayout ? 320 : (self.compactLayout ? 128 : 320);
    NSInteger imageHeight = self.episodeLayout ? 180 : (self.compactLayout ? 96 : 180);
    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:item width:imageWidth height:imageHeight];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image) {
        if ([self.representedItemId isEqualToString:item.itemId]) self.coverView.image = image;
    }];
}

@end
