#import "OEMusicLibraryViewController.h"
#import "Views/OEItemCell.h"
#import "Views/OETheme.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Controllers/OEMusicPlayerViewController.h"
#import "Services/OEMusicPlaybackManager.h"

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

- (void)viewDidLoad {
    [super viewDidLoad];
    [OETheme prepareViewController:self];
    self.title = self.parentId ? (self.listTitle ?: @"歌曲") : @"音乐";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [OETheme libraryBackgroundColor];
    self.tableView.separatorColor = [OETheme separatorColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 60;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 54, 0);
    [self.view addSubview:self.tableView];
    self.pageSize = 200;
    self.hasMorePages = YES;

    [self loadData];
    if (!self.parentId) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLoginNotification" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLogoutNotification" object:nil];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.tableView.frame = self.view.bounds;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationMusicFullPlayerVisibilityChanged object:self];
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
    NSString *types = self.parentId ? @"Audio" : @"Audio";
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
    } else {
        [api fetchItemsInParent:self.parentId itemTypes:types startIndex:start limit:self.pageSize sortBy:@"Album,ParentIndexNumber,IndexNumber" recursive:(self.parentId ? NO : YES) completion:handler];
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
    cell.detailLabel.text = [NSString stringWithFormat:@"%@ · %@", item.artist ?: @"未知歌手", item.album ?: @""];
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
