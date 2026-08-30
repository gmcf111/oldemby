#import "OEEmbyAPIClient.h"
#import "Models/OEServerConfig.h"
#import "Models/OETranscodeSettings.h"
#import "Services/OETranscodeBuilder.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

@interface OEEmbyAPIClient ()
@end

// iOS 6 has no modern URL query-item encoder.  Escape every character that
// can change query parsing (notably +, &, =, / and %) while retaining the
// unreserved URI characters.
static NSString *OEEncodeQueryComponent(NSString *value) {
    if (!value) return @"";
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                  (__bridge CFStringRef)value,
                                                                  NULL,
                                                                  CFSTR(":/?#[]@!$&'()*+,;=%"),
                                                                  kCFStringEncodingUTF8);
    if (!escaped) return @"";
    NSString *result = [(__bridge NSString *)escaped copy];
    CFRelease(escaped);
    return result;
}

@implementation OEEmbyAPIClient

+ (instancetype)sharedClient {
    static OEEmbyAPIClient *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[OEEmbyAPIClient alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
    }
    return self;
}

#pragma mark - Helpers

- (NSString *)baseURL {
    return [[OEServerConfig sharedConfig] baseURL];
}

- (NSDictionary *)authHeaders {
    OEServerConfig *c = [OEServerConfig sharedConfig];
    NSString *token = c.accessToken ?: @"";
    // Emby auth header - X-Emby-Authorization (new) + X-MediaBrowser-Token (legacy)
    NSString *deviceId = c.deviceId ?: @"oldemby-32bit";
    NSString *device = [[UIDevice currentDevice] name] ?: @"iPhone";
    NSString *appVersion = @"1.0.0";
    NSString *auth = [NSString stringWithFormat:@"MediaBrowser Client=\"OldEmby\", Device=\"%@\", DeviceId=\"%@\", Version=\"%@\"%@", device, deviceId, appVersion, token.length ? [@", Token=\"" stringByAppendingFormat:@"%@\"", token] : @""];
    NSMutableDictionary *h = [NSMutableDictionary dictionary];
    h[@"X-Emby-Authorization"] = auth;
    h[@"X-MediaBrowser-Token"] = token;
    h[@"Accept"] = @"application/json";
    h[@"Content-Type"] = @"application/json";
    return h;
}

- (NSURL *)urlForPath:(NSString *)path params:(NSDictionary *)params {
    NSString *base = [self baseURL];
    if (!base) return nil;
    NSString *full = [base stringByAppendingString:path];
    if (params.count) {
        NSMutableArray *parts = [NSMutableArray array];
        [params enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
            NSString *k = [key description];
            NSString *v = [obj description];
            // Simple percent escape (iOS6 compatible)
            NSString *ek = OEEncodeQueryComponent(k);
            NSString *ev = OEEncodeQueryComponent(v);
            [parts addObject:[NSString stringWithFormat:@"%@=%@", ek, ev]];
        }];
        full = [full stringByAppendingFormat:@"?%@", [parts componentsJoinedByString:@"&"]];
    }
    return [NSURL URLWithString:full];
}

- (void)sendRequest:(NSMutableURLRequest *)req completion:(OEAPICompletion)completion {
    // iOS6: NSURLConnection sendAsynchronousRequest:queue:completionHandler:
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err){
        if (err) { if (completion) completion(nil, err); return; }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
        NSInteger code = http.statusCode;
        if (code < 200 || code >= 300) {
            NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            NSError *e = [NSError errorWithDomain:@"OEEmbyAPI" code:code userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld: %@", (long)code, body]}];
            if (completion) completion(nil, e);
            return;
        }
        if (data.length == 0) { if (completion) completion(@{}, nil); return; }
        NSError *je = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
        if (je) { if (completion) completion(nil, je); return; }
        if (completion) completion(json, nil);
    }];
}

- (void)GET:(NSString *)path params:(NSDictionary *)params completion:(OEAPICompletion)completion {
    NSURL *url = [self urlForPath:path params:params];
    if (!url) { if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"No host configured"}]); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    [[self authHeaders] enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s){ [req setValue:v forHTTPHeaderField:k]; }];
    [self sendRequest:req completion:completion];
}

