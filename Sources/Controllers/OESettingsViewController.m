#import "OESettingsViewController.h"
#import "Models/OETranscodeSettings.h"
#import "Models/OEServerConfig.h"
#import "Services/OEEmbyAPIClient.h"
#import "Views/OETheme.h"
#import "Constants.h"

@interface OESettingsViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) OETranscodeSettings *settings;
@end

@implementation OESettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    [OETheme prepareViewController:self];
    self.settings = [OETranscodeSettings sharedSettings];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self applyTheme];
    [self.view addSubview:self.table];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"退出登录" style:UIBarButtonItemStylePlain target:self action:@selector(logout)];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyThemeAndReload) name:kNotificationThemeDidChange object:nil];
}

- (void)applyTheme {
    self.view.backgroundColor = [OETheme libraryBackgroundColor];
    self.table.backgroundView = nil; // replaces the iOS 6 linen texture with a solid theme color
    self.table.backgroundColor = [OETheme libraryBackgroundColor];
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)applyThemeAndReload {
    [self applyTheme];
    [self.table reloadData];
}

- (void)themeSwitchChanged:(UISegmentedControl *)control {
    [OETheme setThemeMode:control.selectedSegmentIndex == 1 ? OEThemeModeLight : OEThemeModeDark];
}

- (void)save {
    [self.settings save];
    UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"已保存" message:[NSString stringWithFormat:@"分辨率 %@ / 视频码率 %ld kbps / 音频码率 %ld kbps / 模式 %@",
        [self.settings resolutionString], (long)self.settings.maxVideoBitrate/1000, (long)self.settings.maxAudioBitrate/1000, self.settings.directPlay?@"直接播放":@"转码"] delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
    [av show];
    [self.table reloadData];
}

