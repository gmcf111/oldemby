#import "OESeasonListViewController.h"
#import "Views/OEItemCell.h"
#import "Services/OEEmbyAPIClient.h"
#import "Services/OEImageCache.h"
#import "Models/OEEmbyItem.h"
#import "Models/OECastItem.h"
#import "Controllers/OEEpisodeListViewController.h"
#import "Views/OETheme.h"
#import "Views/OEErrorAlertView.h"
#import "Views/OECastStripView.h"
#import "Constants.h"

// Layout constants for the series header
static const CGFloat kHeaderSidePadding = 12.0;
static const CGFloat kHeaderCoverWidthFraction = 0.36;
static const CGFloat kHeaderCoverMaxWidth = 160.0;
static const CGFloat kHeaderCoverMinWidth = 100.0;
static const CGFloat kHeaderCoverMinHeight = 150.0;
static const CGFloat kHeaderCoverMaxHeight = 240.0;
static const CGFloat kCastStripHeight = 132.0;

@interface OESeasonListViewController ()
@property (nonatomic, strong) OEEmbyItem *series;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *overviewHeaderLabel;
@property (nonatomic, strong) UILabel *overviewLabel;
@property (nonatomic, strong) UILabel *castHeaderLabel;
@property (nonatomic, strong) OECastStripView *castStrip;
@property (nonatomic, strong) NSArray *seasons;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, assign) BOOL castsLoaded;
@property (nonatomic, assign) BOOL didAutoPush;
@property (nonatomic, assign) BOOL isRelayoutingHeader;
@end

@implementation OESeasonListViewController

- (instancetype)initWithSeries:(OEEmbyItem *)series {
    if ((self = [super init])) {
        _series = series;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.series.name ?: @"分季";
    [OETheme prepareViewController:self];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 140;
    [self applyTheme];
    [self.view addSubview:self.tableView];

    [self buildSeriesHeader];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyThemeAndReload) name:kNotificationThemeDidChange object:nil];
    [self loadData];
}

