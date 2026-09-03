#import <UIKit/UIKit.h>

// A simple subtitle overlay that displays text lines at the bottom of the
// video player view. Designed for iOS 6: pure frame layout, no Auto Layout.
@interface OESubtitleOverlayView : UIView

// Extra space to keep free below the text. Raised while the system control bar
// is on screen so the bar never covers a line.
@property (nonatomic, assign) CGFloat bottomInset;

// Show the given text (may be multi-line). Pass nil or empty to clear.
- (void)setSubtitleText:(NSString *)text;

// Apply theme colors.
- (void)applyTheme;

@end
