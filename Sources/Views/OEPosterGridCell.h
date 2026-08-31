#import <UIKit/UIKit.h>
#import "Models/OEEmbyItem.h"

// A table row rendering OEPosterGridCellColumns poster slots side by side.
// Taps are reported as button-like target/action with the slot's tag set to
// the absolute item index (startIndex + column).
@interface OEPosterGridCell : UITableViewCell

+ (NSInteger)columnCount;
+ (CGFloat)posterWidthForTableWidth:(CGFloat)width;
+ (CGFloat)rowHeightForTableWidth:(CGFloat)width;

- (void)configureWithItems:(NSArray *)items startIndex:(NSInteger)startIndex target:(id)target action:(SEL)action;

@end
