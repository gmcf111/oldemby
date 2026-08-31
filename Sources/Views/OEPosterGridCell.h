#import <UIKit/UIKit.h>
#import "Models/OEEmbyItem.h"

// A table row rendering poster slots side by side.
// iPad: landscape 6 columns (~4.5 rows visible), portrait 4 columns (~6.5 rows);
// iPhone: 3 columns. Columns are determined by view size / orientation.
// Taps are reported as button-like target/action with the slot's tag set to
// the absolute item index (startIndex + column).
@interface OEPosterGridCell : UITableViewCell

+ (NSInteger)columnCount;
+ (NSInteger)columnCountForTableWidth:(CGFloat)width;
+ (NSInteger)columnCountForViewSize:(CGSize)size;
+ (CGFloat)posterWidthForTableWidth:(CGFloat)width;
+ (CGFloat)rowHeightForTableWidth:(CGFloat)width;
+ (CGFloat)rowHeightForViewSize:(CGSize)size;

- (void)configureWithItems:(NSArray *)items startIndex:(NSInteger)startIndex target:(id)target action:(SEL)action;

@end
