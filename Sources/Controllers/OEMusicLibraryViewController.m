#import "OEMusicLibraryViewController.h"
#import "Views/OEItemCell.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Controllers/OEMusicPlayerViewController.h"

@interface OEMusicLibraryViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) UISegmentedControl *seg;
@end

@implementation OEMusicLibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"音乐";
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    self.seg = [[UISegmentedControl alloc] initWithItems:@[@"歌曲", @"专辑", @"歌手"]];
    self.seg.selectedSegmentIndex = 0;
    [self.seg addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    self.seg.frame = CGRectMake(10, 68, self.view.bounds.size.width-20, 30);
    self.seg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.seg];

    CGFloat navH = 44+20;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, navH+40, self.view.bounds.size.width, self.view.bounds.size.height - navH - 40 - 49) style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 60;
    [self.view addSubview:self.tableView];

    [self loadData];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadData) name:@"OEDidLoginNotification" object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat navH = self.navigationController.navigationBar.frame.size.height + 20;
    self.seg.frame = CGRectMake(10, navH+4, self.view.bounds.size.width-20, 30);
    self.tableView.frame = CGRectMake(0, navH+40, self.view.bounds.size.width, self.view.bounds.size.height - navH - 40 - self.tabBarController.tabBar.frame.size.height);
}

- (void)loadData {
    NSString *types = nil;
    switch (self.seg.selectedSegmentIndex) {
        case 0: types = @"Audio"; break;
        case 1: types = @"MusicAlbum"; break;
        case 2: types = @"MusicArtist"; break;
        default: types = @"Audio"; break;
    }
    self.title = @"加载中...";
    [[OEEmbyAPIClient sharedClient] fetchItemsInParent:nil itemTypes:types startIndex:0 limit:50 completion:^(id result, NSError *error){
        self.title = @"音乐";
        if (error) {
            UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"加载失败" message:error.localizedDescription delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
            [av show];
            return;
        }
        self.items = result;
        [self.tableView reloadData];
        if (self.items.count==0) {
            UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
            empty.text = @"暂无音乐，请检查音乐库";
            empty.tag = 998;
            empty.textAlignment = NSTextAlignmentCenter;
            empty.textColor = [UIColor grayColor];
            [self.tableView addSubview:empty];
        } else {
            [[self.tableView viewWithTag:998] removeFromSuperview];
        }
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"MusicCell";
    OEItemCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) cell = [[OEItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
    OEEmbyItem *it = self.items[indexPath.row];
    // Override row height layout: reuse same cell but shorter
    [cell configureWithItem:it];
    // Show album/artist for audio
    if (it.itemType == OEEmbyItemTypeAudio) {
        cell.detailLabel.text = [NSString stringWithFormat:@"%@ - %@", it.artist ?: @"未知歌手", it.album ?: @""];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    OEEmbyItem *it = self.items[indexPath.row];
    if (it.itemType == OEEmbyItemTypeAudio) {
        OEMusicPlayerViewController *vc = [[OEMusicPlayerViewController alloc] initWithItem:it playlist:self.items];
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        // For album/artist, drill down: fetch songs in that parent
        // Simple: push new library with parentId
        // Reuse self logic by setting parent and reloading? Instead push detail list
        UIAlertView *av = [[UIAlertView alloc] initWithTitle:it.name message:@"请在 Emby 服务器中浏览该专辑/歌手包含的歌曲 (下一版支持层级浏览)" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
        [av show];
    }
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
