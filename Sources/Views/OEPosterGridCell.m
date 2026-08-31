#import "OEPosterGridCell.h"
#import "OETheme.h"
#import "Services/OEImageCache.h"
#import "Services/OEEmbyAPIClient.h"
#import <math.h>

static const CGFloat kOuterPadding = 12.0;
static const CGFloat kColumnSpacing = 10.0;
// Poster image area only; the name label height is budgeted separately so a
// two-line title can never overflow into the next row.
static const CGFloat kLabelHeight = 34.0;
static const CGFloat kLabelGap = 3.0;
// Hard cap on the number of slots a cell can host; iPad landscape 10 columns.
static const NSInteger kMaxColumns = 10;

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
        _nameLabel.font = [UIFont systemFontOfSize:11];
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
    CGFloat h = self.bounds.size.height;
    // Guarantee the poster + label always fit inside the slot even if the
    // slot was laid out with a stale frame: clamp heights to bounds first.
    CGFloat labelH = MIN(kLabelHeight, h * 0.35);
    CGFloat posterH = h - labelH - kLabelGap;
    if (posterH < 10) posterH = MAX(10, h - labelH);
    self.posterView.frame = CGRectMake(0, 0, w, MAX(1, posterH));
    self.nameLabel.frame = CGRectMake(0, MAX(1, posterH) + kLabelGap, w, labelH);
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
// Slots laid out for a specific column count; lazily grown up to kMaxColumns.
@property (nonatomic, strong) NSMutableArray *slots;
@property (nonatomic, assign) NSInteger configuredColumns;
@end

@implementation OEPosterGridCell

+ (NSInteger)columnCountForViewSize:(CGSize)size {
    BOOL isPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    if (!isPad) return 3;
    // iPad: landscape packs 10 per row so posters stay small, portrait 6.
    return size.width > size.height ? 10 : 6;
}

+ (NSInteger)columnCountForTableWidth:(CGFloat)width {
    BOOL isPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    if (!isPad) return 3;
    // Prefer the window size (tracks rotation immediately).
    UIWindow *win = [[UIApplication sharedApplication] keyWindow];
    if (win) {
        CGSize winSize = win.bounds.size;
        if (winSize.width > 0 && winSize.height > 0) {
            if (winSize.width > winSize.height) return 10;
            if (winSize.width < winSize.height) return 6;
        }
    }
    UIInterfaceOrientation orient = [[UIApplication sharedApplication] statusBarOrientation];
    if (UIInterfaceOrientationIsLandscape(orient)) return 10;
    if (UIInterfaceOrientationIsPortrait(orient)) return 6;
    // Unknown orientation: fall back to the screen size; iOS 6-7 screens are
    // always portrait, iOS 8+ rotate.
    CGSize screen = [UIScreen mainScreen].bounds.size;
    if (screen.width > screen.height) return 10;
    if (width >= 900) {
        if (width > 1024) return 10;
        if (width == 1024 && screen.height >= 1024) return 6;
        return 10;
    }
    return 6;
}

+ (NSInteger)columnCount {
    BOOL isPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    if (isPad) {
        UIWindow *win = [[UIApplication sharedApplication] keyWindow];
        if (win) {
            CGSize winSize = win.bounds.size;
            if (winSize.width > winSize.height) return 10;
            if (winSize.width < winSize.height) return 6;
        }
        UIInterfaceOrientation orient = [[UIApplication sharedApplication] statusBarOrientation];
        if (UIInterfaceOrientationIsLandscape(orient)) return 10;
        if (UIInterfaceOrientationIsPortrait(orient)) return 6;
        CGSize screen = [UIScreen mainScreen].bounds.size;
        if (screen.width > screen.height) return 10;
        return 6;
    }
    return 3;
}

+ (CGFloat)posterWidthForColumns:(NSInteger)columns width:(CGFloat)width {
    if (columns < 1) columns = 3;
    return floor((width - 2 * kOuterPadding - (columns - 1) * kColumnSpacing) / columns);
}

+ (CGFloat)posterWidthForTableWidth:(CGFloat)width {
    return [self posterWidthForColumns:[self columnCountForTableWidth:width] width:width];
}

+ (CGFloat)rowHeightForColumns:(NSInteger)columns tableWidth:(CGFloat)width {
    CGFloat posterW = [self posterWidthForColumns:columns width:width];
    return kOuterPadding + posterW * 1.5 + kLabelGap + kLabelHeight + kOuterPadding;
}

+ (CGFloat)rowHeightForTableWidth:(CGFloat)width {
    return [self rowHeightForColumns:[self columnCountForTableWidth:width] tableWidth:width];
}

+ (CGFloat)rowHeightForViewSize:(CGSize)size {
    return [self rowHeightForColumns:[self columnCountForViewSize:size] tableWidth:size.width];
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        _slots = [NSMutableArray array];
        _configuredColumns = 0;
    }
    return self;
}

- (OEPosterSlot *)slotAtIndex:(NSInteger)index {
    while (self.slots.count <= (NSUInteger)index) {
        OEPosterSlot *slot = [[OEPosterSlot alloc] initWithFrame:CGRectZero];
        slot.hidden = YES;
        [self.contentView addSubview:slot];
        [self.slots addObject:slot];
    }
    return self.slots[index];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    for (OEPosterSlot *slot in self.slots) {
        slot.hidden = YES;
        slot.representedItemId = nil;
        slot.posterView.image = nil;
        slot.nameLabel.text = nil;
    }
    self.configuredColumns = 0;
}

- (void)layoutSlotsWithColumns:(NSInteger)columns {
    CGFloat width = self.contentView.bounds.size.width;
    if (width < 1) width = self.bounds.size.width;
    if (columns < 1) columns = 3;
    if (columns > kMaxColumns) columns = kMaxColumns;
    CGFloat posterW = [OEPosterGridCell posterWidthForColumns:columns width:width];
    CGFloat slotH = [OEPosterGridCell rowHeightForColumns:columns tableWidth:width] - 2 * kOuterPadding;
    for (NSInteger i = 0; i < columns; ++i) {
        OEPosterSlot *slot = [self slotAtIndex:i];
        slot.frame = CGRectMake(kOuterPadding + i * (posterW + kColumnSpacing), kOuterPadding, posterW, MAX(1, slotH));
    }
    // Hide any slot beyond the current column count.
    for (NSInteger i = columns; i < (NSInteger)self.slots.count; ++i) {
        self.slots[i].hidden = YES;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutSlotsWithColumns:self.configuredColumns];
}

- (void)configureWithItems:(NSArray *)items startIndex:(NSInteger)startIndex columns:(NSInteger)columns target:(id)target action:(SEL)action {
    CGFloat width = self.contentView.bounds.size.width;
    if (width < 1) width = self.bounds.size.width;
    if (columns < 1) columns = [OEPosterGridCell columnCountForTableWidth:width];
    if (columns > kMaxColumns) columns = kMaxColumns;
    self.configuredColumns = columns;
    for (NSInteger i = 0; i < columns; ++i) {
        OEPosterSlot *slot = [self slotAtIndex:i];
        [slot removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        NSInteger index = startIndex + i;
        if (index < (NSInteger)items.count) {
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
