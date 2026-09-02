#import "OEErrorAlertView.h"
#import "OETheme.h"

static const CGFloat kAlertSideMargin = 20.0;
static const CGFloat kAlertPadding = 16.0;
static const CGFloat kAlertButtonHeight = 44.0;
static const CGFloat kAlertMaxWidth = 420.0;
static const CGFloat kAlertDetailMinHeight = 60.0;
static const CGFloat kAlertDetailMaxHeight = 200.0;

@interface OEErrorAlertView ()
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UITextView *detailView;
@property (nonatomic, strong) UIButton *pasteButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIView *separatorTop;
@property (nonatomic, strong) UIView *separatorMiddle;
@property (nonatomic, copy) NSString *pasteboardPayload;
// A presented sheet retains itself until dismissed: the caller is often a
// controller that is being torn down by the same failure.
@property (nonatomic, strong) OEErrorAlertView *selfRetain;
@end

@implementation OEErrorAlertView

+ (void)showWithTitle:(NSString *)title message:(NSString *)message detail:(NSString *)detail {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) {
        NSArray *windows = [UIApplication sharedApplication].windows;
        window = windows.count ? windows[0] : nil;
    }
    if (!window) return;
    OEErrorAlertView *view = [[OEErrorAlertView alloc] initWithTitle:title message:message detail:detail];
    view.frame = window.bounds;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.selfRetain = view;
    [window addSubview:view];
    [view animateIn];
}

