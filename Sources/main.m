#import <UIKit/UIKit.h>
#import "AppDelegate.h"

// MPMoviePlayerController on iOS 6 schedules internal teardown and
// state-update callbacks via performSelector:afterDelay:.  When the
// player encounters a stream it cannot decode (e.g. H.265 in an mp4
// container, or an HLS variant the hardware decoder rejects), one of
// those delayed-perform callbacks throws an NSInvalidArgumentException.
// @try/@catch in the call site cannot intercept it because the throw
// happens in a separate RunLoop tick, long after the originating call
// returned.  The uncaught exception then propagates through
// __NSFireDelayedPerform -> objc_exception_throw -> abort.
//
// Installing a global handler before UIApplicationMain gives us a
// last-chance log before the process is terminated.
static void OEUncaughtExceptionHandler(NSException *exception) {
    NSLog(@"[OldEmby] *** Uncaught exception ***: %@\nReason: %@\nStack: %@",
          exception.name, exception.reason,
          [exception.callStackSymbols componentsJoinedByString:@"\n"]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(OEUncaughtExceptionHandler);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
