#import "OEMusicLibraryViewController.h"
#import "Constants.h"
#import "Views/OEItemCell.h"
#import "Views/OETheme.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Controllers/OEMusicPlayerViewController.h"
#import "Services/OEMusicPlaybackManager.h"

typedef NS_ENUM(NSInteger, OEMusicFilterMode) {
    OEMusicFilterSongs = 0,
    OEMusicFilterAlbums = 1,
    OEMusicFilterArtists = 2
};

typedef NS_ENUM(NSInteger, OEMusicSortMode) {
    OEMusicSortByName = 0,
    OEMusicSortNewest = 1,
    OEMusicSortOldest = 2
};

@interface OEMusicLibraryViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, copy) NSString *parentId;
@property (nonatomic, copy) NSString *listTitle;
@property (nonatomic, assign) OEEmbyItemType parentItemType;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, assign) NSInteger pageStart;
@property (nonatomic, assign) NSInteger pageSize;
@property (nonatomic, assign) BOOL loadingPage;
@property (nonatomic, assign) BOOL hasMorePages;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UISegmentedControl *sortControl;
@property (nonatomic, assign) OEMusicFilterMode filterMode;
@property (nonatomic, assign) OEMusicSortMode sortMode;
@end

@implementation OEMusicLibraryViewController

- (instancetype)initWithParentId:(NSString *)parentId title:(NSString *)title itemType:(OEEmbyItemType)itemType {
    if ((self = [super init])) {
        _parentId = [parentId copy];
        _listTitle = [title copy];
        _parentItemType = itemType;
    }
    return self;
}

- (BOOL)isRoot { return self.parentId == nil; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [OETheme prepareViewController:self];
    self.title = self.parentId ? (self.listTitle ?: @"歌曲") : @"音乐";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 60;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 54, 0);
    [self applyTheme];
    [self.view addSubview:self.tableView];
    self.pageSize = 200;
    self.hasMorePages = YES;

    if ([self isRoot]) [self buildFilterHeader];

    [self loadData];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyThemeAndReload) name:kNotificationThemeDidChange object:nil];
    if (!self.parentId) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLoginNotification" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLogoutNotification" object:nil];
    }
}

- (void)buildFilterHeader {
    CGFloat w = self.view.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 90)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"全部歌曲", @"全部专辑", @"全部歌手"]];
    self.filterControl.frame = CGRectMake(12, 10, w - 24, 30);
    self.filterControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.filterControl.selectedSegmentIndex = self.filterMode;
    self.filterControl.tintColor = [OETheme accentColor];
    [self.filterControl addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [header addSubview:self.filterControl];

    self.sortControl = [[UISegmentedControl alloc] initWithItems:@[@"按首字母", @"最新加入", @"最早加入"]];
    self.sortControl.frame = CGRectMake(12, 48, w - 24, 30);
    self.sortControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.sortControl.selectedSegmentIndex = self.sortMode;
    self.sortControl.tintColor = [OETheme accentColor];
    [self.sortControl addTarget:self action:@selector(sortChanged:) forControlEvents:UIControlEventValueChanged];
    [header addSubview:self.sortControl];

    self.tableView.tableHeaderView = header;
}

- (void)filterChanged:(UISegmentedControl *)control {
    self.filterMode = (OEMusicFilterMode)control.selectedSegmentIndex;
    [self loadData];
}

- (void)sortChanged:(UISegmentedControl *)control {
    self.sortMode = (OEMusicSortMode)control.selectedSegmentIndex;
    [self loadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.tableView.frame = self.view.bounds;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationMusicFullPlayerVisibilityChanged object:self];
}

- (void)applyTheme {
    self.view.backgroundColor = [OETheme libraryBackgroundColor];
    self.tableView.backgroundColor = [OETheme libraryBackgroundColor];
    self.tableView.separatorColor = [OETheme separatorColor];
    self.tableView.tableHeaderView.backgroundColor = [OETheme libraryBackgroundColor];
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)applyThemeAndReload {
    [self applyTheme];
    [self.tableView reloadData];
}

- (NSString *)rootItemTypes {
    switch (self.filterMode) {
        case OEMusicFilterAlbums: return @"MusicAlbum";
        case OEMusicFilterArtists: return @"MusicArtist";
        default: return @"Audio";
    }
}

