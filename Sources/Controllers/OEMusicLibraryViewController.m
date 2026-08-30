#import "OEMusicLibraryViewController.h"
#import "Views/OEItemCell.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Controllers/OEMusicPlayerViewController.h"

@interface OEMusicLibraryViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, copy) NSString *parentId;   // nil = root music library
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
    self.title = self.parentId ? (self.listTitle ?: @"歌曲") : @"音乐";
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    if (!self.parentId) {
        self.seg = [[UISegmentedControl alloc] initWithItems:@[@"歌曲", @"专辑", @"歌手"]];
        self.seg.selectedSegmentIndex = 0;
        [self.seg addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
        self.seg.frame = CGRectMake(10, 68, self.view.bounds.size.width-20, 30);
        self.seg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self.view addSubview:self.seg];
    }

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 60;
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
    CGFloat navH = self.navigationController.navigationBar.frame.size.height + 20;
    CGFloat tabH = self.tabBarController.tabBar.frame.size.height;
    if (self.parentId) {
        self.tableView.frame = CGRectMake(0, navH, self.view.bounds.size.width, self.view.bounds.size.height - navH - tabH);
    } else {
        self.seg.frame = CGRectMake(10, navH+4, self.view.bounds.size.width-20, 30);
        self.tableView.frame = CGRectMake(0, navH+40, self.view.bounds.size.width, self.view.bounds.size.height - navH - 40 - tabH);
    }
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
    if (self.parentId) {
        types = @"Audio"; // drill-down: songs of this album/artist
    } else {
        switch (self.seg.selectedSegmentIndex) {
            case 0: types = @"Audio"; break;
            case 1: types = @"MusicAlbum"; break;
            case 2: types = @"MusicArtist"; break;
            default: types = @"Audio"; break;
        }
    }
    NSString *resetTitle = self.parentId ? (self.listTitle ?: @"歌曲") : @"音乐";
    self.title = @"加载中...";
    OEAPICompletion handler = ^(id result, NSError *error){
        if (generation != self.loadGeneration) return;
        self.loadingPage = NO;
        self.title = resetTitle;
        if (error) {
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
        [[self.tableView viewWithTag:998] removeFromSuperview];
        if (self.items.count==0) {
            UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
            empty.text = @"暂无音乐，请检查音乐库";
            empty.tag = 998;
            empty.textAlignment = NSTextAlignmentCenter;
            empty.textColor = [UIColor grayColor];
            [self.tableView addSubview:empty];
        }
    };
    OEEmbyAPIClient *api = [OEEmbyAPIClient sharedClient];
    if (self.parentId && self.parentItemType == OEEmbyItemTypeArtist) {
        // Artists are virtual nodes: ParentId returns nothing, filter by ArtistIds instead
        [api fetchSongsForArtist:self.parentId startIndex:start limit:self.pageSize completion:handler];
    } else if (self.parentId) {
        // Album: order by disc/track number, not alphabetically
        [api fetchItemsInParent:self.parentId itemTypes:types startIndex:start limit:self.pageSize sortBy:@"ParentIndexNumber,IndexNumber" completion:handler];
    } else {
        [api fetchItemsInParent:nil itemTypes:types startIndex:start limit:self.pageSize sortBy:(self.seg.selectedSegmentIndex == 0 ? @"Album,ParentIndexNumber,IndexNumber" : @"SortName") completion:handler];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == self.items.count - 1 && !self.loadingPage && self.hasMorePages) {
        [self loadPageAtStart:self.pageStart reset:NO];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"MusicCell";
    OEItemCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) cell = [[OEItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
    cell.compactLayout = YES; // rowHeight is 60 here
    OEEmbyItem *it = self.items[indexPath.row];
    [cell configureWithItem:it];
    // Show album/artist for audio
    if (it.itemType == OEEmbyItemTypeAudio) {
        cell.detailLabel.text = [NSString stringWithFormat:@"%@ - %@", it.artist ?: @"未知歌手", it.album ?: @""];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    OEEmbyItem *it = self.items[indexPath.row];
    if (it.itemType == OEEmbyItemTypeAudio) {
        OEMusicPlayerViewController *vc = [[OEMusicPlayerViewController alloc] initWithItem:it playlist:self.items];
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        // Album/Artist: drill down into its songs
        OEMusicLibraryViewController *vc = [[OEMusicLibraryViewController alloc] initWithParentId:it.itemId title:it.name itemType:it.itemType];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
