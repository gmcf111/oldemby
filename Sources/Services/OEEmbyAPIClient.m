#import "OEEmbyAPIClient.h"
#import "Models/OEServerConfig.h"
#import "Models/OETranscodeSettings.h"
#import "Models/OECastItem.h"
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

// Emby may return transcoding URLs that contain raw file-name bytes.  iOS 6-9
// NSURL rejects several of those characters, so retain only URI-safe bytes.
// Existing %XX escapes are preserved to avoid double encoding server URLs.
// Note '[' and ']' are intentionally escaped: iOS 6's CFURL parses strictly
// per RFC 3986, where those bytes are only legal inside an IPv6 host - left
// raw in a path or query they make URLWithString: return nil, which surfaced
// to the user as "invalid playback URL".
static NSString *OEEscapeIllegalURLCharacters(NSString *urlString) {
    if (urlString.length == 0) return urlString;
    NSData *bytes = [urlString dataUsingEncoding:NSUTF8StringEncoding];
    if (!bytes) return urlString;
    const unsigned char *raw = (const unsigned char *)bytes.bytes;
    NSMutableString *out = [NSMutableString stringWithCapacity:urlString.length * 2];
    for (NSUInteger i = 0; i < bytes.length; i++) {
        unsigned char c = raw[i];
        BOOL isAlphaNumeric = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
        BOOL isEscapedByte = c == '%' && i + 2 < bytes.length &&
            ((raw[i + 1] >= '0' && raw[i + 1] <= '9') || (raw[i + 1] >= 'A' && raw[i + 1] <= 'F') || (raw[i + 1] >= 'a' && raw[i + 1] <= 'f')) &&
            ((raw[i + 2] >= '0' && raw[i + 2] <= '9') || (raw[i + 2] >= 'A' && raw[i + 2] <= 'F') || (raw[i + 2] >= 'a' && raw[i + 2] <= 'f'));
        BOOL isURISafe = isAlphaNumeric || c == '-' || c == '.' || c == '_' || c == '~' ||
            c == '!' || c == '$' || c == '&' || c == '\'' || c == '(' || c == ')' ||
            c == '*' || c == '+' || c == ',' || c == ';' || c == '=' || c == ':' ||
            c == '@' || c == '/' || c == '?' || isEscapedByte;
        if (isURISafe) [out appendFormat:@"%c", c];
        else [out appendFormat:@"%%%02X", c];
    }
    return out;
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

- (void)DELETE:(NSString *)path completion:(OEAPICompletion)completion {
    NSURL *url = [self urlForPath:path params:nil];
    if (!url) { if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"No host configured"}]); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"DELETE";
    [[self authHeaders] enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s){ [req setValue:v forHTTPHeaderField:k]; }];
    [self sendRequest:req completion:completion];
}

#pragma mark - Favorites

