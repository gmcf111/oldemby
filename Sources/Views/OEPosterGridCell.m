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

static const NSInteger kMaxColumns = 6;

@implementation OEPosterGridCell

+ (NSInteger)columnCountForViewSize:(CGSize)size {
    BOOL isPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    if (!isPad) return 3;
    // iPad: 横屏每行 6 个（宽 > 高），竖屏每行 4 个（高 > 宽），自然形成
    // 横屏约 4.5 行、竖屏约 6.5 行的半行露出效果，满足用户“海报太大”问题的密度需求。
    return size.width > size.height ? 6 : 4;
}

+ (NSInteger)columnCountForTableWidth:(CGFloat)width {
    BOOL isPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    if (!isPad) return 3;
    // 优先用 window 尺寸（与 view.bounds 同步，旋转时最及时）
    UIWindow *win = [[UIApplication sharedApplication] keyWindow];
    if (win) {
        CGSize winSize = win.bounds.size;
        if (winSize.width > 0 && winSize.height > 0) {
            if (winSize.width > winSize.height) return 6;
            if (winSize.width < winSize.height) return 4;
        }
    }
    UIInterfaceOrientation orient = [[UIApplication sharedApplication] statusBarOrientation];
    if (UIInterfaceOrientationIsLandscape(orient)) return 6;
    if (UIInterfaceOrientationIsPortrait(orient)) return 4;
    // 未知方向时回退到尺寸判断；iOS 8+ screen 已旋转，iOS 6-7 始终竖屏
    CGSize screen = [UIScreen mainScreen].bounds.size;
    if (screen.width > screen.height) return 6;
    // 宽度阈值兜底：常规 iPad 横屏 1024 / 竖屏 768；未知时默认竖屏 4 列
    if (width >= 900) {
        // 1024 可能是常规 iPad 横屏或 iPad Pro 竖屏，优先按竖屏 4 处理避免过大误判
        // 只有明显大于 1024 时才认为是横屏
        if (width > 1024) return 6;
        // 常规 iPad 横屏 1024 时，若 screen 高度也 >=1024 说明是 iPad Pro 竖屏歧义，保守返回 4
        if (width == 1024 && screen.height >= 1024) return 4;
        return 6;
    }
    return 4;
}

+ (NSInteger)columnCount {
    // 兼容旧调用：优先用 window/方向，其次用屏幕尺寸
    BOOL isPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    if (isPad) {
        UIWindow *win = [[UIApplication sharedApplication] keyWindow];
        if (win) {
            CGSize winSize = win.bounds.size;
            if (winSize.width > winSize.height) return 6;
            if (winSize.width < winSize.height) return 4;
        }
        UIInterfaceOrientation orient = [[UIApplication sharedApplication] statusBarOrientation];
        if (UIInterfaceOrientationIsLandscape(orient)) return 6;
        if (UIInterfaceOrientationIsPortrait(orient)) return 4;
        CGSize screen = [UIScreen mainScreen].bounds.size;
        if (screen.width > screen.height) return 6;
        return 4;
    }
    return 3;
}

+ (CGFloat)posterWidthForTableWidth:(CGFloat)width {
    NSInteger columns = [self columnCountForTableWidth:width];
    if (columns < 1) columns = 3;
    return floor((width - 2 * kOuterPadding - (columns - 1) * kColumnSpacing) / columns);
}

+ (CGFloat)rowHeightForTableWidth:(CGFloat)width {
    CGFloat posterH = [self posterWidthForTableWidth:width] * 1.5;
    return kOuterPadding + posterH + 4 + kLabelHeight + kOuterPadding;
}

+ (CGFloat)rowHeightForViewSize:(CGSize)size {
    NSInteger columns = [self columnCountForViewSize:size];
    CGFloat posterW = floor((size.width - 2 * kOuterPadding - (columns - 1) * kColumnSpacing) / columns);
    CGFloat posterH = posterW * 1.5;
    return kOuterPadding + posterH + 4 + kLabelHeight + kOuterPadding;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        NSMutableArray *slots = [NSMutableArray array];
        for (NSInteger i = 0; i < kMaxColumns; ++i) {
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
    CGFloat width = self.contentView.bounds.size.width;
    if (width < 1) width = self.bounds.size.width;
    NSInteger cols = [OEPosterGridCell columnCountForTableWidth:width];
    if (cols < 1) cols = 3;
    if (cols > (NSInteger)self.slots.count) cols = self.slots.count;
    for (NSInteger i = 0; i < (NSInteger)self.slots.count; ++i) {
        OEPosterSlot *slot = self.slots[i];
        [slot removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        if (i >= cols) {
            slot.hidden = YES;
            continue;
        }
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