- (void)POST:(NSString *)path jsonBody:(NSDictionary *)body completion:(OEAPICompletion)completion {
    NSURL *url = [self urlForPath:path params:nil];
    if (!url) { if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"No host configured"}]); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [[self authHeaders] enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s){ [req setValue:v forHTTPHeaderField:k]; }];
    if (body) {
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    }
    [self sendRequest:req completion:completion];
}

#pragma mark - Auth

- (void)authenticateWithHost:(NSString *)host username:(NSString *)user password:(NSString *)pass completion:(OEAPICompletion)completion {
    OEServerConfig *cfg = [OEServerConfig sharedConfig];
    // Emby auth: POST /Users/AuthenticateByName
    NSDictionary *body = @{@"Username": user ?: @"", @"Pw": pass ?: @""};
    NSString *base = host;
    while ([base hasSuffix:@"/"] && base.length>1) base=[base substringToIndex:base.length-1];
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"/Users/AuthenticateByName"]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    // Minimal auth header without token
    NSString *deviceId = cfg.deviceId ?: @"oldemby-32bit";
    NSString *device = [[UIDevice currentDevice] name] ?: @"iPhone";
    NSString *auth = [NSString stringWithFormat:@"MediaBrowser Client=\"OldEmby\", Device=\"%@\", DeviceId=\"%@\", Version=\"1.0.0\"", device, deviceId];
    [req setValue:auth forHTTPHeaderField:@"X-Emby-Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [self sendRequest:req completion:^(id result, NSError *error){
        if (error) { if (completion) completion(nil, error); return; }
        // result contains User { Id } and AccessToken
        NSString *token = [result isKindOfClass:[NSDictionary class]] ? result[@"AccessToken"] : nil;
        NSDictionary *userDict = [result isKindOfClass:[NSDictionary class]] ? result[@"User"] : nil;
        NSString *uid = [userDict isKindOfClass:[NSDictionary class]] ? userDict[@"Id"] : nil;
        if (![uid isKindOfClass:[NSString class]] || !uid.length) {
            id fallbackId = [result isKindOfClass:[NSDictionary class]] ? result[@"Id"] : nil;
            uid = [fallbackId isKindOfClass:[NSString class]] ? fallbackId : nil;
        }
        if ([token isKindOfClass:[NSString class]] && token.length && [uid isKindOfClass:[NSString class]] && uid.length) {
            cfg.host = host;
            cfg.accessToken = token;
            cfg.userId = uid;
            cfg.username = user;
            // host already set
            [cfg saveToDefaults];
        }
        if (![token isKindOfClass:[NSString class]] || !token.length || ![uid isKindOfClass:[NSString class]] || !uid.length) {
            if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-3 userInfo:@{NSLocalizedDescriptionKey:@"Authentication response missing token or user ID"}]);
            return;
        }
        if (completion) completion(result, nil);
    }];
}

- (void)logout {
    [[OEServerConfig sharedConfig] clear];
}

#pragma mark - Browsing

// Shared parsing: extract Items array and build OEEmbyItem list (guards against non-dict responses)
- (void)parseItemsFromResult:(id)result completion:(OEAPICompletion)completion {
    NSArray *items = nil;
    if ([result isKindOfClass:[NSDictionary class]]) {
        id candidate = result[@"Items"];
        if ([candidate isKindOfClass:[NSArray class]]) items = candidate;
    }
    else if ([result isKindOfClass:[NSArray class]]) items = result;
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in items) {
        if ([d isKindOfClass:[NSDictionary class]]) [out addObject:[OEEmbyItem itemWithDictionary:d]];
    }
    if (completion) completion(out, nil);
}