- (void)logout {
    UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"退出登录" message:@"确定要清除服务器配置吗？" delegate:self cancelButtonTitle:@"取消" otherButtonTitles:@"确定", nil];
    av.tag = 1001;
    [av show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag==1001 && buttonIndex==1) {
        [[OEEmbyAPIClient sharedClient] logout];
        [self.table reloadData];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OEDidLogoutNotification" object:nil];
        UIAlertView *a2 = [[UIAlertView alloc] initWithTitle:@"已退出" message:@"请到影视页重新登录" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
        [a2 show];
    }
    if (alertView.tag >= 2000 && buttonIndex==1) {
        // bitrate custom input via alertViewStylePlainTextInput (iOS5+)
        UITextField *tf = [alertView textFieldAtIndex:0];
        NSInteger v = [tf.text integerValue];
        if (alertView.tag==2000) {
            // video bitrate: 500-20000 kbps
            if (v >= 500 && v <= 20000) {
                self.settings.maxVideoBitrate = v*1000;
                [self.table reloadData];
            } else {
                UIAlertView *err = [[UIAlertView alloc] initWithTitle:@"输入无效" message:@"视频码率范围需在 500 到 20000 kbps 之间" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
                [err show];
            }
        } else {
            // audio bitrate: 64-512 kbps
            if (v >= 64 && v <= 512) {
                self.settings.maxAudioBitrate = v*1000;
                [self.table reloadData];
            } else {
                UIAlertView *err = [[UIAlertView alloc] initWithTitle:@"输入无效" message:@"音频码率范围需在 64 到 512 kbps 之间" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
                [err show];
            }
        }
    }
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section==0) return 1; // appearance
    if (section==1) return 4; // resolution 480/720/1080 + note
    if (section==2) return 5; // bitrate presets + custom
    if (section==3) return 2; // direct play toggle + audio bitrate
    return 2; // account info
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section==0) return @"外观";
    if (section==1) return @"分辨率 (默认 720p)";
    if (section==2) return @"视频码率 (默认 4 Mbps)";
    if (section==3) return @"播放模式与音频";
    return @"账户";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"SCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:ID];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    cell.detailTextLabel.text = nil;
    cell.backgroundColor = [OETheme cellColor];
    cell.textLabel.textColor = [OETheme primaryTextColor];
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.detailTextLabel.textColor = [OETheme secondaryTextColor];
    cell.detailTextLabel.backgroundColor = [UIColor clearColor];

    if (indexPath.section==0) {
        cell.textLabel.text = @"主题模式";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISegmentedControl *themeSwitch = [[UISegmentedControl alloc] initWithItems:@[@"深色", @"浅色"]];
        themeSwitch.frame = CGRectMake(0, 0, 150, 30);
        themeSwitch.selectedSegmentIndex = [OETheme themeMode] == OEThemeModeLight ? 1 : 0;
        [themeSwitch addTarget:self action:@selector(themeSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = themeSwitch;
    } else if (indexPath.section==1) {
        if (indexPath.row==0) { cell.textLabel.text=@"480p (720x480)"; cell.accessoryType = (self.settings.resolution==OEResolution480p)?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone; }
        else if (indexPath.row==1) { cell.textLabel.text=@"720p (1280x720) 推荐"; cell.accessoryType = (self.settings.resolution==OEResolution720p)?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone; }
        else if (indexPath.row==2) { cell.textLabel.text=@"1080p (1920x1080)"; cell.detailTextLabel.text=@"老设备解码吃力"; cell.accessoryType = (self.settings.resolution==OEResolution1080p)?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone; }
        else { cell.textLabel.text=@"说明"; cell.detailTextLabel.text=@"向 Emby 请求转码为 H.264"; cell.selectionStyle=UITableViewCellSelectionStyleNone; }
    } else if (indexPath.section==2) {
        NSArray *presets = @[@1500, @2500, @4000, @8000];
        NSArray *titles = @[@"1.5 Mbps 省流", @"2.5 Mbps 均衡", @"4 Mbps 高清 (默认)", @"8 Mbps 极清"];
        if (indexPath.row < 4) {
            cell.textLabel.text = titles[indexPath.row];
            NSInteger br = [presets[indexPath.row] integerValue]*1000;
            cell.accessoryType = (self.settings.maxVideoBitrate==br && !self.settings.directPlay)?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
        } else {
            cell.textLabel.text = @"自定义码率";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld kbps", (long)self.settings.maxVideoBitrate/1000];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section==3) {
        if (indexPath.row==0) {
            cell.textLabel.text = @"直接播放 (不转码)";
            cell.detailTextLabel.text = self.settings.directPlay?@"已开启":@"已关闭";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = self.settings.directPlay;
            [sw addTarget:self action:@selector(toggleDirectPlay:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"音频码率";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld kbps", (long)self.settings.maxAudioBitrate/1000];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.accessoryView = nil;
        }
    } else {
        OEServerConfig *c = [OEServerConfig sharedConfig];
        if (indexPath.row==0) {
            cell.textLabel.text = @"服务器";
            cell.detailTextLabel.text = c.host ?: @"未登录";
        } else {
            cell.textLabel.text = @"用户";
            cell.detailTextLabel.text = c.username ?: @"-";
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section==1 && indexPath.row<3) {
        self.settings.resolution = (OEResolution)indexPath.row;
        [tableView reloadData];
    } else if (indexPath.section==2 && indexPath.row<4) {
        NSArray *presets = @[@1500, @2500, @4000, @8000];
        self.settings.maxVideoBitrate = [presets[indexPath.row] integerValue]*1000;
        self.settings.directPlay = NO;
        [tableView reloadData];
    } else if (indexPath.section==2 && indexPath.row==4) {
        UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"自定义视频码率" message:@"输入 kbps 数值 (500-20000)" delegate:self cancelButtonTitle:@"取消" otherButtonTitles:@"确定", nil];
        av.alertViewStyle = UIAlertViewStylePlainTextInput;
        av.tag = 2000;
        [av textFieldAtIndex:0].keyboardType = UIKeyboardTypeNumberPad;
        [av textFieldAtIndex:0].text = [NSString stringWithFormat:@"%ld", (long)self.settings.maxVideoBitrate/1000];
        [av show];
    } else if (indexPath.section==3 && indexPath.row==1) {
        UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"自定义音频码率" message:@"输入 kbps 数值 (64-512)" delegate:self cancelButtonTitle:@"取消" otherButtonTitles:@"确定", nil];
        av.alertViewStyle = UIAlertViewStylePlainTextInput;
        av.tag = 2001;
        [av textFieldAtIndex:0].keyboardType = UIKeyboardTypeNumberPad;
        [av textFieldAtIndex:0].text = [NSString stringWithFormat:@"%ld", (long)self.settings.maxAudioBitrate/1000];
        [av show];
    }
}

- (void)toggleDirectPlay:(UISwitch *)sw {
    self.settings.directPlay = sw.isOn;
    [self.table reloadData];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
