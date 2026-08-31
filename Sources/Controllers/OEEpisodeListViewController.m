#import "OEEpisodeListViewController.h"
#import "Views/OEItemCell.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Models/OECastItem.h"
#import "Models/OEServerConfig.h"
#import "Controllers/OEVideoDetailViewController.h"
#import "Views/OETheme.h"
#import "Views/OECastStripView.h"
#import "Constants.h"

// Layout constants for the series header
static const CGFloat kHeaderSidePadding = 12.0;
static const CGFloat kHeaderCoverWidthFraction = 0.36;
static const CGFloat kHeaderCoverMaxWidth = 160.0;
static const CGFloat kHeaderCoverMinWidth = 100.0;
static const CGFloat kHeaderCoverMinHeight = 150.0;
static const CGFloat kHeaderCoverMaxHeight = 240.0;
static const CGFloat kCastStripHeight = 110.0;

@interface OEEpisodeListViewController ()
@property (nonatomic, strong) OEEmbyItem *series;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *overviewHeaderLabel;
@property (nonatomic, strong) UILabel *overviewLabel;
@property (nonatomic, strong) UILabel *castHeaderLabel;
@property (nonatomic, strong) OECastStripView *castStrip;
@property (nonatomic, strong) NSArray *episodes;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, assign) BOOL castsLoaded;
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
    [OETheme prepareViewController:self];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 140;
    [self applyTheme];
    [self.view addSubview:self.tableView];

    // Build the series header view
    [self buildSeriesHeader];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyThemeAndReload) name:kNotificationThemeDidChange object:nil];
    [self loadData];
}