- (void)setItem:(NSString *)itemId favorite:(BOOL)favorite completion:(OEAPICompletion)completion {
    OEServerConfig *c = [OEServerConfig sharedConfig];
    if (!c.userId.length || !itemId.length) { if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Not logged in"}]); return; }
    NSString *path = [NSString stringWithFormat:@"/Users/%@/FavoriteItems/%@", c.userId, itemId];
    if (favorite) [self POST:path jsonBody:@{} completion:completion];
    else [self DELETE:path completion:completion];
}

#pragma mark - Auth

- (void)authenticateWithHost:(NSString *)host username:(NSString *)user password:(NSString *)pass completion:(OEAPICompletion)completion {
    OEServerConfig *cfg = [OEServerConfig sharedConfig];
    // Emby auth: POST /Users/AuthenticateByName
    NSDictionary *body = @{@"Username": user ?: @"", @"Pw": pass ?: @""};
    NSString *base = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Normalize before the request AND before persisting: a host without a
    // scheme makes every later playback URL unparseable.
    NSString *lowerBase = [base lowercaseString];
    if (base.length && ![lowerBase hasPrefix:@"http://"] && ![lowerBase hasPrefix:@"https://"]) {
        base = [@"http://" stringByAppendingString:base];
    }
    while ([base hasSuffix:@"/"] && base.length>1) base=[base substringToIndex:base.length-1];
    NSString *normalizedHost = base;
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
            cfg.host = normalizedHost;
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
    // PrimaryImageAspectRatio lets the library home draw the full-width cover
    // at the item's real aspect ratio.
    NSDictionary *params = @{@"Fields": @"PrimaryImageAspectRatio", @"ImageTypeLimit": @"1"};
    [self GET:path params:params completion:^(id result, NSError *error){
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
    [self fetchItemsInParent:parentId itemTypes:types startIndex:start limit:limit sortBy:sortBy sortOrder:@"Ascending" recursive:recursive completion:completion];
}

- (void)fetchItemsInParent:(NSString *)parentId itemTypes:(NSString *)types startIndex:(NSInteger)start limit:(NSInteger)limit sortBy:(NSString *)sortBy sortOrder:(NSString *)sortOrder recursive:(BOOL)recursive completion:(OEAPICompletion)completion {
    OEServerConfig *c = [OEServerConfig sharedConfig];
    if (!c.userId) { if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Not logged in"}]); return; }
    NSString *path = [NSString stringWithFormat:@"/Users/%@/Items", c.userId];
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    if (parentId) p[@"ParentId"] = parentId;
    if (types) p[@"IncludeItemTypes"] = types;
    p[@"Fields"] = @"PrimaryImageAspectRatio,Overview,RunTimeTicks,MediaStreams,SeriesPrimaryImageTag,SeriesId";
    p[@"ImageTypeLimit"] = @"1";
    p[@"StartIndex"] = @(start).stringValue;
    p[@"Limit"] = @(limit).stringValue;
    p[@"SortBy"] = sortBy.length ? sortBy : @"SortName";
    p[@"SortOrder"] = sortOrder.length ? sortOrder : @"Ascending";
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
    p[@"Fields"] = @"PrimaryImageAspectRatio,Overview,RunTimeTicks,MediaStreams";
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

- (void)fetchSeasonsForSeries:(NSString *)seriesId completion:(OEAPICompletion)completion {
    OEServerConfig *c = [OEServerConfig sharedConfig];
    if (!c.userId) { if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Not logged in"}]); return; }
    NSString *path = [NSString stringWithFormat:@"/Shows/%@/Seasons", seriesId];
    NSDictionary *params = @{@"UserId": c.userId,
                             @"Fields": @"PrimaryImageAspectRatio,Overview,RunTimeTicks,SeriesPrimaryImageTag,SeriesId",
                             @"ImageTypeLimit": @"1"};
    [self GET:path params:params completion:^(id result, NSError *error){
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
        // Append transcode query if needed and URL not already contains it.
        // A server-generated HLS TranscodingUrl (master.m3u8) already carries
        // every parameter and must not be rewritten.
        OETranscodeSettings *s = [OETranscodeSettings sharedSettings];
        BOOL isHLSURL = [url rangeOfString:@".m3u8" options:NSCaseInsensitiveSearch].location != NSNotFound;
        if (!s.directPlay && !isHLSURL && [url rangeOfString:@"VideoCodec=" options:NSCaseInsensitiveSearch].location == NSNotFound && [url rangeOfString:@"AudioCodec=" options:NSCaseInsensitiveSearch].location == NSNotFound) {
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
        // Final gate: hand the player only URLs NSURL can actually parse.
        // iOS 6's CFURL is stricter than modern NSURL; if the byte-level
        // escape above still leaves something it rejects, fall back to the
        // system's own escaping routine before giving up.
        NSString *finalURL = OEEscapeIllegalURLCharacters(url);
        if (![NSURL URLWithString:finalURL]) {
            CFStringRef recovered = CFURLCreateStringByAddingPercentEscapes(NULL,
                (__bridge CFStringRef)url, NULL,
                CFSTR(" \t\r\n\"<>\\^`{}[]|"), kCFStringEncodingUTF8);
            NSString *recoveredURL = recovered ? [(__bridge NSString *)recovered copy] : nil;
            if (recovered) CFRelease(recovered);
            if (recoveredURL.length && [NSURL URLWithString:recoveredURL]) finalURL = recoveredURL;
        }
        NSLog(@"[OldEmby] playback URL for %@: %@", itemId, finalURL);
        // Only reject what NSURL genuinely cannot turn into a URL object.
        // Do NOT additionally require scheme/host here: that check once
        // rejected perfectly playable audio URLs and broke music playback.
        if (![NSURL URLWithString:finalURL]) {
            if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"服务器返回的播放地址无法解析：%@", url]}]);
            return;
        }
        if (completion) completion(finalURL, nil);
    }];
}

- (void)fetchDirectStreamURLForItem:(NSString *)itemId isAudio:(BOOL)isAudio completion:(OEAPICompletion)completion {
    // Build a PlaybackInfo body with a direct-play (no transcode) profile so
    // the server returns the original file URL with Static=true.  This is
    // independent of the global transcode setting in OETranscodeSettings.
    OEServerConfig *c = [OEServerConfig sharedConfig];
    OETranscodeSettings *direct = [OETranscodeSettings defaultSettings];
    direct.directPlay = YES;
    NSDictionary *body = [OETranscodeBuilder playbackInfoBodyForItemId:itemId userId:c.userId settings:direct isAudio:isAudio];
    NSString *path = [NSString stringWithFormat:@"/Items/%@/PlaybackInfo", itemId];
    [self POST:path jsonBody:body completion:^(id result, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        if (![result isKindOfClass:[NSDictionary class]]) {
            if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"Invalid PlaybackInfo response"}]);
            return;
        }
        // Extract the MediaSourceId, container, and the direct stream URL
        // directly from the PlaybackInfo response.  We intentionally do NOT
        // call streamURLFromPlaybackInfoResponse here because that class method
        // reads the *global* OETranscodeSettings (which may be in transcode
        // mode) to decide which URL to build.
        NSArray *sources = result[@"MediaSources"];
        if (![sources isKindOfClass:[NSArray class]] || sources.count == 0) {
            if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"No media sources in PlaybackInfo"}]);
            return;
        }
        NSString *msId = nil;
        NSString *url = nil;
        NSString *container = nil;
        BOOL supportsDirectPlay = NO;
        for (NSDictionary *candidate in sources) {
            if (![candidate isKindOfClass:[NSDictionary class]]) continue;
            id dsUrl = candidate[@"DirectStreamUrl"];
            if ([dsUrl isKindOfClass:[NSString class]] && [dsUrl length]) {
                url = dsUrl;
                msId = [candidate[@"Id"] isKindOfClass:[NSString class]] ? candidate[@"Id"] : msId;
                container = [candidate[@"Container"] isKindOfClass:[NSString class]] ? [candidate[@"Container"] lowercaseString] : nil;
                supportsDirectPlay = [candidate[@"SupportsDirectPlay"] boolValue];
                break;
            }
            if (!msId) msId = [candidate[@"Id"] isKindOfClass:[NSString class]] ? candidate[@"Id"] : nil;
            if (!container) container = [candidate[@"Container"] isKindOfClass:[NSString class]] ? [candidate[@"Container"] lowercaseString] : nil;
        }
        // Check if the container is one iOS 6 MPMoviePlayer can natively play.
        // MKV, AVI, WMV, FLV etc. will crash or produce -11828 errors.  Only
        // mp4, mov, m4v, ts (MPEG-TS) are safe for direct playback.
        NSString *lowerURL = url ? [url lowercaseString] : @"";
        BOOL containerSupported = NO;
        if (container.length) {
            static NSArray *supported = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{ supported = @[@"mp4", @"mov", @"m4v", @"ts", @"mpeg", @"mpg"]; });
            for (NSString *s in supported) {
                if ([container containsString:s]) { containerSupported = YES; break; }
            }
        }
        // Also check the URL file extension as a fallback.
        if (!containerSupported) {
            static NSArray *supportedExt = nil;
            static dispatch_once_t onceToken2;
            dispatch_once(&onceToken2, ^{ supportedExt = @[@".mp4", @".mov", @".m4v", @".ts", @".mpeg", @".mpg"]; });
            for (NSString *ext in supportedExt) {
                if ([lowerURL containsString:ext]) { containerSupported = YES; break; }
            }
        }
        if (!containerSupported) {
            if (isAudio) {
                // Audio: also check common audio containers
                static NSArray *audioExt = nil;
                static dispatch_once_t onceToken3;
                dispatch_once(&onceToken3, ^{ audioExt = @[@".mp3", @".aac", @".m4a", @".wav", @".flac"]; });
                for (NSString *ext in audioExt) {
                    if ([lowerURL containsString:ext]) { containerSupported = YES; break; }
                }
            }
        }
        if (!containerSupported) {
            NSString *fmtName = container.length ? container.uppercaseString : @"未知格式";
            NSString *msg = [NSString stringWithFormat:@"该视频为 %@ 格式，iOS 6 系统播放器无法直接播放。请使用上方的转码播放按钮。", fmtName];
            if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-3 userInfo:@{NSLocalizedDescriptionKey:msg}]);
            return;
        }
        // Also check the video codec: even an mp4 container may hold a
        // codec that iOS 6 MPMoviePlayer cannot decode (H.265/HEVC, VP9,
        // AV1).  Playing such a file directly causes the system player to
        // throw an NSInvalidArgumentException from a delayed-perform
        // callback, which aborts the process.  Reject these early so the
        // user is guided to the transcode button instead.
        if (!isAudio) {
            NSString *videoCodec = nil;
            for (NSDictionary *candidate in sources) {
                if (![candidate isKindOfClass:[NSDictionary class]]) continue;
                NSArray *streams = candidate[@"MediaStreams"];
                if (![streams isKindOfClass:[NSArray class]]) continue;
                for (NSDictionary *stream in streams) {
                    if (![stream isKindOfClass:[NSDictionary class]]) continue;
                    NSString *type = [stream[@"Type"] isKindOfClass:[NSString class]] ? stream[@"Type"] : @"";
                    if (![type isEqualToString:@"Video"]) continue;
                    videoCodec = [stream[@"Codec"] isKindOfClass:[NSString class]] ? [stream[@"Codec"] lowercaseString] : nil;
                    if (videoCodec.length) break;
                }
                if (videoCodec.length) break;
            }
            if (videoCodec.length) {
                static NSArray *unsupportedCodecs = nil;
                static dispatch_once_t onceTokenCodec;
                dispatch_once(&onceTokenCodec, ^{
                    unsupportedCodecs = @[@"hevc", @"h265", @"h.265", @"vp9", @"vp09", @"av1", @"av01", @"vvc", @"h266", @"h.266"];
                });
                for (NSString *bad in unsupportedCodecs) {
                    if ([videoCodec isEqualToString:bad] || [videoCodec containsString:bad]) {
                        NSString *msg = [NSString stringWithFormat:@"该视频使用 %@ 编码，iOS 6 系统播放器不支持直接播放此编码。请使用上方的转码播放按钮。", videoCodec.uppercaseString];
                        if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-4 userInfo:@{NSLocalizedDescriptionKey:msg}]);
                        return;
                    }
                }
            }
        }
        // If no DirectStreamUrl was provided, build the canonical stream
        // endpoint ourselves with Static=true (no transcoding).
        if (!url.length) {
            NSString *resource = isAudio ? @"Audio" : @"Videos";
            NSString *msParam = msId.length ? [NSString stringWithFormat:@"MediaSourceId=%@&", msId] : @"";
            url = [NSString stringWithFormat:@"/%@/%@/stream?%@Static=true", resource, itemId, msParam];
        }
        // Ensure the URL is absolute.
        if (![url hasPrefix:@"http"]) {
            NSString *base = [self baseURL];
            if (!base.length) {
                if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"No host configured"}]);
                return;
            }
            while ([base hasSuffix:@"/"] && base.length > 1) base = [base substringToIndex:base.length - 1];
            if (![url hasPrefix:@"/"]) url = [@"/" stringByAppendingString:url];
            if ([base hasSuffix:@"/emby"] && [url hasPrefix:@"/emby/"]) url = [url substringFromIndex:5];
            url = [base stringByAppendingString:url];
        }
        // Force Static=true so the server hands back the original file.
        url = [url stringByReplacingOccurrencesOfString:@"Static=false" withString:@"Static=true"];
        url = [url stringByReplacingOccurrencesOfString:@"static=false" withString:@"static=true"];
        // Ensure the URL carries the api_key for direct file access.
        NSString *token = [OEServerConfig sharedConfig].accessToken;
        if (token.length && [url rangeOfString:@"api_key=" options:NSCaseInsensitiveSearch].location == NSNotFound) {
            NSString *sep = [url rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&";
            url = [url stringByAppendingFormat:@"%@api_key=%@", sep, OEEncodeQueryComponent(token)];
        }
        NSString *finalURL = OEEscapeIllegalURLCharacters(url);
        if (![NSURL URLWithString:finalURL]) {
            CFStringRef recovered = CFURLCreateStringByAddingPercentEscapes(NULL,
                (__bridge CFStringRef)url, NULL,
                CFSTR(" \t\r\n\"<>\\^`{}[]|"), kCFStringEncodingUTF8);
            NSString *recoveredURL = recovered ? [(__bridge NSString *)recovered copy] : nil;
            if (recovered) CFRelease(recovered);
            if (recoveredURL.length && [NSURL URLWithString:recoveredURL]) finalURL = recoveredURL;
        }
        NSLog(@"[OldEmby] direct stream URL for %@: %@", itemId, finalURL);
        if (![NSURL URLWithString:finalURL]) {
            if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-2 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"直接播放地址无法解析：%@", url]}]);
            return;
        }
        if (completion) completion(finalURL, nil);
    }];
}

