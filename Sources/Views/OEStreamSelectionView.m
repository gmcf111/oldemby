#import "OEStreamSelectionView.h"
#import "OETheme.h"

// Layout constants
static const CGFloat kSheetCornerRadius = 12.0;
static const CGFloat kSheetHorizontalMargin = 8.0;
static const CGFloat kSheetMaxWidth = 360.0;
static const CGFloat kRowHeight = 44.0;
static const CGFloat kHeaderHeight = 36.0;
static const CGFloat kSeparatorHeight = 0.5;
static const CGFloat kSheetBottomMargin = 0.0;
static const CGFloat kDimOpacity = 0.5;
static const CGFloat kCloseButtonSize = 36.0;

@implementation OEStreamInfo
@end

@interface OEStreamSelectionView ()
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *audioHeaderLabel;
@property (nonatomic, strong) UILabel *subtitleHeaderLabel;
@property (nonatomic, strong) NSMutableArray *audioRows;
@property (nonatomic, strong) NSMutableArray *subtitleRows;
@property (nonatomic, strong) NSArray *audioStreams;
@property (nonatomic, strong) NSArray *subtitleStreams;
@property (nonatomic, assign) NSInteger selectedAudioIndex;
@property (nonatomic, assign) NSInteger selectedSubtitleIndex;
@property (nonatomic, weak) id<OEStreamSelectionDelegate> delegate;
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic, strong) UIButton *closeButton;
@end

@implementation OEStreamSelectionView

- (instancetype)initWithFrame:(CGRect)frame
                   audioStreams:(NSArray *)audioStreams
                subtitleStreams:(NSArray *)subtitleStreams
             selectedAudioIndex:(NSInteger)audioIndex
          selectedSubtitleIndex:(NSInteger)subtitleIndex
                    delegate:(id<OEStreamSelectionDelegate>)delegate {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _audioStreams = audioStreams;
        _subtitleStreams = subtitleStreams;
        _selectedAudioIndex = audioIndex;
        _selectedSubtitleIndex = subtitleIndex;
        _delegate = delegate;
        _audioRows = [NSMutableArray array];
        _subtitleRows = [NSMutableArray array];
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    self.backgroundColor = [UIColor clearColor];

    _dimView = [[UIView alloc] initWithFrame:CGRectZero];
    _dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:kDimOpacity];
    _dimView.alpha = 0;
    UITapGestureRecognizer *dimTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    _dimView.userInteractionEnabled = YES;
    [_dimView addGestureRecognizer:dimTap];
    [self addSubview:_dimView];

    _sheetView = [[UIView alloc] initWithFrame:CGRectZero];
    _sheetView.backgroundColor = [OETheme cellColor];
    _sheetView.layer.cornerRadius = kSheetCornerRadius;
    _sheetView.layer.borderWidth = 0.5;
    _sheetView.layer.borderColor = [OETheme separatorColor].CGColor;
    _sheetView.clipsToBounds = YES;
    [self addSubview:_sheetView];

    _closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_closeButton setTitle:@"✕" forState:UIControlStateNormal];
    _closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    _closeButton.backgroundColor = [UIColor clearColor];
    [_closeButton setTitleColor:[OETheme secondaryTextColor] forState:UIControlStateNormal];
    [_closeButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [_sheetView addSubview:_closeButton];

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.showsVerticalScrollIndicator = YES;
    [_sheetView addSubview:_scrollView];

    // Build content inside scrollView
    [self buildContentInScrollView];
    [self applyTheme];
}

