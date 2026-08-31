#import "OEItemCell.h"
#import "Services/OEImageCache.h"
#import "Services/OEEmbyAPIClient.h"
#import "Views/OETheme.h"

@interface OEItemCell ()
@property (nonatomic, copy) NSString *representedItemId;
@property (nonatomic, assign) CGFloat primaryImageAspectRatio;
@end

@implementation OEItemCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        if ([self respondsToSelector:@selector(setSeparatorInset:)]) {
            self.separatorInset = UIEdgeInsetsMake(0, 76, 0, 0);
        }

        _coverView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _coverView.contentMode = UIViewContentModeScaleAspectFit;
        _coverView.clipsToBounds = YES;
        _coverView.layer.borderWidth = 0.5;
        [self.contentView addSubview:_coverView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont boldSystemFontOfSize:15];
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_titleLabel];

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
    _titleLabel.textColor = [OETheme primaryTextColor];
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
        CGFloat aspectRatio = self.primaryImageAspectRatio > 0 ? self.primaryImageAspectRatio : (2.0 / 3.0);
        CGFloat imageWidth = MAX(1.0, MIN(imageHeight * aspectRatio, w * 0.55));
        _coverView.frame = CGRectMake(0, 0, imageWidth, imageHeight);
        CGFloat textX = imageWidth + 10;
        _titleLabel.frame = CGRectMake(textX, 16, MAX(0, w - textX - 10), 46);
        _detailLabel.frame = CGRectMake(textX, 70, MAX(0, w - textX - 10), 42);
        if ([self respondsToSelector:@selector(setSeparatorInset:)]) self.separatorInset = UIEdgeInsetsMake(0, textX, 0, 0);
    } else if (_compactLayout) {
        _coverView.frame = CGRectMake(8, 6, 48, 48);
        _titleLabel.frame = CGRectMake(66, 8, w - 76, 20);
        _detailLabel.frame = CGRectMake(66, 30, w - 76, 22);
        if ([self respondsToSelector:@selector(setSeparatorInset:)]) self.separatorInset = UIEdgeInsetsMake(0, 76, 0, 0);
    } else {
        _coverView.frame = CGRectMake(10, 8, 64, 96);
        _titleLabel.frame = CGRectMake(86, 14, w - 98, 22);
        _detailLabel.frame = CGRectMake(86, 40, w - 98, 48);
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
}

- (void)configureWithItem:(OEEmbyItem *)item {
    [self applyTheme];
    self.representedItemId = item.itemId;
    self.primaryImageAspectRatio = item.primaryImageAspectRatio;
    [self setNeedsLayout];
    self.titleLabel.text = item.name ?: @"未命名";
    self.detailLabel.text = [NSString stringWithFormat:@"%@  %@", item.type ?: @"", [item displayDuration]];
    NSInteger imageWidth = self.episodeLayout ? 280 : 128;
    NSInteger imageHeight = self.episodeLayout ? 560 : (self.compactLayout ? 96 : 192);
    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:item width:imageWidth height:imageHeight];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image) {
        if ([self.representedItemId isEqualToString:item.itemId]) self.coverView.image = image;
    }];
}

@end