- (void)buildSeriesHeader {
    CGFloat w = self.view.bounds.size.width;
    if (w < 1) w = [UIScreen mainScreen].bounds.size.width;
    CGFloat margin = kHeaderSidePadding;

    // Calculate cover dimensions
    CGFloat coverWidth = w * kHeaderCoverWidthFraction;
    coverWidth = MAX(kHeaderCoverMinWidth, MIN(coverWidth, kHeaderCoverMaxWidth));
    CGFloat aspectRatio = self.series.primaryImageAspectRatio > 0 ? self.series.primaryImageAspectRatio : (2.0 / 3.0);
    CGFloat coverHeight = coverWidth / (aspectRatio > 0 ? aspectRatio : (2.0 / 3.0));
    coverHeight = MAX(kHeaderCoverMinHeight, MIN(coverHeight, kHeaderCoverMaxHeight));

    // Calculate overview height
    CGFloat rightWidth = w - coverWidth - 3 * margin;
    NSString *overviewText = self.series.overview ?: @"暂无简介";
    CGSize textSize = [overviewText sizeWithFont:[UIFont systemFontOfSize:12]
                               constrainedToSize:CGSizeMake(rightWidth, CGFLOAT_MAX)
                                   lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat overviewHeight = MAX(ceil(textSize.height), coverHeight - 60);

    // Total header height: cover section + cast section + padding
    CGFloat coverSectionHeight = MAX(coverHeight, overviewHeight + 60);
    CGFloat headerHeight = margin + coverSectionHeight + 16 + 20 + 6 + kCastStripHeight + margin;

    _headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, headerHeight)];
    _headerView.backgroundColor = [OETheme libraryBackgroundColor];

    // Cover image
    _cover = [[UIImageView alloc] initWithFrame:CGRectMake(margin, margin, coverWidth, coverHeight)];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.borderWidth = 1.0;
    _cover.layer.borderColor = [OETheme separatorColor].CGColor;
    _cover.backgroundColor = [OETheme imagePlaceholderColor];
    [_headerView addSubview:_cover];

    // Title label
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin + coverWidth + margin, margin, rightWidth, 38)];
    _titleLabel.font = [UIFont boldSystemFontOfSize:16];
    _titleLabel.text = self.series.name ?: @"";
    _titleLabel.textColor = [OETheme primaryTextColor];
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.numberOfLines = 2;
    [_headerView addSubview:_titleLabel];

    // Overview header label
    CGFloat ovHdrY = CGRectGetMaxY(_titleLabel.frame) + 6;
    _overviewHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin + coverWidth + margin, ovHdrY, rightWidth, 18)];
    _overviewHeaderLabel.font = [UIFont boldSystemFontOfSize:13];
    _overviewHeaderLabel.text = @"简介";
    _overviewHeaderLabel.textColor = [OETheme accentColor];
    _overviewHeaderLabel.backgroundColor = [UIColor clearColor];
    [_headerView addSubview:_overviewHeaderLabel];

    // Overview label
    CGFloat ovY = CGRectGetMaxY(_overviewHeaderLabel.frame) + 4;
    _overviewLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin + coverWidth + margin, ovY, rightWidth, overviewHeight)];
    _overviewLabel.font = [UIFont systemFontOfSize:12];
    _overviewLabel.text = overviewText;
    _overviewLabel.textColor = [OETheme secondaryTextColor];
    _overviewLabel.backgroundColor = [UIColor clearColor];
    _overviewLabel.numberOfLines = 0;
    [_headerView addSubview:_overviewLabel];

    // Cast header label
    CGFloat castHdrY = margin + coverSectionHeight + 16;
    _castHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, castHdrY, w - 2 * margin, 20)];
    _castHeaderLabel.font = [UIFont boldSystemFontOfSize:14];
    _castHeaderLabel.text = @"演职人员";
    _castHeaderLabel.textColor = [OETheme primaryTextColor];
    _castHeaderLabel.backgroundColor = [UIColor clearColor];
    [_headerView addSubview:_castHeaderLabel];

    // Cast strip view
    CGFloat castY = CGRectGetMaxY(_castHeaderLabel.frame) + 6;
    _castStrip = [[OECastStripView alloc] initWithFrame:CGRectMake(margin, castY, w - 2 * margin, kCastStripHeight)];
    _castStrip.casts = @[];
    [_headerView addSubview:_castStrip];

    self.tableView.tableHeaderView = _headerView;

    // Load cover image
    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:self.series width:320 height:480];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image) {
        self.cover.image = image;
    }];

    // Fetch series detail: get overview if missing AND cast list in one request.
    // The GET /Items/{Id}?Fields=Overview,People response includes both Overview
    // and a People array, so we don't need a separate fetchCastsForItem call.
    [[OEEmbyAPIClient sharedClient] GET:[NSString stringWithFormat:@"/Items/%@", self.series.itemId]
                                params:@{@"Fields": @"Overview,PrimaryImageAspectRatio,People"}
                           completion:^(id result, NSError *error) {
        if (error || ![result isKindOfClass:[NSDictionary class]]) {
            // Fallback: fetch casts separately if the detail request failed
            if (!self.castsLoaded) [self loadCasts];
            return;
        }
        // Update overview if we got one and didn't have it before
        NSString *ov = [result[@"Overview"] isKindOfClass:[NSString class]] ? result[@"Overview"] : nil;
        if (ov.length && !self.overviewLabel.text.length) {
            self.overviewLabel.text = ov;
            [self relayoutHeader];
        } else if (ov.length && ![ov isEqualToString:self.overviewLabel.text]) {
            self.overviewLabel.text = ov;
            [self relayoutHeader];
        }
        // Parse casts from People array
        id people = [result objectForKey:@"People"];
        if ([people isKindOfClass:[NSArray class]] && !self.castsLoaded) {
            NSMutableArray *out = [NSMutableArray array];
            for (id raw in people) {
                if (![raw isKindOfClass:[NSDictionary class]]) continue;
                OECastItem *cast = [OECastItem castWithDictionary:raw];
                if (cast) [out addObject:cast];
            }
            self.castsLoaded = YES;
            self.castStrip.casts = out;
        }
    }];
}

- (void)loadCasts {
    [[OEEmbyAPIClient sharedClient] fetchCastsForItem:self.series.itemId completion:^(id result, NSError *error) {
        if (error) return;
        if ([result isKindOfClass:[NSArray class]]) {
            self.castsLoaded = YES;
            self.castStrip.casts = result;
        }
    }];
}