- (void)GETText:(NSString *)path completion:(OEAPICompletion)completion {
    NSURL *url = [self urlForPath:path params:nil];
    if (!url) {
        if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"No host configured"}]);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    [[self authHeaders] enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];
    [request setValue:@"text/plain, text/srt, text/vtt, text/ass, text/x-ssa, application/octet-stream" forHTTPHeaderField:@"Accept"];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode < 200 || http.statusCode >= 300) {
            NSError *statusError = [NSError errorWithDomain:@"OEEmbyAPI" code:http.statusCode userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"HTTP %ld while reading text stream", (long)http.statusCode]}];
            if (completion) completion(nil, statusError);
            return;
        }
        NSString *text = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
        if (completion) completion(text ?: @"", nil);
    }];
}

- (BOOL)lyricsResponseHasContent:(id)result {
    if (![result isKindOfClass:[NSDictionary class]]) return NO;
    id lyrics = result[@"Lyrics"];
    if ([lyrics isKindOfClass:[NSArray class]]) return [lyrics count] > 0;
    for (NSString *key in @[@"Text", @"LyricsText", @"Lyrics"]) {
        id value = result[key];
        if ([value isKindOfClass:[NSString class]] && [value length]) return YES;
    }
    return NO;
}

- (NSDictionary *)mediaSourceWithEmbeddedLyricsForItem:(OEEmbyItem *)item playbackInfo:(NSDictionary *)playbackInfo {
    NSArray *sources = playbackInfo[@"MediaSources"];
    for (id source in sources) {
        if (![source isKindOfClass:[NSDictionary class]]) continue;
        NSArray *streams = source[@"MediaStreams"];
        for (id stream in streams) {
            if (![stream isKindOfClass:[NSDictionary class]]) continue;
            NSInteger index = [stream[@"Index"] respondsToSelector:@selector(integerValue)] ? [stream[@"Index"] integerValue] : NSNotFound;
            NSString *type = [stream[@"Type"] isKindOfClass:[NSString class]] ? stream[@"Type"] : @"";
            NSString *codec = [stream[@"Codec"] isKindOfClass:[NSString class]] ? [stream[@"Codec"] lowercaseString] : @"";
            BOOL knownTextCodec = [@[@"lrc", @"srt", @"subrip", @"vtt", @"webvtt", @"ass", @"ssa", @"subviewer", @"microdvd", @"sub"] containsObject:codec];
            if (index == item.embeddedLyricsStreamIndex && [type isEqualToString:@"Subtitle"] && ([stream[@"IsTextSubtitleStream"] boolValue] || knownTextCodec)) return source;
        }
    }
    return nil;
}

