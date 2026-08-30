#import <UIKit/UIKit.h>
#import "Models/OEEmbyItem.h"

@interface OEMusicLibraryViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

// Drill-down mode: list songs contained in an album/artist (parentId).
// itemType must be OEEmbyItemTypeAlbum or OEEmbyItemTypeArtist (artists need ArtistIds filtering).
- (instancetype)initWithParentId:(NSString *)parentId title:(NSString *)title itemType:(OEEmbyItemType)itemType;

@end
