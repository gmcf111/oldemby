#import <UIKit/UIKit.h>
@class OECastItem;

// A horizontally-scrollable cast (actors/crew) strip with circular photos
// and names. Designed for iOS 6 (no UICollectionView; uses UIScrollView).
@interface OECastStripView : UIView

@property (nonatomic, copy) NSArray *casts;

- (void)reloadData;

@end
