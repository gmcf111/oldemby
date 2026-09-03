#import <UIKit/UIKit.h>
@class OEEmbyItem;

@interface OEVideoDetailViewController : UIViewController

- (instancetype)initWithItem:(OEEmbyItem *)item;

// Episodes of the same season in display order, plus this item's position in
// that list. Set by the episode list so the player control bar can offer
// previous/next-episode buttons; left nil for movies.
@property (nonatomic, strong) NSArray *episodeSiblings;
@property (nonatomic, assign) NSInteger episodeIndex;

@end
