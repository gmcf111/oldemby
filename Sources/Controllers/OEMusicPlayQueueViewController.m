#import "OEMusicPlayQueueViewController.h"
#import "Services/OEMusicPlaybackManager.h"
#import "Models/OEEmbyItem.h"
#import "Views/OETheme.h"
#import "Constants.h"

@implementation OEMusicPlayQueueViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [OETheme prepareViewController:self];
    self.title = @"播放队列";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self
                                                                                           action:@selector(doneTapped)];
    self.tableView.rowHeight = 48;
    [self applyTheme];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadQueue) name:kNotificationMusicPlaybackStateChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:kNotificationThemeDidChange object:nil];
}

- (void)applyTheme {
    self.tableView.backgroundColor = [OETheme libraryBackgroundColor];
    self.tableView.separatorColor = [OETheme separatorColor];
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
    [self.tableView reloadData];
}

- (void)reloadQueue {
    [self.tableView reloadData];
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [OEMusicPlaybackManager sharedManager].playlist.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"QueueRow";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.textLabel.backgroundColor = [UIColor clearColor];
        cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    }
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    OEEmbyItem *item = manager.playlist[indexPath.row];
    cell.textLabel.text = item.name ?: @"未知曲目";
    cell.detailTextLabel.text = item.artist ?: item.album ?: @"";
    BOOL current = indexPath.row == manager.currentIndex;
    cell.accessoryType = current ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.textLabel.textColor = current ? [OETheme accentColor] : [OETheme primaryTextColor];
    cell.detailTextLabel.textColor = [OETheme secondaryTextColor];
    cell.backgroundColor = [OETheme cellColor];
    cell.contentView.backgroundColor = [OETheme cellColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [[OEMusicPlaybackManager sharedManager] playItemAtIndex:indexPath.row];
    // The state notification reloads and moves the checkmark; keep the queue
    // open so the user can keep browsing while the new track loads.
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
