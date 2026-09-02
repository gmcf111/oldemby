#import "OEEpisodeListViewController.h"
#import "Views/OEItemCell.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Models/OEServerConfig.h"
#import "Controllers/OEVideoDetailViewController.h"
#import "Views/OETheme.h"
#import "Views/OEErrorAlertView.h"
#import "Constants.h"

@interface OEEpisodeListViewController ()
@property (nonatomic, strong) OEEmbyItem *series;
@property (nonatomic, strong) OEEmbyItem *season;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *episodes;
@property (nonatomic, assign) NSUInteger loadGeneration;
@end

@implementation OEEpisodeListViewController

- (instancetype)initWithSeries:(OEEmbyItem *)series {
    return [self initWithSeries:series season:nil];
}

- (instancetype)initWithSeries:(OEEmbyItem *)series season:(OEEmbyItem *)season {
    if ((self = [super init])) {
        _series = series;
        _season = season;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.season.name ?: (self.series.name ?: @"选集");
    [OETheme prepareViewController:self];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 110;
    [self applyTheme];
    [self.view addSubview:self.tableView];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyThemeAndReload) name:kNotificationThemeDidChange object:nil];
    [self loadData];
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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.tableView.frame = self.view.bounds;
}

- (void)loadData {
    NSUInteger generation = ++self.loadGeneration;
    OEServerConfig *c = [OEServerConfig sharedConfig];
    if (!c.userId) {
        UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"未登录" message:@"请先在影视页登录" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
        [av show];
        return;
    }
    NSString *resetTitle = self.season.name ?: (self.series.name ?: @"选集");
    self.title = @"加载中...";

    NSString *seriesId = self.series.itemId.length ? self.series.itemId : self.season.seriesId;
    if (!seriesId.length && self.season.itemId.length) {
        // Fallback: query episodes by season ParentId
        [[OEEmbyAPIClient sharedClient] fetchItemsInParent:self.season.itemId itemTypes:@"Episode" startIndex:0 limit:500 sortBy:@"IndexNumber" recursive:NO completion:^(id result, NSError *error) {
            if (generation != self.loadGeneration) return;
            self.title = resetTitle;
            if (error) {
                [OEErrorAlertView showWithTitle:@"加载失败" error:error];
                return;
            }
            NSArray *items = [result isKindOfClass:[NSArray class]] ? result : @[];
            for (OEEmbyItem *ep in items) {
                if (!ep.seriesId.length) ep.seriesId = seriesId;
            }
            self.episodes = items;
            [self.tableView reloadData];
            [self updateEmptyState];
        }];
        return;
    }

    // Emby: GET /Shows/{seriesId}/Episodes?SeasonId=... returns the season's
    // episodes ordered by episode number.
    NSString *path = [NSString stringWithFormat:@"/Shows/%@/Episodes", seriesId ?: @""];
    NSMutableDictionary *params = [@{@"UserId": c.userId,
                             @"Fields": @"PrimaryImageAspectRatio,Overview,RunTimeTicks",
                             @"ImageTypeLimit": @"1"} mutableCopy];
    if (self.season.itemId.length) params[@"SeasonId"] = self.season.itemId;
    [[OEEmbyAPIClient sharedClient] GET:path params:params completion:^(id result, NSError *error){
        if (generation != self.loadGeneration) return;
        self.title = resetTitle;
        if (error) {
            [OEErrorAlertView showWithTitle:@"加载失败" error:error];
            return;
        }
        id candidate = [result isKindOfClass:[NSDictionary class]] ? result[@"Items"] : nil;
        NSArray *items = [candidate isKindOfClass:[NSArray class]] ? candidate : nil;
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *d in items) {
            if (![d isKindOfClass:[NSDictionary class]]) continue;
            OEEmbyItem *episode = [OEEmbyItem itemWithDictionary:d];
            if (!episode.seriesId.length) episode.seriesId = seriesId;
            [out addObject:episode];
        }
        self.episodes = out;
        [self.tableView reloadData];
        [self updateEmptyState];
    }];
}

- (void)updateEmptyState {
    [[self.tableView viewWithTag:997] removeFromSuperview];
    if (self.episodes.count == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
        empty.text = @"暂无剧集";
        empty.tag = 997;
        empty.textAlignment = NSTextAlignmentCenter;
        empty.textColor = [OETheme secondaryTextColor];
        empty.backgroundColor = [UIColor clearColor];
        [self.tableView addSubview:empty];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.episodes.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"EpisodeCell";
    OEItemCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) cell = [[OEItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
    cell.episodeLayout = YES;
    OEEmbyItem *it = (indexPath.row < (NSInteger)self.episodes.count) ? self.episodes[indexPath.row] : nil;
    if (!it) return cell;
    [cell configureWithItem:it episodeNumber:it.episodeNumber];
    // Emby-web style: bold "N." prefix + episode name.
    cell.titleLabel.text = it.name ?: @"未命名";
    NSString *se = @"";
    if (it.seasonNumber > 0 && it.episodeNumber > 0) {
        se = [NSString stringWithFormat:@"S%02ldE%02ld · ", (long)it.seasonNumber, (long)it.episodeNumber];
    }
    cell.detailLabel.text = [NSString stringWithFormat:@"%@%@", se, [it displayDuration]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.episodes.count) return;
    OEEmbyItem *it = self.episodes[indexPath.row];
    OEVideoDetailViewController *vc = [[OEVideoDetailViewController alloc] initWithItem:it];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)dealloc {
    _tableView.dataSource = nil;
    _tableView.delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
