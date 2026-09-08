#import <UIKit/UIKit.h>

// Top-level search tab. It sits beside 影视 / 音乐 / 设置 in the root tab bar:
// each of those owns its own navigation stack, and so does search — the page
// is never pushed from another module and never contains one.
//
// The scope control picks which Emby item types are queried:
//   OESearchScopeVideo -> Movie, Series, Episode
//   OESearchScopeMusic -> Audio, MusicAlbum, MusicArtist
typedef NS_ENUM(NSInteger, OESearchScope) {
    OESearchScopeVideo = 0,
    OESearchScopeMusic = 1
};

@interface OESearchViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>

@end
