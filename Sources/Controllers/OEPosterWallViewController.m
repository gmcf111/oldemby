#import "OEPosterWallViewController.h"
#import "Views/OEPosterGridCell.h"
#import "Views/OETheme.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEEmbyItem.h"
#import "Controllers/OEVideoDetailViewController.h"
#import "Controllers/OEEpisodeListViewController.h"
#import "Constants.h"
#import <math.h>

@interface OEPosterWallViewController ()
@property (nonatomic, strong) OEEmbyItem *library;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, assign) NSInteger pageStart;
@property (nonatomic, assign) NSInteger pageSize;
@property (nonatomic, assign) BOOL loadingPage;
@property (nonatomic, assign) BOOL hasMorePages;
@end

@implementation OEPosterWallViewController

- (instancetype)initWithLibrary:(OEEmbyItem *)library {
    if ((self = [super init])) {
        _library = library;
    }
    return self;
}

// Movies libraries hold Movies; TV libraries hold Series; anything else gets both.
- (NSString *)itemTypes {
    NSString *collectionType = self.library.collectionType;
    if ([collectionType isEqualToString:@"movies"]) return @"Movie";
    if ([collectionType isEqualToString:@"tvshows"]) return @"Series";
    return @"Movie,Series";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [OETheme prepareViewController:self];
    self.title = self.library.name ?: @"媒体库";
    // No left bar button here: the navigation back button must stay visible.
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(loadData)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = [OEPosterGridCell rowHeightForTableWidth:self.view.bounds.size.width];
    [self applyTheme];
    [self.view addSubview:self.tableView];
    self.pageSize = 60;
    self.hasMorePages = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyThemeAndReload) name:kNotificationThemeDidChange object:nil];
    [self loadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.tableView.frame = self.view.bounds;
    self.tableView.rowHeight = [OEPosterGridCell rowHeightForTableWidth:self.view.bounds.size.width];
}

- (void)applyTheme {
    self.view.backgroundColor = [OETheme libraryBackgroundColor];
    self.tableView.backgroundColor = [OETheme libraryBackgroundColor];
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)applyThemeAndReload {
    [self applyTheme];
    [self.tableView reloadData];
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
    [[OEEmbyAPIClient sharedClient] fetchItemsInParent:self.library.itemId itemTypes:[self itemTypes] startIndex:start limit:self.pageSize sortBy:@"SortName" recursive:YES completion:^(id result, NSError *error) {
        if (generation != self.loadGeneration) return;
        self.loadingPage = NO;
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
        [[self.tableView viewWithTag:996] removeFromSuperview];
        if (!self.items.count) [self showEmptyState];
    }];
}

- (void)showEmptyState {
    UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.view.bounds.size.width, 40)];
    empty.text = @"此媒体库暂无内容";
    empty.textAlignment = NSTextAlignmentCenter;
    empty.tag = 996;
    empty.textColor = [OETheme secondaryTextColor];
    empty.backgroundColor = [UIColor clearColor];
    [self.tableView addSubview:empty];
}

- (void)posterTapped:(UIControl *)slot {
    NSInteger index = slot.tag;
    if (index < 0 || index >= (NSInteger)self.items.count) return;
    OEEmbyItem *item = self.items[index];
    if (item.itemType == OEEmbyItemTypeSeries) {
        [self.navigationController pushViewController:[[OEEpisodeListViewController alloc] initWithSeries:item] animated:YES];
    } else {
        [self.navigationController pushViewController:[[OEVideoDetailViewController alloc] initWithItem:item] animated:YES];
    }
}

#pragma mark - Table

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger rows = (NSInteger)ceil((double)self.items.count / [OEPosterGridCell columnCount]);
    if (indexPath.row == rows - 1 && !self.loadingPage && self.hasMorePages) [self loadPageAtStart:self.pageStart reset:NO];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)ceil((double)self.items.count / [OEPosterGridCell columnCount]);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"OEPosterGridCell";
    OEPosterGridCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) cell = [[OEPosterGridCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
    NSInteger startIndex = indexPath.row * [OEPosterGridCell columnCount];
    [cell configureWithItems:self.items startIndex:startIndex target:self action:@selector(posterTapped:)];
    return cell;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
