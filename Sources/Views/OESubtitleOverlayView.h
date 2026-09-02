#import <UIKit/UIKit.h>

// A simple subtitle overlay that displays text lines at the bottom of the
// video player view. Designed for iOS 6: pure frame layout, no Auto Layout.
@interface OESubtitleOverlayView : UIView

// Show the given text (may be multi-line). Pass nil or empty to clear.
- (void)setSubtitleText:(NSString *)text;

// Apply theme colors.
- (void)applyTheme;

@end
