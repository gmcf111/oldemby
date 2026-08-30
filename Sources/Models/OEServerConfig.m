#import "OEServerConfig.h"
#import "Constants.h"
#import <UIKit/UIKit.h>

@implementation OEServerConfig

+ (instancetype)sharedConfig {
    static OEServerConfig *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[OEServerConfig alloc] init]; [s loadFromDefaults]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _deviceId = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        if (!_deviceId) {
            _deviceId = @"oldemby-32bit-device";
        }
    }
    return self;
}

- (void)loadFromDefaults {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    self.host = [d stringForKey:kDefaultsServerHost];
    self.userId = [d stringForKey:kDefaultsServerUserId];
    self.accessToken = [d stringForKey:kDefaultsServerToken];
    self.username = [d stringForKey:kDefaultsServerUsername];
}

- (void)saveToDefaults {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (self.host) [d setObject:self.host forKey:kDefaultsServerHost]; else [d removeObjectForKey:kDefaultsServerHost];
    if (self.userId) [d setObject:self.userId forKey:kDefaultsServerUserId]; else [d removeObjectForKey:kDefaultsServerUserId];
    if (self.accessToken) [d setObject:self.accessToken forKey:kDefaultsServerToken]; else [d removeObjectForKey:kDefaultsServerToken];
    if (self.username) [d setObject:self.username forKey:kDefaultsServerUsername]; else [d removeObjectForKey:kDefaultsServerUsername];
    [d synchronize];
}

- (void)clear {
    self.host = nil;
    self.userId = nil;
    self.accessToken = nil;
    self.username = nil;
    [self saveToDefaults];
}

- (BOOL)isLoggedIn {
    return self.host.length > 0 && self.accessToken.length > 0;
}

- (NSString *)baseURL {
    if (!self.host) return nil;
    NSString *u = self.host;
    // trim trailing /
    while ([u hasSuffix:@"/"] && u.length > 1) u = [u substringToIndex:u.length-1];
    return u;
}

@end
