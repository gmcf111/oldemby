#import <UIKit/UIKit.h>

// Modal error sheet whose message text can be selected and copied.
//
// UIAlertView on iOS 6-9 renders its message in a plain label: the user cannot
// select a word of it, which makes a long playback URL or a server error body
// impossible to report back. This view presents the same information in a
// selectable UITextView plus an explicit "复制" button that puts the whole
// message on the system pasteboard.
@interface OEErrorAlertView : UIView

// Presents the sheet over the key window. Safe to call from any playback
// failure path; nil/empty detail simply hides the detail area.
+ (void)showWithTitle:(NSString *)title message:(NSString *)message detail:(NSString *)detail;

// Convenience for network/API failures: renders the localized description as
// the message and the error domain/code (plus any underlying error) as the
// copyable detail.
+ (void)showWithTitle:(NSString *)title error:(NSError *)error;

@end
