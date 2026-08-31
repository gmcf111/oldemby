#import "OEItemCell.h"
#import "Services/OEImageCache.h"
#import "Services/OEEmbyAPIClient.h"
#import "Views/OETheme.h"

@interface OEItemCell ()
@property (nonatomic, copy) NSString *representedItemId;
@property (nonatomic, assign) CGFloat primaryImageAspectRatio;
@property (nonatomic, strong) UIView *captionOverlay;
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

        // Library rows overlay the caption on a translucent strip at the
        // bottom of the full-width cover so nothing sits above or below it.
        _captionOverlay = [[UIView alloc] initWithFrame:CGRectZero];
        _captionOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        [self.contentView addSubview:_captionOverlay];

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
    BOOL libraryLayout = !_compactLayout && !_episodeLayout;
    _titleLabel.textColor = libraryLayout ? [UIColor whiteColor] : [OETheme primaryTextColor];
    _titleLabel.font = [UIFont boldSystemFontOfSize:15];
    _episodeNumberLabel.textColor = [OETheme primaryTextColor];
    _detailLabel.textColor = libraryLayout ? [UIColor colorWithWhite:1 alpha:0.85] : [OETheme secondaryTextColor];
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
        CGFloat aspectRatio = self.primaryImageAspectRatio > 0 ? self.primaryImageAspectRatio : (2.0 / 3.0);
        CGFloat imageWidth = MAX(1.0, MIN(imageHeight * aspectRatio, w * 0.55));
        _coverView.frame = CGRectMake(0, 0, imageWidth, imageHeight);
        _captionOverlay.hidden = YES;
        CGFloat textX = imageWidth + 10;
        // Bold episode number ("12.") followed by the regular episode name.
        CGFloat numberW = 0;
        if (!_episodeNumberLabel.hidden) {
            numberW = ceil([_episodeNumberLabel.text sizeWithFont:_episodeNumberLabel.font].width) + 4;
            numberW = MIN(numberW, w * 0.2);
            _episodeNumberLabel.frame = CGRectMake(textX, 16, numberW, 20);
        }
        _titleLabel.frame = CGRectMake(textX + numberW, 16, MAX(0, w - textX - numberW - 10), 20);
        // Detail block fills the rest of the row so taller season rows show
        // more overview lines without hand-tuned offsets.
        _detailLabel.frame = CGRectMake(textX, 40, MAX(0, w - textX - 10), MAX(0, self.contentView.bounds.size.height - 40 - 8));
        if ([self respondsToSelector:@selector(setSeparatorInset:)]) self.separatorInset = UIEdgeInsetsMake(0, textX, 0, 0);
    } else if (_compactLayout) {
        _coverView.frame = CGRectMake(8, 6, 48, 48);
        _captionOverlay.hidden = YES;
        _titleLabel.frame = CGRectMake(66, 8, w - 76, 20);
        _detailLabel.frame = CGRectMake(66, 30, w - 76, 22);
        if ([self respondsToSelector:@selector(setSeparatorInset:)]) self.separatorInset = UIEdgeInsetsMake(0, 76, 0, 0);
    } else {
        // Library rows: full-bleed cover filling the whole cell (width =
        // cell width, height set by the controller from the item's real
        // aspect ratio), caption overlaid at the bottom — nothing above or
        // below the cover.
        CGFloat h = self.contentView.bounds.size.height;
        _coverView.frame = CGRectMake(0, 0, w, h);
        CGFloat stripH = 34;
        _captionOverlay.hidden = NO;
        _captionOverlay.frame = CGRectMake(0, h - stripH, w, stripH);
        _titleLabel.frame = CGRectMake(10, h - stripH + 3, w - 20, 18);
        _detailLabel.frame = CGRectMake(10, h - stripH + 21, w - 20, 13);
        if ([self respondsToSelector:@selector(setSeparatorInset:)]) self.separatorInset = UIEdgeInsetsMake(0, 76, 0, 0);
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
    // Library rows request a wide banner-size image to match the full-width
    // cover; compact/episode rows keep their original small thumbnails.
    NSInteger imageWidth = self.episodeLayout ? 280 : (self.compactLayout ? 128 : 640);
    NSInteger imageHeight = self.episodeLayout ? 560 : (self.compactLayout ? 96 : 360);
    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:item width:imageWidth height:imageHeight];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image) {
        if ([self.representedItemId isEqualToString:item.itemId]) self.coverView.image = image;
    }];
}

@end