- (void)fetchEmbeddedLyricsForItem:(OEEmbyItem *)item completion:(OEAPICompletion)completion {
    if (item.embeddedLyricsStreamIndex == NSNotFound || !item.embeddedLyricsFormat.length) {
        if (completion) completion(@"", nil);
        return;
    }
    // Request a fresh PlaybackInfo rather than trusting a list response: its
    // MediaSources contain the authoritative ID required by the subtitle
    // stream endpoint. This request must not alter the active audio player.
    [self fetchPlaybackInfoForItem:item.itemId isAudio:YES completion:^(id result, NSError *error) {
        if (error || ![result isKindOfClass:[NSDictionary class]]) {
            if (completion) completion(@"", nil);
            return;
        }
        NSDictionary *source = [self mediaSourceWithEmbeddedLyricsForItem:item playbackInfo:result];
        NSString *mediaSourceId = [source[@"Id"] isKindOfClass:[NSString class]] ? source[@"Id"] : nil;
        if (!mediaSourceId.length) {
            if (completion) completion(@"", nil);
            return;
        }
        NSString *path = [NSString stringWithFormat:@"/Items/%@/%@/Subtitles/%ld/Stream.%@",
                          OEEncodeQueryComponent(item.itemId), OEEncodeQueryComponent(mediaSourceId),
                          (long)item.embeddedLyricsStreamIndex, OEEncodeQueryComponent(item.embeddedLyricsFormat)];
        [self GETText:path completion:^(id text, NSError *textError) {
            // Lyrics are optional. A missing/unsupported embedded stream must
            // never turn into a music playback error.
            if (completion) completion(textError ? @"" : (text ?: @""), nil);
        }];
    }];
}

