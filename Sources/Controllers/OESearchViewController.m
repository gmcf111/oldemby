#import "OESearchViewController.h"
#import "Constants.h"
#import "Views/OEItemCell.h"
#import "Views/OETheme.h"
#import "Views/OEErrorAlertView.h"
#import "Services/OEEmbyAPIClient.h"
#import "Services/OEMusicPlaybackManager.h"
#import "Models/OEEmbyItem.h"
#import "Controllers/OEVideoDetailViewController.h"
#import "Controllers/OESeasonListViewController.h"
#import "Controllers/OEMusicLibraryViewController.h"
#import "Controllers/OEMusicPlayerViewController.h"
#import "Controllers/OELoginViewController.h"

static NSInteger const kOESearchPageSize = 60;
static CGFloat const kOESearchBarHeight = 44.0;
static CGFloat const kOEScopeHeight = 44.0;
static NSInteger const kOESearchEmptyLabelTag = 997;

@interface OESearchViewController ()
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, assign) OESearchScope scope;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, assign) NSInteger pageStart;
@property (nonatomic, assign) BOOL loadingPage;
@property (nonatomic, assign) BOOL hasMorePages;
@property (nonatomic, assign) BOOL hasSearched;
@end

@implementation OESearchViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [OETheme prepareViewController:self];
    self.title = @"搜索";
    self.scope = OESearchScopeVideo;
    self.items = @[];
    self.hasMorePages = YES;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"登录"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(showLogin)];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索影视或音乐";
    if ([self.searchBar respondsToSelector:@selector(setReturnKeyType:)]) {
        self.searchBar.returnKeyType = UIReturnKeySearch;
    }
    [self.view addSubview:self.searchBar];

    self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[@"影视", @"音乐"]];
    self.scopeControl.selectedSegmentIndex = self.scope;
    self.scopeControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scopeControl addTarget:self action:@selector(scopeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.scopeControl];

    // Grouped style gives the Cydia look: inset rounded rows below a fixed
    // search field instead of a full-bleed plain list.
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    [self applyTheme];
    [self applyRowHeightForScope];
    [self updatePlaceholder];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyThemeAndReload) name:kNotificationThemeDidChange object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resetForAccountChange) name:@"OEDidLoginNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resetForAccountChange) name:@"OEDidLogoutNotification" object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    // Cydia-style header: the field is inset from the screen edges and floats
    // above the grouped list, not edge-to-edge under the navigation bar.
    self.searchBar.frame = CGRectMake(7, 7, w - 14, kOESearchBarHeight);
    self.scopeControl.frame = CGRectMake(13, kOESearchBarHeight + 11, w - 26, 30);
    CGFloat tableTop = kOESearchBarHeight + kOEScopeHeight + 6;
    self.tableView.frame = CGRectMake(0, tableTop, w, MAX(0, h - tableTop));
    [self positionPlaceholder];
}