+ (void)showWithTitle:(NSString *)title error:(NSError *)error {
    NSMutableString *detail = [NSMutableString string];
    if (error) {
        [detail appendFormat:@"错误域：%@\n错误码：%ld", error.domain ?: @"-", (long)error.code];
        NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
        if ([underlying isKindOfClass:[NSError class]]) {
            [detail appendFormat:@"\n底层错误：%@ (%ld)", underlying.domain ?: @"-", (long)underlying.code];
            if (underlying.localizedDescription.length) [detail appendFormat:@"\n%@", underlying.localizedDescription];
        }
        NSURL *failingURL = error.userInfo[NSURLErrorFailingURLErrorKey];
        if ([failingURL isKindOfClass:[NSURL class]]) [detail appendFormat:@"\n地址：%@", failingURL.absoluteString];
    }
    [self showWithTitle:title
                message:error.localizedDescription.length ? error.localizedDescription : @"未知错误"
                 detail:detail];
}

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message detail:(NSString *)detail {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;

    // The copyable payload joins message and detail so one tap grabs
    // everything worth pasting into a bug report.
    NSMutableString *payload = [NSMutableString string];
    if (message.length) [payload appendString:message];
    if (detail.length) {
        if (payload.length) [payload appendString:@"\n\n"];
        [payload appendString:detail];
    }
    _pasteboardPayload = [payload copy];

    self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];

    _panel = [[UIView alloc] initWithFrame:CGRectZero];
    _panel.backgroundColor = [OETheme isLight] ? [UIColor whiteColor] : [UIColor colorWithWhite:0.16 alpha:1.0];
    _panel.layer.cornerRadius = 10.0;
    _panel.clipsToBounds = YES;
    [self addSubview:_panel];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.font = [UIFont boldSystemFontOfSize:17];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 2;
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.textColor = [OETheme primaryTextColor];
    _titleLabel.text = title.length ? title : @"播放失败";
    [_panel addSubview:_titleLabel];

    _messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _messageLabel.font = [UIFont systemFontOfSize:14];
    _messageLabel.textAlignment = NSTextAlignmentCenter;
    _messageLabel.numberOfLines = 0;
    _messageLabel.backgroundColor = [UIColor clearColor];
    _messageLabel.textColor = [OETheme primaryTextColor];
    _messageLabel.text = message.length ? message : @"未知错误";
    [_panel addSubview:_messageLabel];

    if (detail.length) {
        // Selectable but not editable: the user can drag-select any part of
        // the URL or server body. Editing is pointless and would raise the
        // keyboard over the sheet.
        _detailView = [[UITextView alloc] initWithFrame:CGRectZero];
        _detailView.editable = NO;
        _detailView.font = [UIFont systemFontOfSize:12];
        _detailView.text = detail;
        _detailView.backgroundColor = [OETheme isLight]
            ? [UIColor colorWithWhite:0.95 alpha:1.0]
            : [UIColor colorWithWhite:0.10 alpha:1.0];
        _detailView.textColor = [OETheme secondaryTextColor];
        _detailView.layer.cornerRadius = 6.0;
        _detailView.layer.borderWidth = 1.0;
        _detailView.layer.borderColor = [OETheme separatorColor].CGColor;
        [_panel addSubview:_detailView];
    }

    _separatorTop = [[UIView alloc] initWithFrame:CGRectZero];
    _separatorTop.backgroundColor = [OETheme separatorColor];
    [_panel addSubview:_separatorTop];

    _separatorMiddle = [[UIView alloc] initWithFrame:CGRectZero];
    _separatorMiddle.backgroundColor = [OETheme separatorColor];
    [_panel addSubview:_separatorMiddle];

    _pasteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _pasteButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [_pasteButton setTitle:@"复制" forState:UIControlStateNormal];
    [_pasteButton setTitleColor:[OETheme accentColor] forState:UIControlStateNormal];
    [_pasteButton addTarget:self action:@selector(copyTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_pasteButton];

    _closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [_closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    [_closeButton setTitleColor:[OETheme accentColor] forState:UIControlStateNormal];
    [_closeButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_closeButton];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat available = self.bounds.size.width - 2 * kAlertSideMargin;
    CGFloat panelWidth = MIN(available, kAlertMaxWidth);
    CGFloat contentWidth = panelWidth - 2 * kAlertPadding;
    if (contentWidth < 1) return;

    CGFloat y = kAlertPadding;

    CGSize titleSize = [self.titleLabel.text sizeWithFont:self.titleLabel.font
                                        constrainedToSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
                                            lineBreakMode:NSLineBreakByWordWrapping];
    self.titleLabel.frame = CGRectMake(kAlertPadding, y, contentWidth, ceil(titleSize.height));
    y = CGRectGetMaxY(self.titleLabel.frame) + 10;

    CGSize messageSize = [self.messageLabel.text sizeWithFont:self.messageLabel.font
                                            constrainedToSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
                                                lineBreakMode:NSLineBreakByWordWrapping];
    self.messageLabel.frame = CGRectMake(kAlertPadding, y, contentWidth, ceil(messageSize.height));
    y = CGRectGetMaxY(self.messageLabel.frame) + 12;

    if (self.detailView) {
        CGSize detailSize = [self.detailView.text sizeWithFont:self.detailView.font
                                             constrainedToSize:CGSizeMake(contentWidth - 12, CGFLOAT_MAX)
                                                 lineBreakMode:NSLineBreakByCharWrapping];
        CGFloat detailHeight = MAX(kAlertDetailMinHeight, MIN(ceil(detailSize.height) + 20, kAlertDetailMaxHeight));
        self.detailView.frame = CGRectMake(kAlertPadding, y, contentWidth, detailHeight);
        y = CGRectGetMaxY(self.detailView.frame) + 12;
    }

    self.separatorTop.frame = CGRectMake(0, y, panelWidth, 0.5);
    y += 0.5;

    CGFloat halfWidth = floor(panelWidth / 2.0);
    self.pasteButton.frame = CGRectMake(0, y, halfWidth, kAlertButtonHeight);
    self.separatorMiddle.frame = CGRectMake(halfWidth, y, 0.5, kAlertButtonHeight);
    self.closeButton.frame = CGRectMake(halfWidth, y, panelWidth - halfWidth, kAlertButtonHeight);
    y += kAlertButtonHeight;

    CGFloat panelHeight = y;
    self.panel.frame = CGRectMake(floor((self.bounds.size.width - panelWidth) / 2.0),
                                  floor((self.bounds.size.height - panelHeight) / 2.0),
                                  panelWidth, panelHeight);
}

- (void)animateIn {
    self.alpha = 0.0;
    self.panel.transform = CGAffineTransformMakeScale(0.9, 0.9);
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 1.0;
        self.panel.transform = CGAffineTransformIdentity;
    }];
}

- (void)copyTapped {
    [UIPasteboard generalPasteboard].string = self.pasteboardPayload ?: @"";
    [self.pasteButton setTitle:@"已复制" forState:UIControlStateNormal];
    // Restore the label so a second copy is obviously available.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.pasteButton setTitle:@"复制" forState:UIControlStateNormal];
    });
}

- (void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        // Drop the self-retain last so the view stays alive through teardown.
        self.selfRetain = nil;
    }];
}

@end