- (void)fetchViewsWithCompletion:(OEAPICompletion)completion {
    OEServerConfig *c = [OEServerConfig sharedConfig];
    if (!c.userId) { if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Not logged in"}]); return; }
    NSString *path = [NSString stringWithFormat:@"/Users/%@/Views", c.userId];
    [self GET:path params:nil completion:^(id result, NSError *error){
        if (error) { if (completion) completion(nil, error); return; }
        [self parseItemsFromResult:result completion:completion];
    }];
}

- (void)fetchItemsInParent:(NSString *)parentId itemTypes:(NSString *)types startIndex:(NSInteger)start limit:(NSInteger)limit completion:(OEAPICompletion)completion {
    [self fetchItemsInParent:parentId itemTypes:types startIndex:start limit:limit sortBy:@"SortName" completion:completion];
}

- (void)fetchItemsInParent:(NSString *)parentId itemTypes:(NSString *)types startIndex:(NSInteger)start limit:(NSInteger)limit sortBy:(NSString *)sortBy completion:(OEAPICompletion)completion {
    [self fetchItemsInParent:parentId itemTypes:types startIndex:start limit:limit sortBy:sortBy recursive:YES completion:completion];
}

- (void)fetchItemsInParent:(NSString *)parentId itemTypes:(NSString *)types startIndex:(NSInteger)start limit:(NSInteger)limit sortBy:(NSString *)sortBy recursive:(BOOL)recursive completion:(OEAPICompletion)completion {
    OEServerConfig *c = [OEServerConfig sharedConfig];
    if (!c.userId) { if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Not logged in"}]); return; }
    NSString *path = [NSString stringWithFormat:@"/Users/%@/Items", c.userId];
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    if (parentId) p[@"ParentId"] = parentId;
    if (types) p[@"IncludeItemTypes"] = types;
    p[@"Fields"] = @"PrimaryImageAspectRatio,Overview,RunTimeTicks";
    p[@"ImageTypeLimit"] = @"1";
    p[@"StartIndex"] = @(start).stringValue;
    p[@"Limit"] = @(limit).stringValue;
    p[@"SortBy"] = sortBy.length ? sortBy : @"SortName";
    p[@"SortOrder"] = @"Ascending";
    p[@"Recursive"] = recursive ? @"true" : @"false";
    [self GET:path params:p completion:^(id result, NSError *error){
        if (error) { if (completion) completion(nil, error); return; }
        [self parseItemsFromResult:result completion:completion];
    }];
}

- (void)fetchSongsForArtist:(NSString *)artistId startIndex:(NSInteger)start limit:(NSInteger)limit completion:(OEAPICompletion)completion {
    OEServerConfig *c = [OEServerConfig sharedConfig];
    if (!c.userId) { if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Not logged in"}]); return; }
    NSString *path = [NSString stringWithFormat:@"/Users/%@/Items", c.userId];
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    p[@"IncludeItemTypes"] = @"Audio";
    p[@"ArtistIds"] = artistId ?: @"";
    p[@"Fields"] = @"PrimaryImageAspectRatio,Overview,RunTimeTicks";
    p[@"ImageTypeLimit"] = @"1";
    p[@"StartIndex"] = @(start).stringValue;
    p[@"Limit"] = @(limit).stringValue;
    p[@"SortBy"] = @"Album,ParentIndexNumber,IndexNumber";
    p[@"SortOrder"] = @"Ascending";
    p[@"Recursive"] = @"true";
    [self GET:path params:p completion:^(id result, NSError *error){
        if (error) { if (completion) completion(nil, error); return; }
        [self parseItemsFromResult:result completion:completion];
    }];
}

#pragma mark - Playback

- (void)fetchPlaybackInfoForItem:(NSString *)itemId isAudio:(BOOL)isAudio completion:(OEAPICompletion)completion {
    OEServerConfig *c = [OEServerConfig sharedConfig];
    OETranscodeSettings *s = [OETranscodeSettings sharedSettings];
    NSDictionary *body = [OETranscodeBuilder playbackInfoBodyForItemId:itemId userId:c.userId settings:s isAudio:isAudio];
    NSString *path = [NSString stringWithFormat:@"/Items/%@/PlaybackInfo", itemId];
    [self POST:path jsonBody:body completion:completion];
}

- (void)fetchStreamURLForItem:(NSString *)itemId isAudio:(BOOL)isAudio completion:(OEAPICompletion)completion {
    [self fetchPlaybackInfoForItem:itemId isAudio:isAudio completion:^(id result, NSError *error){
        if (error) { if (completion) completion(nil, error); return; }
        if (![result isKindOfClass:[NSDictionary class]]) {
            if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"Invalid PlaybackInfo response"}]);
            return;
        }
        NSString *msId = nil;
        NSString *url = [OETranscodeBuilder streamURLFromPlaybackInfoResponse:result itemId:itemId isAudio:isAudio host:[self baseURL] mediaSourceId:&msId];
        if (!url) { if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"No stream URL in PlaybackInfo"}]); return; }
        // Append transcode query if needed and URL not already contains it
        OETranscodeSettings *s = [OETranscodeSettings sharedSettings];
        if (!s.directPlay && [url rangeOfString:@"VideoCodec=" options:NSCaseInsensitiveSearch].location == NSNotFound && [url rangeOfString:@"AudioCodec=" options:NSCaseInsensitiveSearch].location == NSNotFound) {
            // A server may return a generic URL containing Static=true even
            // when the profile requested transcoding.  Replace that flag
            // before adding codec parameters instead of sending contradictory
            // duplicate query keys.
            url = [url stringByReplacingOccurrencesOfString:@"Static=true" withString:@"Static=false"];
            url = [url stringByReplacingOccurrencesOfString:@"static=true" withString:@"static=false"];
            NSString *qs = [OETranscodeBuilder transcodeQueryStringForSettings:s isAudio:isAudio];
            NSString *sep = [url rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&";
            // Emby stream endpoint also needs api_key? For direct stream, token via header is ok, but append if needed
            NSString *token = [OEServerConfig sharedConfig].accessToken;
            NSString *escapedToken = OEEncodeQueryComponent(token);
            NSString *extra = [NSString stringWithFormat:@"%@%@&api_key=%@", sep, qs, escapedToken ?: @""];
            url = [url stringByAppendingString:extra];
        } else if (s.directPlay) {
            // In direct play, ensure Static=true if a fallback or media source stream URL was used
            url = [url stringByReplacingOccurrencesOfString:@"Static=false" withString:@"Static=true"];
            url = [url stringByReplacingOccurrencesOfString:@"static=false" withString:@"static=true"];
            // Ensure api_key for direct
            if ([url rangeOfString:@"api_key" options:NSCaseInsensitiveSearch].location == NSNotFound) {
                NSString *token = [OEServerConfig sharedConfig].accessToken;
                NSString *escapedToken = OEEncodeQueryComponent(token);
                NSString *sep = [url rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&";
                url = [url stringByAppendingFormat:@"%@api_key=%@", sep, escapedToken ?: @""];
            }
        }
        // Some Emby versions omit the token from an explicit
        // TranscodingUrl.  Movie/AVPlayer cannot send our custom headers, so
        // ensure every returned playback URL is independently authenticated.
        NSString *token = [OEServerConfig sharedConfig].accessToken;
        if (token.length && [url rangeOfString:@"api_key=" options:NSCaseInsensitiveSearch].location == NSNotFound) {
            NSString *sep = [url rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&";
            url = [url stringByAppendingFormat:@"%@api_key=%@", sep, OEEncodeQueryComponent(token)];
        }
        if (completion) completion(url, nil);
    }];
}

- (NSString *)imageURLForItem:(OEEmbyItem *)item width:(NSInteger)width {
    NSString *url = [item primaryImageURLWithHost:[self baseURL] maxWidth:width];
    NSString *token = [OEServerConfig sharedConfig].accessToken;
    if (!url.length || !token.length) return url;
    // ImageCache uses a plain NSURLConnection, so authenticate image
    // requests through Emby's api_key query parameter.
    NSString *escaped = OEEncodeQueryComponent(token);
    return [url stringByAppendingFormat:@"&api_key=%@", escaped ?: @""];
}

@end