- (void)fetchLyricsForAudioItem:(OEEmbyItem *)item completion:(OEAPICompletion)completion {
    if (!item.itemId.length) {
        if (completion) completion(@"", nil);
        return;
    }
    [self fetchLyricsForItem:item.itemId completion:^(id result, NSError *error) {
        if (!error && [self lyricsResponseHasContent:result]) {
            if (completion) completion(result, nil);
            return;
        }
        [self fetchEmbeddedLyricsForItem:item completion:completion];
    }];
}

- (void)fetchLyricsForItem:(NSString *)itemId completion:(OEAPICompletion)completion {
    if (!itemId.length) {
        if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Missing audio item ID"}]);
        return;
    }
    // Emby 4.x uses /Audio/{id}/Lyrics; several older releases use the
    // generic item route. Treat only a 404 as a compatibility fallback.
    NSString *audioPath = [NSString stringWithFormat:@"/Audio/%@/Lyrics", itemId];
    [self GET:audioPath params:nil completion:^(id result, NSError *error) {
        if (!error || error.code != 404) {
            if (completion) completion(result, error);
            return;
        }
        NSString *itemPath = [NSString stringWithFormat:@"/Items/%@/Lyrics", itemId];
        [self GET:itemPath params:nil completion:completion];
    }];
}