- (void)buildContentInScrollView {
    CGFloat w = [UIScreen mainScreen].bounds.size.width;
    w = MIN(w, kSheetMaxWidth);
    CGFloat contentW = w - 2 * kSheetHorizontalMargin;

    CGFloat y = kHeaderHeight;
    CGFloat totalHeight = 0;

    // Audio section header
    if (_audioStreams.count > 0) {
        _audioHeaderLabel = [self makeHeaderLabel:@"音轨"];
        [_scrollView addSubview:_audioHeaderLabel];
        y += kHeaderHeight;

        for (NSInteger i = 0; i < (NSInteger)_audioStreams.count; i++) {
            OEStreamInfo *info = _audioStreams[i];
            UIView *row = [self makeRowWithInfo:info
                                         index:i
                                      selected:(i == _selectedAudioIndex)
                                        isAudio:YES];
            row.frame = CGRectMake(0, y, contentW, kRowHeight);
            [_scrollView addSubview:row];
            [_audioRows addObject:row];
            y += kRowHeight;
        }
        y += 8;
    }

    // Subtitle section header
    _subtitleHeaderLabel = [self makeHeaderLabel:@"字幕"];
    [_scrollView addSubview:_subtitleHeaderLabel];
    y += kHeaderHeight;

    // "关闭字幕" option — index -1 means subtitles off
    OEStreamInfo *offInfo = [[OEStreamInfo alloc] init];
    offInfo.index = @"-1";
    offInfo.title = @"关闭字幕";
    UIView *offRow = [self makeRowWithInfo:offInfo
                                    index:-1
                                 selected:(_selectedSubtitleIndex == -1)
                                   isAudio:NO];
    offRow.frame = CGRectMake(0, y, contentW, kRowHeight);
    [_scrollView addSubview:offRow];
    [_subtitleRows addObject:offRow];
    y += kRowHeight;

    for (NSInteger i = 0; i < (NSInteger)_subtitleStreams.count; i++) {
        OEStreamInfo *info = _subtitleStreams[i];
        UIView *row = [self makeRowWithInfo:info
                                     index:i
                                  selected:(i == _selectedSubtitleIndex)
                                    isAudio:NO];
        row.frame = CGRectMake(0, y, contentW, kRowHeight);
        [_scrollView addSubview:row];
        [_subtitleRows addObject:row];
        y += kRowHeight;
    }

    totalHeight = y + 8;
    _scrollView.contentSize = CGSizeMake(contentW, totalHeight);
}

- (UILabel *)makeHeaderLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont boldSystemFontOfSize:14];
    label.text = text;
    label.textColor = [OETheme accentColor];
    label.backgroundColor = [UIColor clearColor];
    return label;
}

- (UIView *)makeRowWithInfo:(OEStreamInfo *)info
                     index:(NSInteger)index
                  selected:(BOOL)selected
                    isAudio:(BOOL)isAudio {
    UIView *row = [[UIView alloc] init];
    row.backgroundColor = [UIColor clearColor];
    row.tag = index;
    row.userInteractionEnabled = YES;

    // Separator at bottom
    UIView *sep = [[UIView alloc] init];
    sep.backgroundColor = [OETheme separatorColor];
    sep.alpha = 0.5;
    [row addSubview:sep];

    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:14];
    label.text = info.title.length ? info.title : @"未知";
    label.textColor = selected ? [OETheme accentColor] : [OETheme primaryTextColor];
    label.backgroundColor = [UIColor clearColor];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [row addSubview:label];

    // Checkmark for selected
    UILabel *check = [[UILabel alloc] init];
    check.font = [UIFont boldSystemFontOfSize:16];
    check.text = selected ? @"✓" : @"";
    check.textColor = [OETheme accentColor];
    check.backgroundColor = [UIColor clearColor];
    check.textAlignment = NSTextAlignmentRight;
    [row addSubview:check];

    // Layout subviews within row
    CGFloat w = [UIScreen mainScreen].bounds.size.width;
    w = MIN(w, kSheetMaxWidth) - 2 * kSheetHorizontalMargin;
    CGFloat pad = 14;
    CGFloat checkW = 24;
    label.frame = CGRectMake(pad, 0, w - pad - checkW - pad, kRowHeight);
    check.frame = CGRectMake(w - checkW - pad, 0, checkW, kRowHeight);
    sep.frame = CGRectMake(pad, kRowHeight - kSeparatorHeight, w - 2 * pad, kSeparatorHeight);

    // Tap gesture
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rowTapped:)];
    tap.delegate = nil;
    tap.cancelsTouchesInView = YES;
    [row addGestureRecognizer:tap];
    row.tag = 1000 + (isAudio ? 0 : 10000) + (index + 1);

    return row;
}

