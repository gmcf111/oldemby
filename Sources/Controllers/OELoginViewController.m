#import "OELoginViewController.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEServerConfig.h"
#import "Constants.h"
#import "Views/OETheme.h"

@interface OELoginViewController ()
@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UITextField *userField;
@property (nonatomic, strong) UITextField *passField;
@property (nonatomic, strong) UIButton *loginBtn;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation OELoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"连接 Emby";
    [OETheme prepareViewController:self];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:kNotificationThemeDidChange object:nil];

    // Prefill host if saved
    NSString *savedHost = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsServerHost];

    self.hostField = [self makeField:@"服务器地址，如 http://192.168.1.10:8096"];
    self.hostField.text = savedHost;
    self.hostField.keyboardType = UIKeyboardTypeURL;
    self.userField = [self makeField:@"用户名"];
    self.passField = [self makeField:@"密码"];
    self.passField.secureTextEntry = YES;
    [self.view addSubview:self.hostField];
    [self.view addSubview:self.userField];
    [self.view addSubview:self.passField];

    self.loginBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.loginBtn.backgroundColor = [OETheme accentColor];
    self.loginBtn.layer.cornerRadius = 7;
    self.loginBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.loginBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.loginBtn setTitle:@"登录" forState:UIControlStateNormal];
    [self.loginBtn addTarget:self action:@selector(doLogin) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.loginBtn];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.statusLabel];

    [self applyTheme];
}

- (UITextField *)makeField:(NSString *)placeholder {
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectZero];
    f.borderStyle = UITextBorderStyleRoundedRect;
    f.placeholder = placeholder;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.font = [UIFont systemFontOfSize:15];
    f.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    f.backgroundColor = [UIColor whiteColor];
    f.textColor = [UIColor darkTextColor];
    return f;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat x = 20;
    CGFloat fieldW = w - 2 * x;
    CGFloat y = 24;
    CGFloat fieldH = 40;
    CGFloat gap = 14;
    self.hostField.frame = CGRectMake(x, y, fieldW, fieldH);
    y += fieldH + gap;
    self.userField.frame = CGRectMake(x, y, fieldW, fieldH);
    y += fieldH + gap;
    self.passField.frame = CGRectMake(x, y, fieldW, fieldH);
    y += fieldH + 22;
    self.loginBtn.frame = CGRectMake(x, y, fieldW, 44);
    y += 44 + 12;
    self.statusLabel.frame = CGRectMake(x, y, fieldW, 60);
}

- (void)applyTheme {
    self.view.backgroundColor = [OETheme libraryBackgroundColor];
    self.statusLabel.textColor = [OETheme secondaryTextColor];
    if (self.navigationController) [OETheme applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)cancel {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)doLogin {
    NSString *host = [self.hostField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *user = [self.userField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *pass = self.passField.text ?: @"";
    if (!host.length || !user.length) {
        self.statusLabel.text = @"请填写服务器地址和用户名";
        return;
    }
    if (![host hasPrefix:@"http"]) host = [@"http://" stringByAppendingString:host];
    self.statusLabel.text = @"正在登录...";
    self.loginBtn.enabled = NO;

    [[OEEmbyAPIClient sharedClient] authenticateWithHost:host username:user password:pass completion:^(id result, NSError *error){
        self.loginBtn.enabled = YES;
        if (error) {
            self.statusLabel.text = [NSString stringWithFormat:@"登录失败: %@", error.localizedDescription];
            NSLog(@"[OldEmby] login error: %@", error);
        } else {
            self.statusLabel.text = @"登录成功";
            NSLog(@"[OldEmby] login ok token=%@", [[OEServerConfig sharedConfig] accessToken]);
            // Dismiss
            [self dismissViewControllerAnimated:YES completion:nil];
            // Notify library to reload
            [[NSNotificationCenter defaultCenter] postNotificationName:@"OEDidLoginNotification" object:nil];
        }
    }];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
