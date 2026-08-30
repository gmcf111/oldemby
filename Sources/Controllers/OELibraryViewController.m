#import "OELibraryViewController.h"
#import "Views/OEItemCell.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Controllers/OEVideoDetailViewController.h"
#import "Controllers/OEEpisodeListViewController.h"
#import "Controllers/OEMusicLibraryViewController.h"
#import "Controllers/OEMusicPlayerViewController.h"
#import "Controllers/OELoginViewController.h"

@interface OELibraryViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *items; // OEEmbyItem
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, copy) NSString *currentParentId;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, assign) NSInteger pageStart;
@property (nonatomic, assign) NSInteger pageSize;
@property (nonatomic, assign) BOOL loadingPage;
@property (nonatomic, assign) BOOL hasMorePages;
@property (nonatomic, copy) NSString *listTitle;
@end

@implementation OELibraryViewController

- (instancetype)initWithParentId:(NSString *)parentId title:(NSString *)title {
    if ((self = [super init])) {
        _currentParentId = [parentId copy];
        _listTitle = [title copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.listTitle ?: @"媒体库";
    self.view.backgroundColor = [UIColor whiteColor];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"登录" style:UIBarButtonItemStylePlain target:self action:@selector(showLogin)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    if (!self.currentParentId) {
        // Segment for filter - pure code
        self.seg = [[UISegmentedControl alloc] initWithItems:@[@"全部", @"电影", @"剧集"]];
        self.seg.selectedSegmentIndex = 0;
        [self.seg addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
        self.seg.frame = CGRectMake(10, 68, self.view.bounds.size.width-20, 30);
        self.seg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self.view addSubview:self.seg];
    }

    CGFloat tabH = 49;
    CGFloat navH = 44 + 20;
    CGFloat segH = self.currentParentId ? 0 : 40;
    CGRect tableFrame = CGRectMake(0, navH + segH, self.view.bounds.size.width, self.view.bounds.size.height - navH - segH - tabH);
    self.tableView = [[UITableView alloc] initWithFrame:tableFrame style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 102;
    [self.view addSubview:self.tableView];
    self.pageSize = 50;
    self.hasMorePages = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLoginNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLogoutNotification" object:nil];
    [self loadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Keep manual frame correct on rotation (iOS6 manual layout)
    CGFloat navH = self.navigationController.navigationBar.frame.size.height + 20;
    CGFloat segH = self.currentParentId ? 0 : 40;
    if (self.seg) self.seg.frame = CGRectMake(10, navH + 4, self.view.bounds.size.width-20, 30);
    self.tableView.frame = CGRectMake(0, navH + segH, self.view.bounds.size.width, self.view.bounds.size.height - navH - segH - self.tabBarController.tabBar.frame.size.height);
}

- (void)segChanged { [self loadData]; }

- (void)showLogin {
    OELoginViewController *vc = [[OELoginViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)loadData {
    ++self.loadGeneration; // invalidate any in-flight page from the previous filter
    self.pageStart = 0;
    self.hasMorePages = YES;
    self.items = @[];
    [self loadPageAtStart:0 reset:YES];
}

- (void)loadPageAtStart:(NSInteger)start reset:(BOOL)reset {
    if ((!reset && self.loadingPage) || (!reset && !self.hasMorePages)) return;
    NSUInteger generation = ++self.loadGeneration;
    self.loadingPage = YES;
    NSString *types = nil;
    switch (self.seg.selectedSegmentIndex) {
        case 1: types = @"Movie"; break;
        case 2: types = @"Series"; break;
        default: types = @"Folder,CollectionFolder,Movie,Series,Video"; break;
    }
    // Show HUD-like
    self.title = @"加载中...";
    // The unfiltered root is the library-view level; recurse only for the
    // explicit Movie/TV filters.  Folder drill-down must stay direct-child.
    BOOL recursive = self.currentParentId ? NO : (self.seg.selectedSegmentIndex != 0);
    [[OEEmbyAPIClient sharedClient] fetchItemsInParent:self.currentParentId itemTypes:types startIndex:start limit:self.pageSize sortBy:@"SortName" recursive:recursive completion:^(id result, NSError *error){
        if (generation != self.loadGeneration) return;
        self.loadingPage = NO;
        self.title = self.listTitle ?: @"媒体库";
        if (error) {
            NSLog(@"[OldEmby] fetch error %@", error);
            // Don't pop alert for expected "Not logged in" state (e.g. app launch before login modal)
            if (error.code != -1 || ![error.domain isEqualToString:@"OEEmbyAPI"]) {
                UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"加载失败" message:error.localizedDescription delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
                [av show];
            }
            return;
        }
        NSArray *page = [result isKindOfClass:[NSArray class]] ? result : @[];
        self.items = reset ? page : [self.items arrayByAddingObjectsFromArray:page];
        self.pageStart = start + page.count;
        self.hasMorePages = (page.count == self.pageSize);
        [self.tableView reloadData];
        [[self.tableView viewWithTag:999] removeFromSuperview];
        if (self.items.count==0) {
            UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
            empty.text = @"暂无内容，请检查服务器或登录";
            empty.textAlignment = NSTextAlignmentCenter;
            empty.tag = 999;
            empty.textColor = [UIColor grayColor];
            [self.tableView addSubview:empty];
        }
    }];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == self.items.count - 1 && !self.loadingPage && self.hasMorePages) {
        [self loadPageAtStart:self.pageStart reset:NO];
    }
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"OEItemCell";
    OEItemCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) cell = [[OEItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
    OEEmbyItem *it = self.items[indexPath.row];
    [cell configureWithItem:it];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    OEEmbyItem *it = self.items[indexPath.row];
    if (it.itemType == OEEmbyItemTypeFolder) {
        OELibraryViewController *vc = [[OELibraryViewController alloc] initWithParentId:it.itemId title:it.name];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    if (it.itemType == OEEmbyItemTypeSeries) {
        OEEpisodeListViewController *vc = [[OEEpisodeListViewController alloc] initWithSeries:it];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    if (it.itemType == OEEmbyItemTypeAudio) {
        OEMusicPlayerViewController *vc = [[OEMusicPlayerViewController alloc] initWithItem:it playlist:self.items];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    if (it.itemType == OEEmbyItemTypeAlbum || it.itemType == OEEmbyItemTypeArtist) {
        OEMusicLibraryViewController *vc = [[OEMusicLibraryViewController alloc] initWithParentId:it.itemId title:it.name itemType:it.itemType];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    OEVideoDetailViewController *vc = [[OEVideoDetailViewController alloc] initWithItem:it];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