- (void)buildSeriesHeader {
    CGFloat w = self.view.bounds.size.width;
    if (w < 1) w = [UIScreen mainScreen].bounds.size.width;
    CGFloat margin = kHeaderSidePadding;

    CGFloat coverWidth = w * kHeaderCoverWidthFraction;
    coverWidth = MAX(kHeaderCoverMinWidth, MIN(coverWidth, kHeaderCoverMaxWidth));
    CGFloat aspectRatio = self.series.primaryImageAspectRatio > 0 ? self.series.primaryImageAspectRatio : (2.0 / 3.0);
    CGFloat coverHeight = coverWidth / (aspectRatio > 0 ? aspectRatio : (2.0 / 3.0));
    coverHeight = MAX(kHeaderCoverMinHeight, MIN(coverHeight, kHeaderCoverMaxHeight));

    CGFloat rightWidth = MAX(1.0, w - coverWidth - 3 * margin);
    NSString *overviewText = self.series.overview ?: @"暂无简介";
    CGSize textSize = [overviewText sizeWithFont:[UIFont systemFontOfSize:12]
                               constrainedToSize:CGSizeMake(rightWidth, CGFLOAT_MAX)
                                   lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat overviewHeight = MAX(ceil(textSize.height), coverHeight - 60);

    CGFloat coverSectionHeight = MAX(coverHeight, overviewHeight + 60);
    CGFloat headerHeight = margin + coverSectionHeight + 16 + 20 + 6 + kCastStripHeight + margin;

    _headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, headerHeight)];
    _headerView.backgroundColor = [OETheme libraryBackgroundColor];

    _cover = [[UIImageView alloc] initWithFrame:CGRectMake(margin, margin, coverWidth, coverHeight)];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.borderWidth = 1.0;
    _cover.layer.borderColor = [OETheme separatorColor].CGColor;
    _cover.backgroundColor = [OETheme imagePlaceholderColor];
    [_headerView addSubview:_cover];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin + coverWidth + margin, margin, rightWidth, 38)];
    _titleLabel.font = [UIFont boldSystemFontOfSize:16];
    _titleLabel.text = self.series.name ?: @"";
    _titleLabel.textColor = [OETheme primaryTextColor];
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.numberOfLines = 2;
    [_headerView addSubview:_titleLabel];

    CGFloat ovHdrY = CGRectGetMaxY(_titleLabel.frame) + 6;
    _overviewHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin + coverWidth + margin, ovHdrY, rightWidth, 18)];
    _overviewHeaderLabel.font = [UIFont boldSystemFontOfSize:13];
    _overviewHeaderLabel.text = @"简介";
    _overviewHeaderLabel.textColor = [OETheme accentColor];
    _overviewHeaderLabel.backgroundColor = [UIColor clearColor];
    [_headerView addSubview:_overviewHeaderLabel];

    CGFloat ovY = CGRectGetMaxY(_overviewHeaderLabel.frame) + 4;
    _overviewLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin + coverWidth + margin, ovY, rightWidth, overviewHeight)];
    _overviewLabel.font = [UIFont systemFontOfSize:12];
    _overviewLabel.text = overviewText;
    _overviewLabel.textColor = [OETheme secondaryTextColor];
    _overviewLabel.backgroundColor = [UIColor clearColor];
    _overviewLabel.numberOfLines = 0;
    [_headerView addSubview:_overviewLabel];

    CGFloat castHdrY = margin + coverSectionHeight + 16;
    _castHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, castHdrY, MAX(1.0, w - 2 * margin), 20)];
    _castHeaderLabel.font = [UIFont boldSystemFontOfSize:14];
    _castHeaderLabel.text = @"演职人员";
    _castHeaderLabel.textColor = [OETheme primaryTextColor];
    _castHeaderLabel.backgroundColor = [UIColor clearColor];
    [_headerView addSubview:_castHeaderLabel];

    CGFloat castY = CGRectGetMaxY(_castHeaderLabel.frame) + 6;
    _castStrip = [[OECastStripView alloc] initWithFrame:CGRectMake(margin, castY, MAX(1.0, w - 2 * margin), kCastStripHeight)];
    _castStrip.casts = @[];
    [_headerView addSubview:_castStrip];

    self.tableView.tableHeaderView = _headerView;

    NSString *url = [[OEEmbyAPIClient sharedClient] imageURLForItem:self.series width:320 height:480];
    [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image) {
        self.cover.image = image;
    }];

    // Series detail: fills in a missing overview and the cast list in one request.
    [[OEEmbyAPIClient sharedClient] GET:[NSString stringWithFormat:@"/Items/%@", self.series.itemId]
                                params:@{@"Fields": @"Overview,PrimaryImageAspectRatio,People"}
                           completion:^(id result, NSError *error) {
        if (error || ![result isKindOfClass:[NSDictionary class]]) {
            if (!self.castsLoaded) [self loadCasts];
            return;
        }
        NSString *ov = [result[@"Overview"] isKindOfClass:[NSString class]] ? result[@"Overview"] : nil;
        if (ov.length && ![ov isEqualToString:self.overviewLabel.text]) {
            self.overviewLabel.text = ov;
            [self relayoutHeader];
        }
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
    if (self.isRelayoutingHeader) return;
    self.isRelayoutingHeader = YES;

    CGFloat w = self.view.bounds.size.width;
    if (w < 1) w = [UIScreen mainScreen].bounds.size.width;
    CGFloat margin = kHeaderSidePadding;

    CGFloat coverWidth = w * kHeaderCoverWidthFraction;
    coverWidth = MAX(kHeaderCoverMinWidth, MIN(coverWidth, kHeaderCoverMaxWidth));
    CGFloat aspectRatio = self.series.primaryImageAspectRatio > 0 ? self.series.primaryImageAspectRatio : (2.0 / 3.0);
    CGFloat coverHeight = coverWidth / (aspectRatio > 0 ? aspectRatio : (2.0 / 3.0));
    coverHeight = MAX(kHeaderCoverMinHeight, MIN(coverHeight, kHeaderCoverMaxHeight));

    CGFloat rightWidth = MAX(1.0, w - coverWidth - 3 * margin);
    CGFloat rightX = margin + coverWidth + margin;

    NSString *ovText = self.overviewLabel.text ?: @"";
    UIFont *ovFont = self.overviewLabel.font ?: [UIFont systemFontOfSize:12];
    CGSize textSize = [ovText sizeWithFont:ovFont
                         constrainedToSize:CGSizeMake(rightWidth, CGFLOAT_MAX)
                             lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat overviewHeight = MAX(ceil(textSize.height), coverHeight - 60);

    self.cover.frame = CGRectMake(margin, margin, coverWidth, coverHeight);
    self.titleLabel.frame = CGRectMake(rightX, margin, rightWidth, 38);
    self.overviewHeaderLabel.frame = CGRectMake(rightX, margin + 38 + 6, rightWidth, 18);
    self.overviewLabel.frame = CGRectMake(rightX, margin + 38 + 6 + 18 + 4, rightWidth, overviewHeight);

    CGFloat coverSectionHeight = MAX(coverHeight, overviewHeight + 60);
    CGFloat castHdrY = margin + coverSectionHeight + 16;
    self.castHeaderLabel.frame = CGRectMake(margin, castHdrY, MAX(1.0, w - 2 * margin), 20);
    CGFloat castY = CGRectGetMaxY(self.castHeaderLabel.frame) + 6;
    self.castStrip.frame = CGRectMake(margin, castY, MAX(1.0, w - 2 * margin), kCastStripHeight);

    CGFloat headerHeight = margin + coverSectionHeight + 16 + 20 + 6 + kCastStripHeight + margin;
    CGRect newFrame = CGRectMake(0, 0, w, headerHeight);

    if (!CGSizeEqualToSize(self.headerView.frame.size, newFrame.size)) {
        self.headerView.frame = newFrame;
        // Re-assign tableHeaderView to force the table to pick up new height
        self.tableView.tableHeaderView = nil;
        self.tableView.tableHeaderView = self.headerView;
    }

    self.isRelayoutingHeader = NO;
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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // When the auto-pushed episode list is popped back to us, continue
    // popping so the user lands on the poster wall in one back tap.
    if (self.didAutoPush) {
        self.didAutoPush = NO;
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.tableView.frame = self.view.bounds;
    if (self.headerView && fabs(self.headerView.frame.size.width - self.view.bounds.size.width) > 1.0) {
        [self relayoutHeader];
    }
}

- (void)loadData {
    NSUInteger generation = ++self.loadGeneration;
    NSString *resetTitle = self.series.name ?: @"分季";
    self.title = @"加载中…";
    [[OEEmbyAPIClient sharedClient] fetchSeasonsForSeries:self.series.itemId completion:^(id result, NSError *error) {
        if (generation != self.loadGeneration) return;
        self.title = resetTitle;
        if (error) {
            [OEErrorAlertView showWithTitle:@"加载失败" error:error];
            return;
        }
        NSArray *seasons = [result isKindOfClass:[NSArray class]] ? result : @[];
        for (OEEmbyItem *season in seasons) {
            if (!season.seriesId.length) season.seriesId = self.series.itemId;
            if (!season.seriesPrimaryImageTag.length && self.series.imageTag.length) {
                season.seriesPrimaryImageTag = self.series.imageTag;
            }
            if (season.primaryImageAspectRatio <= 0 && self.series.primaryImageAspectRatio > 0) {
                season.primaryImageAspectRatio = self.series.primaryImageAspectRatio;
            }
        }
        self.seasons = seasons;
        [self.tableView reloadData];
        if (seasons.count == 1 && !self.didAutoPush) {
            self.didAutoPush = YES;
            [self pushEpisodeListForSeason:seasons[0] animated:NO];
            return;
        }
        [[self.tableView viewWithTag:995] removeFromSuperview];
        if (!seasons.count) {
            UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
            empty.text = @"暂无分季";
            empty.tag = 995;
            empty.textAlignment = NSTextAlignmentCenter;
            empty.textColor = [OETheme secondaryTextColor];
            empty.backgroundColor = [UIColor clearColor];
            [self.tableView addSubview:empty];
        }
    }];
}

- (void)pushEpisodeListForSeason:(OEEmbyItem *)season animated:(BOOL)animated {
    OEEpisodeListViewController *vc = [[OEEpisodeListViewController alloc] initWithSeries:self.series season:season];
    [self.navigationController pushViewController:vc animated:animated];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.seasons.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"SeasonCell";
    OEItemCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) {
        cell = [[OEItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    // Left-cover/right-text layout; no episode-number prefix (seasons pass 0).
    cell.episodeLayout = YES;
    OEEmbyItem *season = self.seasons[indexPath.row];
    [cell configureWithItem:season episodeNumber:0];
    cell.titleLabel.text = season.indexNumber > 0
        ? [NSString stringWithFormat:@"第 %ld 季", (long)season.indexNumber]
        : (season.name ?: @"分季");
    cell.detailLabel.text = season.overview.length ? season.overview : @"查看分集";
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    OEEmbyItem *season = self.seasons[indexPath.row];
    [self pushEpisodeListForSeason:season animated:YES];
}

- (void)dealloc {
    _tableView.dataSource = nil;
    _tableView.delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
