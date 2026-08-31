#import <UIKit/UIKit.h>
#import "Models/OEEmbyItem.h"

// A table row rendering poster slots side by side.
// iPad: landscape 10 columns, portrait 6; iPhone: 3 columns.
// The controller computes the column count once per layout pass and passes it
// to configureWithItems: so row height and slot frames can never disagree.
// Taps are reported as button-like target/action with the slot's tag set to
// the absolute item index (startIndex + column).
@interface OEPosterGridCell : UITableViewCell

+ (NSInteger)columnCount;
+ (NSInteger)columnCountForTableWidth:(CGFloat)width;
+ (NSInteger)columnCountForViewSize:(CGSize)size;
+ (CGFloat)posterWidthForTableWidth:(CGFloat)width;
+ (CGFloat)rowHeightForTableWidth:(CGFloat)width;
+ (CGFloat)rowHeightForViewSize:(CGSize)size;
// Row height for an explicit column count: the controller must use the same
// column count here and in configureWithItems:columns:...
+ (CGFloat)rowHeightForColumns:(NSInteger)columns tableWidth:(CGFloat)width;

- (void)configureWithItems:(NSArray *)items startIndex:(NSInteger)startIndex columns:(NSInteger)columns target:(id)target action:(SEL)action;

@end
