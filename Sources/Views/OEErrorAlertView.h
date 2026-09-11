#import <UIKit/UIKit.h>

// Modal error sheet whose message text can be selected and copied.
//
// UIAlertView on iOS 6-9 renders its message in a plain label: the user cannot
// select a word of it, which makes a long playback URL or a server error body
// impossible to report back. This view presents the same information in a
// selectable UITextView plus an explicit "复制" button that puts the whole
// message on the system pasteboard.
//
// Do NOT use this for failures raised while the movie player is full-screen:
// the sheet is added straight to the key window, whose coordinate space stays
// portrait on iOS 6-8, so it cannot follow the player's landscape orientation.
// Playback failures go through a native UIAlertView (see
// OEVideoDetailViewController -showPlaybackError:detail:), which the system
// rotates with the interface.
@interface OEErrorAlertView : UIView

// Presents the sheet over the key window. Use for browsing/loading failures
// shown while the interface is upright; nil/empty detail hides the detail
// area.
+ (void)showWithTitle:(NSString *)title message:(NSString *)message detail:(NSString *)detail;

// Convenience for network/API failures: renders the localized description as
// the message and the error domain/code (plus any underlying error) as the
// copyable detail.
+ (void)showWithTitle:(NSString *)title error:(NSError *)error;

@end