- (void)rowTapped:(UITapGestureRecognizer *)gesture {
    NSInteger tag = gesture.view.tag;
    BOOL isAudio = (tag / 10000) == 0;
    NSInteger index = (tag % 10000) - 1;

    if (isAudio) {
        if (index >= 0 && index < (NSInteger)_audioStreams.count) {
            _selectedAudioIndex = index;
            [self updateRowSelections];
            if ([_delegate respondsToSelector:@selector(streamSelectionView:didSelectAudioIndex:)]) {
                [_delegate streamSelectionView:self didSelectAudioIndex:index];
            }
        }
    } else {
        _selectedSubtitleIndex = index;
        [self updateRowSelections];
        if ([_delegate respondsToSelector:@selector(streamSelectionView:didSelectSubtitleIndex:)]) {
            [_delegate streamSelectionView:self didSelectSubtitleIndex:index];
        }
    }
}

- (void)updateRowSelections {
    for (NSInteger i = 0; i < (NSInteger)_audioRows.count; i++) {
        UIView *row = _audioRows[i];
        BOOL selected = (i == _selectedAudioIndex);
        UILabel *label = [self findLabelInView:row];
        UILabel *check = [self findCheckInView:row];
        label.textColor = selected ? [OETheme accentColor] : [OETheme primaryTextColor];
        check.text = selected ? @"✓" : @"";
    }
    for (NSInteger i = 0; i < (NSInteger)_subtitleRows.count; i++) {
        UIView *row = _subtitleRows[i];
        // Actual stream index in _subtitleRows: row 0 is "off" (index -1),
        // row 1+ maps to _subtitleStreams[i-1].
        NSInteger actualIndex = (i == 0) ? -1 : (i - 1);
        BOOL selected = (actualIndex == _selectedSubtitleIndex);
        UILabel *label = [self findLabelInView:row];
        UILabel *check = [self findCheckInView:row];
        label.textColor = selected ? [OETheme accentColor] : [OETheme primaryTextColor];
        check.text = selected ? @"✓" : @"";
    }
}

- (UILabel *)findLabelInView:(UIView *)row {
    for (UIView *v in row.subviews) {
        if ([v isKindOfClass:[UILabel class]] && [(UILabel *)v text].length > 0 && ![[(UILabel *)v text] isEqualToString:@"✓"]) return (UILabel *)v;
    }
    return nil;
}

- (UILabel *)findCheckInView:(UIView *)row {
    for (UIView *v in row.subviews) {
        if ([v isKindOfClass:[UILabel class]] && ([[(UILabel *)v text] isEqualToString:@"✓"] || [(UILabel *)v text].length == 0)) {
            // Prefer the rightmost one
            if (v.frame.origin.x > 100) return (UILabel *)v;
        }
    }
    // Fallback: any label with right alignment
    for (UIView *v in row.subviews) {
        if ([v isKindOfClass:[UILabel class]] && ((UILabel *)v).textAlignment == NSTextAlignmentRight) return (UILabel *)v;
    }
    return nil;
}

- (void)applyTheme {
    _sheetView.backgroundColor = [OETheme cellColor];
    _sheetView.layer.borderColor = [OETheme separatorColor].CGColor;
    _audioHeaderLabel.textColor = [OETheme accentColor];
    _subtitleHeaderLabel.textColor = [OETheme accentColor];
    _closeButton.backgroundColor = [UIColor clearColor];
    [_closeButton setTitleColor:[OETheme secondaryTextColor] forState:UIControlStateNormal];
}