- (NSString *)sortByForCurrentMode {
    return self.sortMode == OEMusicSortByName ? @"SortName" : @"DateCreated";
}

- (NSString *)sortOrderForCurrentMode {
    return self.sortMode == OEMusicSortNewest ? @"Descending" : @"Ascending";
}

- (void)loadData {
    ++self.loadGeneration;
    self.pageStart = 0;
    self.hasMorePages = YES;
    self.items = @[];
    [self loadPageAtStart:0 reset:YES];
}

- (void)loadPageAtStart:(NSInteger)start reset:(BOOL)reset {
    if ((!reset && self.loadingPage) || (!reset && !self.hasMorePages)) return;
    NSUInteger generation = ++self.loadGeneration;
    self.loadingPage = YES;
    NSString *title = self.parentId ? (self.listTitle ?: @"歌曲") : @"音乐";
    self.title = @"加载中…";
    OEAPICompletion handler = ^(id result, NSError *error) {
        if (generation != self.loadGeneration) return;
        self.loadingPage = NO;
        self.title = title;
        if (error) {
            if (error.code != -1 || ![error.domain isEqualToString:@"OEEmbyAPI"]) {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"加载失败" message:error.localizedDescription delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
                [alert show];
            }
            return;
        }
        NSArray *page = [result isKindOfClass:[NSArray class]] ? result : @[];
        self.items = reset ? page : [self.items arrayByAddingObjectsFromArray:page];
        self.pageStart = start + page.count;
        self.hasMorePages = page.count == self.pageSize;
        [self.tableView reloadData];
        [[self.tableView viewWithTag:998] removeFromSuperview];
        if (!self.items.count) [self showEmptyState];
    };
    OEEmbyAPIClient *api = [OEEmbyAPIClient sharedClient];
    if (self.parentId && self.parentItemType == OEEmbyItemTypeArtist) {
        [api fetchSongsForArtist:self.parentId startIndex:start limit:self.pageSize completion:handler];
    } else if (self.parentId) {
        // Songs inside an album folder, in track order.
        [api fetchItemsInParent:self.parentId itemTypes:@"Audio" startIndex:start limit:self.pageSize sortBy:@"Album,ParentIndexNumber,IndexNumber" recursive:NO completion:handler];
    } else {
        // Root: filtered by 歌曲/专辑/歌手 with the chosen sort.
        [api fetchItemsInParent:nil itemTypes:[self rootItemTypes] startIndex:start limit:self.pageSize sortBy:[self sortByForCurrentMode] sortOrder:[self sortOrderForCurrentMode] recursive:YES completion:handler];
    }
}

- (void)showEmptyState {
    UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
    empty.text = @"暂无音乐，请检查音乐库";
    empty.tag = 998;
    empty.textAlignment = NSTextAlignmentCenter;
    empty.textColor = [OETheme secondaryTextColor];
    empty.backgroundColor = [UIColor clearColor];
    [self.tableView addSubview:empty];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == self.items.count - 1 && !self.loadingPage && self.hasMorePages) [self loadPageAtStart:self.pageStart reset:NO];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"MusicCell";
    OEItemCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) cell = [[OEItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
    cell.compactLayout = YES;
    OEEmbyItem *item = self.items[indexPath.row];
    [cell configureWithItem:item];
    if (item.itemType == OEEmbyItemTypeAudio) {
        cell.detailLabel.text = [NSString stringWithFormat:@"%@ · %@", item.artist ?: @"未知歌手", item.album ?: @""];
    } else if (item.itemType == OEEmbyItemTypeAlbum) {
        cell.detailLabel.text = item.artist ?: @"专辑";
    } else if (item.itemType == OEEmbyItemTypeArtist) {
        cell.detailLabel.text = @"歌手";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    OEEmbyItem *item = self.items[indexPath.row];
    if (item.itemType == OEEmbyItemTypeAudio) {
        [[OEMusicPlaybackManager sharedManager] playItem:item playlist:self.items];
    } else {
        OEMusicLibraryViewController *library = [[OEMusicLibraryViewController alloc] initWithParentId:item.itemId title:item.name itemType:item.itemType];
        [self.navigationController pushViewController:library animated:YES];
    }
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
