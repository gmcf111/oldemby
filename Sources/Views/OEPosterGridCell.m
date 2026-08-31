#import "OEPosterGridCell.h"
#import "OETheme.h"
#import "Services/OEImageCache.h"
#import "Services/OEEmbyAPIClient.h"
#import <math.h>

static const CGFloat kOuterPadding = 12.0;
static const CGFloat kColumnSpacing = 10.0;
static const CGFloat kLabelHeight = 34.0;

// One tappable poster slot: image on top, 2-line name label below.
@interface OEPosterSlot : UIControl
@property (nonatomic, strong) UIImageView *posterView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, copy) NSString *representedItemId;
@end

@implementation OEPosterSlot

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _posterView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _posterView.contentMode = UIViewContentModeScaleAspectFill;
        _posterView.clipsToBounds = YES;
        _posterView.layer.borderWidth = 0.5;
        [self addSubview:_posterView];

        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.font = [UIFont systemFontOfSize:12];
        _nameLabel.numberOfLines = 2;
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _nameLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_nameLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat posterH = self.bounds.size.height - kLabelHeight - 4;
    self.posterView.frame = CGRectMake(0, 0, w, posterH);
    self.nameLabel.frame = CGRectMake(0, posterH + 4, w, kLabelHeight);
}

- (void)applyTheme {
    self.posterView.backgroundColor = [OETheme imagePlaceholderColor];
    self.posterView.layer.borderColor = [OETheme separatorColor].CGColor;
    self.nameLabel.textColor = [OETheme primaryTextColor];
}

- (void)configureWithItem:(OEEmbyItem *)item {
    self.representedItemId = item.itemId;
    self.nameLabel.text = item.name ?: @"未命名";
    self.posterView.image = nil;
    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:item width:220 height:330];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image) {
        if ([self.representedItemId isEqualToString:item.itemId]) self.posterView.image = image;
    }];
}

@end

@interface OEPosterGridCell ()
@property (nonatomic, strong) NSArray *slots; // OEPosterSlot x columnCount
@end

@implementation OEPosterGridCell

+ (NSInteger)columnCount { return 3; }

+ (CGFloat)posterWidthForTableWidth:(CGFloat)width {
    NSInteger columns = [self columnCount];
    return floor((width - 2 * kOuterPadding - (columns - 1) * kColumnSpacing) / columns);
}

+ (CGFloat)rowHeightForTableWidth:(CGFloat)width {
    CGFloat posterH = [self posterWidthForTableWidth:width] * 1.5;
    return kOuterPadding + posterH + 4 + kLabelHeight + kOuterPadding;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        NSMutableArray *slots = [NSMutableArray array];
        for (NSInteger i = 0; i < [OEPosterGridCell columnCount]; ++i) {
            OEPosterSlot *slot = [[OEPosterSlot alloc] initWithFrame:CGRectZero];
            [self.contentView addSubview:slot];
            [slots addObject:slot];
        }
        _slots = slots;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat posterW = [OEPosterGridCell posterWidthForTableWidth:width];
    CGFloat slotH = [OEPosterGridCell rowHeightForTableWidth:width] - 2 * kOuterPadding;
    for (NSInteger i = 0; i < self.slots.count; ++i) {
        OEPosterSlot *slot = self.slots[i];
        slot.frame = CGRectMake(kOuterPadding + i * (posterW + kColumnSpacing), kOuterPadding, posterW, slotH);
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    for (OEPosterSlot *slot in self.slots) {
        slot.hidden = YES;
        slot.representedItemId = nil;
        slot.posterView.image = nil;
        slot.nameLabel.text = nil;
    }
}

- (void)configureWithItems:(NSArray *)items startIndex:(NSInteger)startIndex target:(id)target action:(SEL)action {
    for (NSInteger i = 0; i < self.slots.count; ++i) {
        OEPosterSlot *slot = self.slots[i];
        NSInteger index = startIndex + i;
        [slot removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        if (index < items.count) {
            OEEmbyItem *item = items[index];
            slot.hidden = NO;
            slot.tag = index;
            [slot applyTheme];
            [slot configureWithItem:item];
            [slot addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
        } else {
            slot.hidden = YES;
        }
    }
    [self setNeedsLayout];
}

@end
