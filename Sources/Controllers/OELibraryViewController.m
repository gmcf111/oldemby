#import "OELibraryViewController.h"
#import "Views/OEItemCell.h"
#import "Views/OETheme.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Controllers/OEVideoDetailViewController.h"
#import "Controllers/OEEpisodeListViewController.h"
#import "Controllers/OELoginViewController.h"

@interface OELibraryViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *items;
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
    [OETheme prepareViewController:self];
    self.title = self.listTitle ?: @"影视";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"登录" style:UIBarButtonItemStylePlain target:self action:@selector(showLogin)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [OETheme libraryBackgroundColor];
    self.tableView.separatorColor = [OETheme separatorColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 112;
    [self.view addSubview:self.tableView];
    self.pageSize = 50;
    self.hasMorePages = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLoginNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLogoutNotification" object:nil];
    [self loadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.tableView.frame = self.view.bounds;
}

- (void)showLogin {
    OELoginViewController *vc = [[OELoginViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
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
    NSString *types = self.currentParentId ? @"Folder,CollectionFolder,Movie,Series,Video" : @"Folder,CollectionFolder,Movie,Series,Video";
    self.title = @"加载中…";
    BOOL recursive = self.currentParentId ? NO : YES;
    [[OEEmbyAPIClient sharedClient] fetchItemsInParent:self.currentParentId itemTypes:types startIndex:start limit:self.pageSize sortBy:@"SortName" recursive:recursive completion:^(id result, NSError *error) {
        if (generation != self.loadGeneration) return;
        self.loadingPage = NO;
        self.title = self.listTitle ?: @"影视";
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
        [[self.tableView viewWithTag:999] removeFromSuperview];
        if (!self.items.count) [self showEmptyState];
    }];
}

- (void)showEmptyState {
    UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
    empty.text = @"暂无影视内容，请检查服务器或登录";
    empty.textAlignment = NSTextAlignmentCenter;
    empty.tag = 999;
    empty.textColor = [OETheme secondaryTextColor];
    empty.backgroundColor = [UIColor clearColor];
    [self.tableView addSubview:empty];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == self.items.count - 1 && !self.loadingPage && self.hasMorePages) [self loadPageAtStart:self.pageStart reset:NO];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"OEVideoItemCell";
    OEItemCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) cell = [[OEItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
    cell.compactLayout = NO;
    [cell configureWithItem:self.items[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    OEEmbyItem *item = self.items[indexPath.row];
    if (item.itemType == OEEmbyItemTypeFolder) {
        [self.navigationController pushViewController:[[OELibraryViewController alloc] initWithParentId:item.itemId title:item.name] animated:YES];
    } else if (item.itemType == OEEmbyItemTypeSeries) {
        [self.navigationController pushViewController:[[OEEpisodeListViewController alloc] initWithSeries:item] animated:YES];
    } else {
        [self.navigationController pushViewController:[[OEVideoDetailViewController alloc] initWithItem:item] animated:YES];
    }
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