#pragma mark - Media Sources

- (void)fetchMediaSourcesForItem:(NSString *)itemId completion:(OEAPICompletion)completion {
    if (!itemId.length) {
        if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Missing item ID"}]);
        return;
    }
    // Request PlaybackInfo with a direct-play profile so the server returns
    // the original MediaSources with full stream metadata (codec, resolution,
    // channels, bitrate, etc.).  The transcode settings used here should not
    // affect which MediaSources are returned — only which URL is selected.
    OEServerConfig *c = [OEServerConfig sharedConfig];
    OETranscodeSettings *direct = [OETranscodeSettings defaultSettings];
    direct.directPlay = YES;
    NSDictionary *body = [OETranscodeBuilder playbackInfoBodyForItemId:itemId userId:c.userId settings:direct isAudio:NO];
    NSString *path = [NSString stringWithFormat:@"/Items/%@/PlaybackInfo", itemId];
    [self POST:path jsonBody:body completion:^(id result, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        if (![result isKindOfClass:[NSDictionary class]]) {
            if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"Invalid PlaybackInfo response"}]);
            return;
        }
        NSArray *sources = result[@"MediaSources"];
        if (![sources isKindOfClass:[NSArray class]]) {
            // Some Emby versions embed MediaSources directly in the item detail.
            // Try fetching via the user-scoped item endpoint as a fallback.
            NSString *itemPath = [NSString stringWithFormat:@"/Users/%@/Items/%@", c.userId ?: @"", itemId];
            NSDictionary *params = @{@"Fields": @"MediaSources"};
            [self GET:itemPath params:params completion:^(id r2, NSError *e2) {
                if (e2 || ![r2 isKindOfClass:[NSDictionary class]]) {
                    if (completion) completion(@[], nil);
                    return;
                }
                NSArray *altSources = r2[@"MediaSources"];
                if (![altSources isKindOfClass:[NSArray class]]) altSources = @[];
                if (completion) completion(altSources, nil);
            }];
            return;
        }
        if (completion) completion(sources, nil);
    }];
}

#pragma mark - Subtitles