// The placeholder is created before the first layout pass, so its width has
// to be refreshed here or it stays at the initial (possibly zero) width.
- (void)positionPlaceholder {
    UIView *placeholder = [self.tableView viewWithTag:kOESearchEmptyLabelTag];
    if (!placeholder) return;
    CGRect frame = placeholder.frame;
    frame.origin.x = 0;
    frame.origin.y = 40;
    frame.size.width = self.tableView.bounds.size.width;
    placeholder.frame = frame;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

#pragma mark - Theme

- (void)applyTheme {
    self.view.backgroundColor = [OETheme libraryBackgroundColor];
    self.tableView.backgroundColor = [OETheme libraryBackgroundColor];
    self.tableView.separatorColor = [OETheme separatorColor];
    // Neutral grays, never the Emby green: the scope control's selected
    // segment and the search field's cursor / clear / cancel buttons all
    // follow tintColor, which used to paint two green accents next to the
    // field.
    UIColor *neutralTint = [OETheme isLight] ? [UIColor colorWithWhite:0.35 alpha:1.0]
                                             : [UIColor colorWithWhite:0.85 alpha:1.0];
    self.scopeControl.tintColor = neutralTint;
    if ([self.searchBar respondsToSelector:@selector(setBarTintColor:)]) {
        // iOS 7+: barTintColor paints the bar behind the (light) field.
        self.searchBar.barTintColor = [OETheme navigationBarColor];
        self.searchBar.tintColor = neutralTint;
    } else {
        // iOS 6: tintColor paints the field itself; a near-white value keeps
        // Cydia's light rounded field on the dark header.
        self.searchBar.tintColor = [UIColor colorWithWhite:0.97 alpha:1.0];
    }
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)applyThemeAndReload {
    [self applyTheme];
    [self.tableView reloadData];
}

#pragma mark - Scope

// The scope is the only thing that decides which half of the library is
// queried: Emby filters server-side via IncludeItemTypes, so video search can
// never return a song and vice versa.
- (NSString *)itemTypesForScope:(OESearchScope)scope {
    return scope == OESearchScopeMusic ? @"Audio,MusicAlbum,MusicArtist" : @"Movie,Series,Episode";
}

- (void)applyRowHeightForScope {
    self.tableView.rowHeight = self.scope == OESearchScopeMusic ? 60 : 100;
}

- (void)scopeChanged:(UISegmentedControl *)control {
    self.scope = (OESearchScope)control.selectedSegmentIndex;
    [self applyRowHeightForScope];
    self.searchBar.placeholder = self.scope == OESearchScopeMusic ? @"搜索音乐" : @"搜索影视";
    [self runSearch];
}

#pragma mark - Searching

- (NSString *)currentTerm {
    return [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    // Debounce: every keystroke would otherwise fire a request.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    [self performSelector:@selector(runSearch) withObject:nil afterDelay:0.35];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [searchBar setShowsCancelButton:NO animated:YES];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    [self runSearch];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    searchBar.text = nil;
    [searchBar resignFirstResponder];
    [searchBar setShowsCancelButton:NO animated:YES];
    self.items = @[];
    self.hasSearched = NO;
    [self.tableView reloadData];
    [self updatePlaceholder];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self.searchBar resignFirstResponder];
}

- (void)runSearch {
    NSString *term = [self currentTerm];
    ++self.loadGeneration;
    self.pageStart = 0;
    self.hasMorePages = YES;
    self.hasSearched = term.length > 0;
    if (!term.length) {
        self.items = @[];
        [self.tableView reloadData];
        [self updatePlaceholder];
        return;
    }
    [self loadPageAtStart:0 reset:YES];
}

- (void)loadPageAtStart:(NSInteger)start reset:(BOOL)reset {
    NSString *term = [self currentTerm];
    if (!term.length) return;
    if (!reset && (self.loadingPage || !self.hasMorePages)) return;
    NSUInteger generation = ++self.loadGeneration;
    self.loadingPage = YES;
    if (reset) {
        self.title = @"搜索中…";
        [self updatePlaceholder];
    }
    __weak OESearchViewController *weakSelf = self;
    [[OEEmbyAPIClient sharedClient] searchItemsWithTerm:term
                                             itemTypes:[self itemTypesForScope:self.scope]
                                            startIndex:start
                                                 limit:kOESearchPageSize
                                           completion:^(id result, NSError *error) {
        OESearchViewController *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.loadGeneration) return;
        strongSelf.loadingPage = NO;
        strongSelf.title = @"搜索";
        if (error) {
            if (error.code != -1 || ![error.domain isEqualToString:@"OEEmbyAPI"]) {
                [OEErrorAlertView showWithTitle:@"搜索失败" error:error];
            }
            [strongSelf updatePlaceholder];
            return;
        }
        NSArray *page = [result isKindOfClass:[NSArray class]] ? result : @[];
        strongSelf.items = reset ? page : [strongSelf.items arrayByAddingObjectsFromArray:page];
        strongSelf.pageStart = start + page.count;
        strongSelf.hasMorePages = ((NSInteger)page.count == kOESearchPageSize);
        [strongSelf.tableView reloadData];
        [strongSelf updatePlaceholder];
    }];
}

- (void)resetForAccountChange {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    ++self.loadGeneration;
    self.items = @[];
    self.hasSearched = NO;
    self.loadingPage = NO;
    self.hasMorePages = YES;
    self.pageStart = 0;
    [self.tableView reloadData];
    [self updatePlaceholder];
}

