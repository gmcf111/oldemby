#import "OELoginViewController.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEServerConfig.h"

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
    self.view.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];

    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 80;
    self.hostField = [self makeField:@"服务器地址 http://IP:8096" y:y];
    y += 50;
    self.userField = [self makeField:@"用户名" y:y];
    y += 50;
    self.passField = [self makeField:@"密码" y:y];
    self.passField.secureTextEntry = YES;
    y += 70;

    self.loginBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.loginBtn.frame = CGRectMake(20, y, w-40, 44);
    [self.loginBtn setTitle:@"登录" forState:UIControlStateNormal];
    self.loginBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.loginBtn addTarget:self action:@selector(doLogin) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.loginBtn];
    y += 54;
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w-40, 40)];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textColor = [UIColor darkGrayColor];
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.statusLabel];

    // Prefill host if saved
    NSString *savedHost = [[NSUserDefaults standardUserDefaults] stringForKey:@"OEServerHost"];
    if (savedHost) self.hostField.text = savedHost;
}

- (UITextField *)makeField:(NSString *)placeholder y:(CGFloat)y {
    CGFloat w = self.view.bounds.size.width;
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(20, y, w-40, 40)];
    f.borderStyle = UITextBorderStyleRoundedRect;
    f.placeholder = placeholder;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:f];
    return f;
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

@end