- (void)fetchSubtitleForItem:(NSString *)itemId
              mediaSourceId:(NSString *)mediaSourceId
                streamIndex:(NSInteger)streamIndex
                     format:(NSString *)format
                 completion:(OEAPICompletion)completion {
    if (!itemId.length || !mediaSourceId.length) {
        if (completion) completion(@"", [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Missing item or media source ID for subtitle fetch"}]);
        return;
    }
    // Default to SRT format — Emby's subtitle stream endpoint transcodes
    // compatible text tracks (ASS, VTT, etc.) to SRT on the fly.
    NSString *fmt = format.length ? format : @"srt";
    // /Videos/… is the route Emby's SubtitleService has always declared;
    // /Items/… is an alias only newer builds answer, so try the canonical one
    // first and fall back on a 404/405 from an older or stricter server.
    NSString *videosPath = [NSString stringWithFormat:@"/Videos/%@/%@/Subtitles/%ld/Stream.%@",
                            OEEncodeQueryComponent(itemId),
                            OEEncodeQueryComponent(mediaSourceId),
                            (long)streamIndex,
                            OEEncodeQueryComponent(fmt)];
    NSString *itemsPath = [NSString stringWithFormat:@"/Items/%@/%@/Subtitles/%ld/Stream.%@",
                           OEEncodeQueryComponent(itemId),
                           OEEncodeQueryComponent(mediaSourceId),
                           (long)streamIndex,
                           OEEncodeQueryComponent(fmt)];
    [self GETText:videosPath completion:^(id text, NSError *error) {
        BOOL usable = !error && [text isKindOfClass:[NSString class]] && [text length];
        if (usable) {
            if (completion) completion(text, nil);
            return;
        }
        NSLog(@"[OldEmby] subtitle via /Videos failed (%@), retrying /Items",
              error ? error.localizedDescription : @"empty body");
        [self GETText:itemsPath completion:completion];
    }];
}

#pragma mark - Stream URL with Audio/Subtitle Index

- (NSString *)streamURLWithAudioIndex:(NSInteger)audioIndex
                        subtitleIndex:(NSInteger)subtitleIndex
                         fromBaseURL:(NSString *)baseStreamURL
                                itemId:(NSString *)itemId {
    if (!baseStreamURL.length) return nil;

    NSMutableString *url = [baseStreamURL mutableCopy];
    if (audioIndex >= 0) {
        // Remove any existing AudioStreamIndex parameter to avoid duplicates.
        url = [self removeQueryParam:url key:@"AudioStreamIndex"];
        NSString *sep = [url rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&";
        [url appendFormat:@"%@AudioStreamIndex=%ld", sep, (long)audioIndex];
    }
    if (subtitleIndex >= 0) {
        url = [self removeQueryParam:url key:@"SubtitleStreamIndex"];
        NSString *sep = [url rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&";
        [url appendFormat:@"%@SubtitleStreamIndex=%ld", sep, (long)subtitleIndex];
        // Also set SubtitleMethod=Encode so the server burns-in image subs;
        // for text subs the server will deliver them as part of the HLS if
        // the profile requests it, or as an external endpoint we fetch.
        url = [self removeQueryParam:url key:@"SubtitleMethod"];
        sep = [url rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&";
        [url appendFormat:@"%@SubtitleMethod=Encode", sep];
    } else {
        // A negative index means "no server-side subtitles". Any leftover
        // parameters must go, or the server keeps burning the previous track
        // into the video underneath the locally drawn overlay.
        url = [self removeQueryParam:url key:@"SubtitleStreamIndex"];
        url = [self removeQueryParam:url key:@"SubtitleMethod"];
    }
    return OEEscapeIllegalURLCharacters(url);
}

- (NSMutableString *)removeQueryParam:(NSMutableString *)url key:(NSString *)key {
    // Remove existing key=value& from the query string to avoid duplicates.
    NSString *pattern = [NSString stringWithFormat:@"%@=", key];
    NSRange searchRange = NSMakeRange(0, url.length);
    NSRange found = [url rangeOfString:pattern options:NSCaseInsensitiveSearch range:searchRange];
    if (found.location == NSNotFound) return url;
    // Find the end of this param value (next & or end of string).
    NSUInteger valueStart = NSMaxRange(found);
    NSUInteger end = valueStart;
    while (end < url.length) {
        unichar c = [url characterAtIndex:end];
        if (c == '&') break;
        end++;
    }
    // Also consume the preceding & if the param is not the first query key.
    NSUInteger removeStart = found.location;
    if (removeStart > 0 && [url characterAtIndex:removeStart - 1] == '&') {
        removeStart--;
    } else if (end < url.length && [url characterAtIndex:end] == '&') {
        // Consume trailing &
        end++;
    }
    [url deleteCharactersInRange:NSMakeRange(removeStart, end - removeStart)];
    return url;
}

#pragma mark - Casts

- (void)fetchCastsForItem:(NSString *)itemId completion:(OEAPICompletion)completion {
    if (!itemId.length) {
        if (completion) completion(nil, [NSError errorWithDomain:@"OEEmbyAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Missing item ID"}]);
        return;
    }
    // Emby: GET /Users/{UserId}/Items/{Id}?Fields=People returns the item with
    // a People array.  The user-scoped path is required because the bare
    // /Items/{Id} endpoint on many Emby versions omits People (it only
    // returns the raw item without user-context fields).
    OEServerConfig *c = [OEServerConfig sharedConfig];
    NSString *path = [NSString stringWithFormat:@"/Users/%@/Items/%@", c.userId ?: @"", itemId];
    NSDictionary *params = @{@"Fields": @"People"};
    [self GET:path params:params completion:^(id result, NSError *error) {
        if (error) {
            // Fallback to the bare /Items/{Id} path for older Emby versions
            // that do not support the user-scoped item endpoint.
            NSString *altPath = [NSString stringWithFormat:@"/Items/%@", itemId];
            [self GET:altPath params:params completion:^(id r2, NSError *e2) {
                if (e2) { if (completion) completion(nil, e2); return; }
                if (![r2 isKindOfClass:[NSDictionary class]]) { if (completion) completion(@[], nil); return; }
                id people = [r2 objectForKey:@"People"];
                if (![people isKindOfClass:[NSArray class]]) { if (completion) completion(@[], nil); return; }
                NSMutableArray *out = [NSMutableArray array];
                for (id raw in people) {
                    if (![raw isKindOfClass:[NSDictionary class]]) continue;
                    OECastItem *cast = [OECastItem castWithDictionary:raw];
                    if (cast) [out addObject:cast];
                }
                if (completion) completion(out, nil);
            }];
            return;
        }
        if (![result isKindOfClass:[NSDictionary class]]) {
            if (completion) completion(@[], nil);
            return;
        }
        id people = [result objectForKey:@"People"];
        if (![people isKindOfClass:[NSArray class]]) {
            if (completion) completion(@[], nil);
            return;
        }
        NSMutableArray *out = [NSMutableArray array];
        for (id raw in people) {
            if (![raw isKindOfClass:[NSDictionary class]]) continue;
            OECastItem *cast = [OECastItem castWithDictionary:raw];
            if (cast) [out addObject:cast];
        }
        if (completion) completion(out, nil);
    }];
}

- (NSString *)personImageURLWithHost:(NSString *)host personId:(NSString *)personId tag:(NSString *)tag maxWidth:(NSInteger)width {
    if (!personId.length || !tag.length || !host) return nil;
    NSString *base = host;
    while ([base hasSuffix:@"/"] && base.length > 1) base = [base substringToIndex:base.length - 1];
    BOOL hasEmbyPrefix = [base hasSuffix:@"/emby"];
    NSString *root = hasEmbyPrefix ? [base substringToIndex:base.length - 5] : base;
    NSString *escapedTag = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL,
        (__bridge CFStringRef)tag, NULL,
        CFSTR(":/?#[]@!$&'()*+,;=%"), kCFStringEncodingUTF8));
    NSString *url = [NSString stringWithFormat:@"%@/emby/Items/%@/Images/Primary?Tag=%@&maxWidth=%ld&quality=90",
            root, personId, escapedTag ?: @"", (long)width];
    NSString *token = [OEServerConfig sharedConfig].accessToken;
    if (!token.length) return url;
    NSString *escaped = OEEncodeQueryComponent(token);
    return [url stringByAppendingFormat:@"&api_key=%@", escaped ?: @""];
}

#pragma mark - Image Helpers

- (NSString *)imageURLForItem:(OEEmbyItem *)item width:(NSInteger)width {
    return [self imageURLForItem:item width:width height:0];
}

- (NSString *)imageURLForItem:(OEEmbyItem *)item width:(NSInteger)width height:(NSInteger)height {
    NSString *url = [item primaryImageURLWithHost:[self baseURL] maxWidth:width maxHeight:height];
    NSString *token = [OEServerConfig sharedConfig].accessToken;
    if (!url.length || !token.length) return url;
    // ImageCache uses a plain NSURLConnection, so authenticate image
    // requests through Emby's api_key query parameter.
    NSString *escaped = OEEncodeQueryComponent(token);
    return [url stringByAppendingFormat:@"&api_key=%@", escaped ?: @""];
}

@end
