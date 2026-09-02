#import <UIKit/UIKit.h>

// A stream descriptor for audio or subtitle tracks parsed from Emby
// MediaSources → MediaStreams.
@interface OEStreamInfo : NSObject
@property (nonatomic, copy) NSString *index;      // Stream Index (NSString for table cell reuse convenience)
@property (nonatomic, copy) NSString *title;      // Display title
@property (nonatomic, copy) NSString *language;    // Language code
@property (nonatomic, copy) NSString *codec;       // Codec (e.g. "aac", "srt")
@property (nonatomic, assign) BOOL isDefault;
@property (nonatomic, assign) BOOL isExternal;   // External subtitle (has DeliveryUrl or IsExternal)
@property (nonatomic, copy) NSString *deliveryUrl; // Subtitle delivery URL if external
@property (nonatomic, copy) NSString *mediaSourceId; // MediaSource Id for subtitle fetch
@end

// A bottom-sheet style picker for selecting audio tracks and subtitles.
// Designed for iOS 6: pure frame layout, no Auto Layout or UICollectionView.
// Presented as a modal view on top of the movie player view.
@protocol OEStreamSelectionDelegate;

@interface OEStreamSelectionView : UIView

// Initialize with audio streams and subtitle streams parsed from MediaSources.
- (instancetype)initWithFrame:(CGRect)frame
                   audioStreams:(NSArray *)audioStreams
                subtitleStreams:(NSArray *)subtitleStreams
             selectedAudioIndex:(NSInteger)audioIndex
          selectedSubtitleIndex:(NSInteger)subtitleIndex
                    delegate:(id<OEStreamSelectionDelegate>)delegate;

// Show/hide with animation.
- (void)showInWindow:(UIWindow *)window;
- (void)dismiss;

@end

@protocol OEStreamSelectionDelegate <NSObject>
@optional
- (void)streamSelectionView:(OEStreamSelectionView *)view
         didSelectAudioIndex:(NSInteger)audioIndex;
- (void)streamSelectionView:(OEStreamSelectionView *)view
      didSelectSubtitleIndex:(NSInteger)subtitleIndex;
- (void)streamSelectionViewDidDismiss:(OEStreamSelectionView *)view;
@end
