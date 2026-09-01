#import "OELibraryViewController.h"
#import "Views/OETheme.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Controllers/OEPosterWallViewController.h"
#import "Controllers/OELoginViewController.h"
#import "Views/OEItemCell.h"
#import "Constants.h"

@interface OELibraryViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *libraries;
@property (nonatomic, assign) NSUInteger loadGeneration;
@end

@implementation OELibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [OETheme prepareViewController:self];
    self.title = @"影视";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"登录" style:UIBarButtonItemStylePlain target:self action:@selector(showLogin)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 106;
    [self applyTheme];
    [self.view addSubview:self.tableView];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLoginNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLogoutNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyThemeAndReload) name:kNotificationThemeDidChange object:nil];
    [self loadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.tableView.frame = self.view.bounds;
}

- (void)applyTheme {
    self.view.backgroundColor = [OETheme libraryBackgroundColor];
    self.tableView.backgroundColor = [OETheme libraryBackgroundColor];
    self.tableView.separatorColor = [OETheme separatorColor];
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)applyThemeAndReload {
    [self applyTheme];
    [self.tableView reloadData];
}

- (void)showLogin {
    OELoginViewController *vc = [[OELoginViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)loadData {
    NSUInteger generation = ++self.loadGeneration;
    self.title = @"加载中…";
    [[OEEmbyAPIClient sharedClient] fetchViewsWithCompletion:^(id result, NSError *error) {
        if (generation != self.loadGeneration) return;
        self.title = @"影视";
        if (error) {
            if (error.code != -1 || ![error.domain isEqualToString:@"OEEmbyAPI"]) {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"加载失败" message:error.localizedDescription delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
                [alert show];
            }
            return;
        }
        NSArray *views = [result isKindOfClass:[NSArray class]] ? result : @[];
        // Keep only movie/TV libraries; fall back to every folder view so a
        // server with unusual collection types still shows something.
        NSMutableArray *videoLibraries = [NSMutableArray array];
        NSMutableArray *allFolders = [NSMutableArray array];
        for (OEEmbyItem *item in views) {
            if (![item isKindOfClass:[OEEmbyItem class]] || item.itemType != OEEmbyItemTypeFolder) continue;
            [allFolders addObject:item];
            if ([item.collectionType isEqualToString:@"movies"] || [item.collectionType isEqualToString:@"tvshows"]) {
                [videoLibraries addObject:item];
            }
        }
        self.libraries = videoLibraries.count ? videoLibraries : allFolders;
        [self.tableView reloadData];
        [[self.tableView viewWithTag:999] removeFromSuperview];
        if (!self.libraries.count) [self showEmptyState];
    }];
}

- (void)showEmptyState {
    UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
    empty.text = @"暂无影视媒体库，请检查服务器或登录";
    empty.textAlignment = NSTextAlignmentCenter;
    empty.tag = 999;
    empty.textColor = [OETheme secondaryTextColor];
    empty.backgroundColor = [UIColor clearColor];
    [self.tableView addSubview:empty];
}

- (NSString *)subtitleForLibrary:(OEEmbyItem *)item {
    if ([item.collectionType isEqualToString:@"movies"]) return @"电影库";
    if ([item.collectionType isEqualToString:@"tvshows"]) return @"剧集库";
    return @"媒体库";
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.libraries.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"OELibraryCell";
    OEItemCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) {
        cell = [[OEItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.compactLayout = NO;
    OEEmbyItem *item = self.libraries[indexPath.row];
    [cell configureWithItem:item];
    cell.detailLabel.numberOfLines = 1;
    cell.detailLabel.text = [self subtitleForLibrary:item];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    OEEmbyItem *library = self.libraries[indexPath.row];
    [self.navigationController pushViewController:[[OEPosterWallViewController alloc] initWithLibrary:library] animated:YES];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
