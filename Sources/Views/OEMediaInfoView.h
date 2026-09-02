#import <UIKit/UIKit.h>

// Displays video and audio stream information (codec, resolution, bitrate,
// channels, etc.) parsed from an Emby PlaybackInfo / MediaSources response.
// Designed for iOS 6: pure frame layout, no Auto Layout or UICollectionView.
@interface OEMediaInfoView : UIView

// Pass the MediaSources array from a PlaybackInfo or item-detail response.
// The view rebuilds its subviews on each set.
@property (nonatomic, copy) NSArray *mediaSources;

// Convenience: calculate the height needed for the given width.
- (CGFloat)heightForWidth:(CGFloat)width;

@end
