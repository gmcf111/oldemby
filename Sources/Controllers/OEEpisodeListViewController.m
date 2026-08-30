#import "OEEpisodeListViewController.h"
#import "Views/OEItemCell.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Models/OEServerConfig.h"
#import "Controllers/OEVideoDetailViewController.h"

@interface OEEpisodeListViewController ()
@property (nonatomic, strong) OEEmbyItem *series;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *episodes;
@end

@implementation OEEpisodeListViewController

- (instancetype)initWithSeries:(OEEmbyItem *)series {
    if ((self = [super init])) {
        _series = series;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.series.name ?: @"选集";
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 60;
    [self.view addSubview:self.tableView];

    [self loadData];
}

- (void)loadData {
    OEServerConfig *c = [OEServerConfig sharedConfig];
    if (!c.userId) {
        UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"未登录" message:@"请先在 视频 页登录" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
        [av show];
        return;
    }
    NSString *oldTitle = self.title;
    self.title = @"加载中...";
    // Emby: GET /Shows/{seriesId}/Episodes?UserId=... returns all episodes ordered by season/episode
    NSString *path = [NSString stringWithFormat:@"/Shows/%@/Episodes", self.series.itemId];
    NSDictionary *params = @{@"UserId": c.userId,
                             @"Fields": @"PrimaryImageAspectRatio,Overview,RunTimeTicks",
                             @"ImageTypeLimit": @"1"};
    [[OEEmbyAPIClient sharedClient] GET:path params:params completion:^(id result, NSError *error){
        self.title = oldTitle;
        if (error) {
            UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"加载失败" message:error.localizedDescription delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
            [av show];
            return;
        }
        NSArray *items = result[@"Items"];
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *d in items) {
            if ([d isKindOfClass:[NSDictionary class]]) [out addObject:[OEEmbyItem itemWithDictionary:d]];
        }
        self.episodes = out;
        [self.tableView reloadData];
        if (self.episodes.count==0) {
            UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
            empty.text = @"暂无剧集";
            empty.tag = 997;
            empty.textAlignment = NSTextAlignmentCenter;
            empty.textColor = [UIColor grayColor];
            [self.tableView addSubview:empty];
        } else {
            [[self.tableView viewWithTag:997] removeFromSuperview];
        }
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.episodes.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"EpisodeCell";
    OEItemCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) cell = [[OEItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
    OEEmbyItem *it = self.episodes[indexPath.row];
    [cell configureWithItem:it];
    NSString *se = @"";
    if (it.seasonNumber > 0 && it.episodeNumber > 0) {
        se = [NSString stringWithFormat:@"S%02ldE%02ld · ", (long)it.seasonNumber, (long)it.episodeNumber];
    }
    cell.detailLabel.text = [NSString stringWithFormat:@"%@%@", se, [it displayDuration]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    OEEmbyItem *it = self.episodes[indexPath.row];
    OEVideoDetailViewController *vc = [[OEVideoDetailViewController alloc] initWithItem:it];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