- (void)showInWindow:(UIWindow *)window {
    _window = window;
    self.frame = window.bounds;
    [window addSubview:self];

    // Calculate sheet size
    CGFloat screenW = window.bounds.size.width;
    CGFloat screenH = window.bounds.size.height;
    CGFloat sheetW = MIN(screenW, kSheetMaxWidth);
    CGFloat contentH = _scrollView.contentSize.height;
    CGFloat sheetH = contentH + kHeaderHeight + 10;  // header + padding
    CGFloat maxSheetH = screenH * 0.7;
    if (sheetH > maxSheetH) sheetH = maxSheetH;

    CGFloat sheetX = (screenW - sheetW) / 2.0;
    CGFloat sheetY = screenH - sheetH - kSheetBottomMargin;

    _dimView.frame = self.bounds;
    _sheetView.frame = CGRectMake(sheetX, screenH, sheetW, sheetH);
    _scrollView.frame = CGRectMake(0, kHeaderHeight, sheetW, sheetH - kHeaderHeight);
    _closeButton.frame = CGRectMake(sheetW - kCloseButtonSize - 4, 2, kCloseButtonSize, kHeaderHeight);

    // Position headers in scrollView (they were added without frames)
    CGFloat contentW = sheetW - 2 * kSheetHorizontalMargin;
    _audioHeaderLabel.frame = CGRectMake(kSheetHorizontalMargin, 0, contentW, kHeaderHeight);

    if (_subtitleHeaderLabel) {
        // Recalculate positions
        CGFloat y = kHeaderHeight;
        if (_audioStreams.count > 0) {
            y += kHeaderHeight + _audioStreams.count * kRowHeight + 8;
        }
        _subtitleHeaderLabel.frame = CGRectMake(kSheetHorizontalMargin, y, contentW, kHeaderHeight);
    }

    // Re-layout all rows within the scrollView's coordinate space
    [self layoutContentWithWidth:sheetW];

    // Animate in
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:0.25];
    _dimView.alpha = 1.0;
    _sheetView.frame = CGRectMake(sheetX, sheetY, sheetW, sheetH);
    [UIView commitAnimations];
}

- (void)layoutContentWithWidth:(CGFloat)sheetW {
    CGFloat contentW = sheetW - 2 * kSheetHorizontalMargin;
    CGFloat pad = 14;
    CGFloat checkW = 24;
    CGFloat labelW = contentW - 2 * pad - checkW;

    CGFloat y = kHeaderHeight;

    // Audio header
    if (_audioStreams.count > 0) {
        _audioHeaderLabel.frame = CGRectMake(kSheetHorizontalMargin, y - kHeaderHeight, contentW, kHeaderHeight);
        for (NSInteger i = 0; i < (NSInteger)_audioRows.count; i++) {
            UIView *row = _audioRows[i];
            row.frame = CGRectMake(0, y, contentW, kRowHeight);
            [self relayoutRowSubviews:row width:contentW pad:pad checkW:checkW labelW:labelW];
            y += kRowHeight;
        }
        y += 8;
    }

    // Subtitle header
    if (_subtitleHeaderLabel) {
        _subtitleHeaderLabel.frame = CGRectMake(kSheetHorizontalMargin, y, contentW, kHeaderHeight);
        y += kHeaderHeight;
    }

    // Subtitle rows (including "off")
    for (NSInteger i = 0; i < (NSInteger)_subtitleRows.count; i++) {
        UIView *row = _subtitleRows[i];
        row.frame = CGRectMake(0, y, contentW, kRowHeight);
        [self relayoutRowSubviews:row width:contentW pad:pad checkW:checkW labelW:labelW];
        y += kRowHeight;
    }

    y += 8;
    _scrollView.contentSize = CGSizeMake(contentW, y);
    _scrollView.frame = CGRectMake(0, kHeaderHeight, sheetW, _sheetView.frame.size.height - kHeaderHeight);
}

- (void)relayoutRowSubviews:(UIView *)row width:(CGFloat)w pad:(CGFloat)pad checkW:(CGFloat)checkW labelW:(CGFloat)labelW {
    for (UIView *v in row.subviews) {
        if ([v isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)v;
            if (label.textAlignment == NSTextAlignmentRight) {
                label.frame = CGRectMake(w - checkW - pad, 0, checkW, kRowHeight);
            } else {
                label.frame = CGRectMake(pad, 0, labelW, kRowHeight);
            }
        } else {
            // Separator
            v.frame = CGRectMake(pad, kRowHeight - kSeparatorHeight, w - 2 * pad, kSeparatorHeight);
        }
    }
}

- (void)dismiss {
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:0.2];
    _dimView.alpha = 0;
    CGRect f = _sheetView.frame;
    f.origin.y = _window.bounds.size.height;
    _sheetView.frame = f;
    [UIView commitAnimations];

    // Remove after animation
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf removeFromSuperview];
            if ([strongSelf.delegate respondsToSelector:@selector(streamSelectionViewDidDismiss:)]) {
                [strongSelf.delegate streamSelectionViewDidDismiss:strongSelf];
            }
        }
    });
}

@end