- (void)relayoutHeader {
    CGFloat w = self.view.bounds.size.width;
    if (w < 1) w = [UIScreen mainScreen].bounds.size.width;
    CGFloat margin = kHeaderSidePadding;

    CGFloat coverWidth = w * kHeaderCoverWidthFraction;
    coverWidth = MAX(kHeaderCoverMinWidth, MIN(coverWidth, kHeaderCoverMaxWidth));
    CGFloat aspectRatio = self.series.primaryImageAspectRatio > 0 ? self.series.primaryImageAspectRatio : (2.0 / 3.0);
    CGFloat coverHeight = coverWidth / (aspectRatio > 0 ? aspectRatio : (2.0 / 3.0));
    coverHeight = MAX(kHeaderCoverMinHeight, MIN(coverHeight, kHeaderCoverMaxHeight));

    CGFloat rightWidth = w - coverWidth - 3 * margin;
    CGFloat rightX = margin + coverWidth + margin;

    // Recalculate overview height with updated text
    CGSize textSize = [self.overviewLabel.text sizeWithFont:self.overviewLabel.font
                                          constrainedToSize:CGSizeMake(rightWidth, CGFLOAT_MAX)
                                              lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat overviewHeight = MAX(ceil(textSize.height), coverHeight - 60);

    // Update frames
    self.cover.frame = CGRectMake(margin, margin, coverWidth, coverHeight);
    self.titleLabel.frame = CGRectMake(rightX, margin, rightWidth, 38);
    self.overviewHeaderLabel.frame = CGRectMake(rightX, margin + 38 + 6, rightWidth, 18);
    self.overviewLabel.frame = CGRectMake(rightX, margin + 38 + 6 + 18 + 4, rightWidth, overviewHeight);

    CGFloat coverSectionHeight = MAX(coverHeight, overviewHeight + 60);
    CGFloat castHdrY = margin + coverSectionHeight + 16;
    self.castHeaderLabel.frame = CGRectMake(margin, castHdrY, w - 2 * margin, 20);
    CGFloat castY = CGRectGetMaxY(self.castHeaderLabel.frame) + 6;
    self.castStrip.frame = CGRectMake(margin, castY, w - 2 * margin, kCastStripHeight);

    CGFloat headerHeight = margin + coverSectionHeight + 16 + 20 + 6 + kCastStripHeight + margin;
    self.headerView.frame = CGRectMake(0, 0, w, headerHeight);

    // Re-assign tableHeaderView to force the table to pick up new height
    self.tableView.tableHeaderView = nil;
    self.tableView.tableHeaderView = self.headerView;
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
    // Re-layout header on rotation / resize
    if (self.headerView) [self relayoutHeader];
}

- (void)loadData {
    NSUInteger generation = ++self.loadGeneration;
    OEServerConfig *c = [OEServerConfig sharedConfig];
    if (!c.userId) {
        UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"未登录" message:@"请先在影视页登录" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
        [av show];
        return;
    }
    NSString *resetTitle = self.series.name ?: @"选集";
    self.title = @"加载中...";
    // Emby: GET /Shows/{seriesId}/Episodes?UserId=... returns all episodes ordered by season/episode
    NSString *path = [NSString stringWithFormat:@"/Shows/%@/Episodes", self.series.itemId];
    NSDictionary *params = @{@"UserId": c.userId,
                             @"Fields": @"PrimaryImageAspectRatio,Overview,RunTimeTicks",
                             @"ImageTypeLimit": @"1"};
    [[OEEmbyAPIClient sharedClient] GET:path params:params completion:^(id result, NSError *error){
        if (generation != self.loadGeneration) return;
        self.title = resetTitle;
        if (error) {
            UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"加载失败" message:error.localizedDescription delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
            [av show];
            return;
        }
        id candidate = [result isKindOfClass:[NSDictionary class]] ? result[@"Items"] : nil;
        NSArray *items = [candidate isKindOfClass:[NSArray class]] ? candidate : nil;
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *d in items) {
            if ([d isKindOfClass:[NSDictionary class]]) [out addObject:[OEEmbyItem itemWithDictionary:d]];
        }
        self.episodes = out;
        [self.tableView reloadData];
        [[self.tableView viewWithTag:997] removeFromSuperview];
        if (self.episodes.count==0) {
            UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
            empty.text = @"暂无剧集";
            empty.tag = 997;
            empty.textAlignment = NSTextAlignmentCenter;
            empty.textColor = [OETheme secondaryTextColor];
            [self.tableView addSubview:empty];
        }
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.episodes.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"EpisodeCell";
    OEItemCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) cell = [[OEItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
    cell.episodeLayout = YES;
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

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
