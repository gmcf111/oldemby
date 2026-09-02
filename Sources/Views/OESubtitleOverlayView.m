#import "OESubtitleOverlayView.h"
#import "OETheme.h"

static const CGFloat kSubtitleMaxWidth = 0.85;  // fraction of screen width
static const CGFloat kSubtitleBottomMargin = 12.0;
static const CGFloat kSubtitleHorizontalPadding = 12.0;
static const CGFloat kSubtitleVerticalPadding = 8.0;

@interface OESubtitleOverlayView ()
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIView *bgView;
@end

@implementation OESubtitleOverlayView

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;

        _bgView = [[UIView alloc] initWithFrame:CGRectZero];
        _bgView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
        _bgView.layer.cornerRadius = 4;
        [self addSubview:_bgView];

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.font = [UIFont systemFontOfSize:15];
        _label.textColor = [UIColor whiteColor];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.numberOfLines = 0;
        _label.lineBreakMode = NSLineBreakByWordWrapping;
        _label.backgroundColor = [UIColor clearColor];
        [self addSubview:_label];

        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    // Subtitles are always white-on-black for readability over video.
    _label.textColor = [UIColor whiteColor];
    _bgView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
}

- (void)setSubtitleText:(NSString *)text {
    if (!text.length) {
        _label.text = nil;
        _bgView.hidden = YES;
        [self setNeedsLayout];
        return;
    }
    _bgView.hidden = NO;
    _label.text = text;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat selfW = self.bounds.size.width;
    CGFloat selfH = self.bounds.size.height;
    if (selfW < 1 || selfH < 1) return;

    CGFloat maxLabelW = selfW * kSubtitleMaxWidth;
    CGSize constraint = CGSizeMake(maxLabelW - 2 * kSubtitleHorizontalPadding, CGFLOAT_MAX);
    CGSize textSize = [_label.text sizeWithFont:_label.font
                              constrainedToSize:constraint
                                  lineBreakMode:NSLineBreakByWordWrapping];
    if (textSize.width < 1 || textSize.height < 1) {
        _bgView.hidden = YES;
        return;
    }

    CGFloat labelW = textSize.width;
    CGFloat labelH = textSize.height;
    CGFloat bgW = labelW + 2 * kSubtitleHorizontalPadding;
    CGFloat bgH = labelH + 2 * kSubtitleVerticalPadding;

    CGFloat bgX = (selfW - bgW) / 2.0;
    CGFloat bgY = selfH - bgH - kSubtitleBottomMargin;

    _bgView.frame = CGRectMake(bgX, bgY, bgW, bgH);
    _label.frame = CGRectMake(bgX + kSubtitleHorizontalPadding,
                             bgY + kSubtitleVerticalPadding,
                             labelW, labelH);
}

@end
