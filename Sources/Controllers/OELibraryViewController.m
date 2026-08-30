#import "OELibraryViewController.h"
#import "Views/OEItemCell.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Controllers/OEVideoDetailViewController.h"
#import "Controllers/OEEpisodeListViewController.h"
#import "Controllers/OELoginViewController.h"

@interface OELibraryViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *items; // OEEmbyItem
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, copy) NSString *currentParentId;
@end

@implementation OELibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"媒体库";
    self.view.backgroundColor = [UIColor whiteColor];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"登录" style:UIBarButtonItemStylePlain target:self action:@selector(showLogin)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    // Segment for filter - pure code
    self.seg = [[UISegmentedControl alloc] initWithItems:@[@"全部", @"电影", @"剧集"]];
    self.seg.selectedSegmentIndex = 0;
    [self.seg addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
    self.seg.frame = CGRectMake(10, 68, self.view.bounds.size.width-20, 30);
    self.seg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.seg];

    CGFloat tabH = 49;
    CGFloat navH = 44 + 20;
    CGFloat segH = 40;
    CGRect tableFrame = CGRectMake(0, navH + segH, self.view.bounds.size.width, self.view.bounds.size.height - navH - segH - tabH);
    self.tableView = [[UITableView alloc] initWithFrame:tableFrame style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 102;
    [self.view addSubview:self.tableView];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLoginNotification" object:nil];
    [self loadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Keep manual frame correct on rotation (iOS6 manual layout)
    CGFloat navH = self.navigationController.navigationBar.frame.size.height + 20;
    CGFloat segH = 40;
    self.seg.frame = CGRectMake(10, navH + 4, self.view.bounds.size.width-20, 30);
    self.tableView.frame = CGRectMake(0, navH + segH, self.view.bounds.size.width, self.view.bounds.size.height - navH - segH - self.tabBarController.tabBar.frame.size.height);
}

- (void)segChanged { [self loadData]; }

- (void)showLogin {
    OELoginViewController *vc = [[OELoginViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)loadData {
    NSString *types = nil;
    switch (self.seg.selectedSegmentIndex) {
        case 1: types = @"Movie"; break;
        case 2: types = @"Episode,Series"; break;
        default: types = @"Movie,Episode,Series,Video"; break;
    }
    // Show HUD-like
    self.title = @"加载中...";
    [[OEEmbyAPIClient sharedClient] fetchItemsInParent:self.currentParentId itemTypes:types startIndex:0 limit:50 completion:^(id result, NSError *error){
        self.title = @"媒体库";
        if (error) {
            NSLog(@"[OldEmby] fetch error %@", error);
            // Show alert iOS6 compatible
            UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"加载失败" message:error.localizedDescription delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
            [av show];
            return;
        }
        self.items = result;
        [self.tableView reloadData];
        if (self.items.count==0) {
            UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
            empty.text = @"暂无内容，请检查服务器或登录";
            empty.textAlignment = NSTextAlignmentCenter;
            empty.tag = 999;
            empty.textColor = [UIColor grayColor];
            [self.tableView addSubview:empty];
        } else {
            [[self.tableView viewWithTag:999] removeFromSuperview];
        }
    }];
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
    if (it.itemType == OEEmbyItemTypeSeries) {
        OEEpisodeListViewController *vc = [[OEEpisodeListViewController alloc] initWithSeries:it];
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