- (void)showLogin {
    OELoginViewController *vc = [[OELoginViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Placeholder

- (void)updatePlaceholder {
    [[self.tableView viewWithTag:kOESearchEmptyLabelTag] removeFromSuperview];
    if (self.items.count) return;
    NSString *text;
    if (!self.hasSearched) {
        text = self.scope == OESearchScopeMusic ? @"输入关键词搜索音乐" : @"输入关键词搜索电影与剧集";
    } else if (self.loadingPage) {
        return;
    } else {
        text = @"没有找到匹配的内容";
    }
    UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, self.tableView.bounds.size.width, 40)];
    empty.text = text;
    empty.tag = kOESearchEmptyLabelTag;
    empty.textAlignment = NSTextAlignmentCenter;
    empty.textColor = [OETheme secondaryTextColor];
    empty.backgroundColor = [UIColor clearColor];
    empty.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.tableView addSubview:empty];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

// Cydia-style section caption: scope name plus the hit count.
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (!self.items.count) return nil;
    NSString *name = self.scope == OESearchScopeMusic ? @"音乐" : @"影视";
    return [NSString stringWithFormat:@"%@ (%d)", name, (int)self.items.count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL music = self.scope == OESearchScopeMusic;
    NSString *ID = music ? @"OESearchMusicCell" : @"OESearchVideoCell";
    OEItemCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) {
        cell = [[OEItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    OEEmbyItem *item = self.items[indexPath.row];
    cell.compactLayout = music;
    [cell configureWithItem:item];
    cell.detailLabel.numberOfLines = music ? 1 : 2;
    cell.detailLabel.text = [self subtitleForItem:item];
    return cell;
}

- (NSString *)subtitleForItem:(OEEmbyItem *)item {
    NSString *kind;
    switch (item.itemType) {
        case OEEmbyItemTypeMovie:   kind = @"电影"; break;
        case OEEmbyItemTypeSeries:  kind = @"剧集"; break;
        case OEEmbyItemTypeSeason:  kind = @"季";   break;
        case OEEmbyItemTypeEpisode: kind = @"单集"; break;
        case OEEmbyItemTypeAudio:   kind = @"歌曲"; break;
        case OEEmbyItemTypeAlbum:   kind = @"专辑"; break;
        case OEEmbyItemTypeArtist:  kind = @"歌手"; break;
        default:                    kind = item.type.length ? item.type : @"媒体"; break;
    }
    NSString *duration = [item displayDuration];
    if (duration.length) return [NSString stringWithFormat:@"%@  %@", kind, duration];
    if (item.itemType == OEEmbyItemTypeEpisode && item.seriesName.length) {
        return [NSString stringWithFormat:@"%@  %@", kind, item.seriesName];
    }
    return kind;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == (NSInteger)self.items.count - 1 && !self.loadingPage && self.hasMorePages) {
        [self loadPageAtStart:self.pageStart reset:NO];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.searchBar resignFirstResponder];
    OEEmbyItem *item = self.items[indexPath.row];
    if (self.scope == OESearchScopeMusic) {
        [self openMusicItem:item];
    } else {
        [self openVideoItem:item];
    }
}

#pragma mark - Result routing

- (void)openVideoItem:(OEEmbyItem *)item {
    UIViewController *next = nil;
    if (item.itemType == OEEmbyItemTypeSeries) {
        // Series have no playable source of their own: drill into seasons
        // exactly like the poster wall does.
        next = [[OESeasonListViewController alloc] initWithSeries:item];
    } else {
        next = [[OEVideoDetailViewController alloc] initWithItem:item];
    }
    [self.navigationController pushViewController:next animated:YES];
}

- (void)openMusicItem:(OEEmbyItem *)item {
    if (item.itemType == OEEmbyItemTypeAudio) {
        // Keep the queue inside the search result set so prev/next stay in scope.
        NSMutableArray *tracks = [NSMutableArray array];
        for (OEEmbyItem *candidate in self.items) {
            if (candidate.itemType == OEEmbyItemTypeAudio) [tracks addObject:candidate];
        }
        if (!tracks.count) [tracks addObject:item];
        [[OEMusicPlaybackManager sharedManager] playItem:item playlist:tracks];
        [self presentFullPlayer];
        return;
    }
    // Albums and artists behave like the music library drill-down.
    OEMusicLibraryViewController *library = [[OEMusicLibraryViewController alloc] initWithParentId:item.itemId
                                                                                           title:item.name
                                                                                        itemType:item.itemType];
    [self.navigationController pushViewController:library animated:YES];
}

// The mini player only lives on the music tab, so playing from search opens
// the full player directly instead of leaving no visible feedback.
- (void)presentFullPlayer {
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    if (!manager.currentItem) return;
    if ([self.presentedViewController isKindOfClass:[OEMusicPlayerViewController class]]) return;
    OEMusicPlayerViewController *player = [[OEMusicPlayerViewController alloc] initWithItem:manager.currentItem
                                                                                 playlist:manager.playlist];
    player.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    [self presentViewController:player animated:YES completion:nil];
}

@end
