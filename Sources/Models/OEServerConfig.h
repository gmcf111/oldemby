#import <Foundation/Foundation.h>

@interface OEServerConfig : NSObject

@property (nonatomic, copy) NSString *host;      // e.g. http://192.168.1.10:8096
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, copy) NSString *deviceId;  // stable device id

+ (instancetype)sharedConfig;
- (void)loadFromDefaults;
- (void)saveToDefaults;
- (void)clear;

- (BOOL)isLoggedIn;
- (NSString *)baseURL; // host without trailing /

@end
