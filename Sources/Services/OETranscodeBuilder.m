#import "OETranscodeBuilder.h"
#import "Models/OEServerConfig.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *OEEncodeStreamComponent(NSString *value) {
    if (!value.length) return @"";
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(NULL, (__bridge CFStringRef)value,
        NULL, CFSTR(":/?#[]@!$&'()*+,;=%"), kCFStringEncodingUTF8);
    return escaped ? CFBridgingRelease(escaped) : @"";
}

@implementation OETranscodeBuilder

+ (NSDictionary *)deviceProfileForSettings:(OETranscodeSettings *)s isAudio:(BOOL)isAudio {
    if (s.directPlay) {
        // Advertise the media type being requested.  A video-only profile
        // makes PlaybackInfo reject otherwise playable music sources.
        // Only list containers iOS 6 MPMoviePlayer can natively decode:
        // mp4 and mov.  mkv/avi are NOT supported by the system player.
        NSDictionary *directProfile = isAudio
            ? @{ @"Container": @"mp3,aac,m4a,wav", @"Type": @"Audio", @"AudioCodec": @"mp3,aac,alac,pcm_s16le,pcm_s24le,pcm_s32le" }
            : @{ @"Container": @"mp4,mov,m4v", @"Type": @"Video", @"VideoCodec": @"h264,mpeg4", @"AudioCodec": @"aac,mp3,alac" };
        return @{
            @"Name": @"OldEmby Direct",
            @"MaxStaticBitrate": @(100000000),
            @"MusicStreamingTranscodingBitrate": @(s.maxAudioBitrate),
            @"MaxStreamingBitrate": @(s.maxVideoBitrate),
            @"DirectPlayProfiles": @[directProfile],
            @"TranscodingProfiles": @[],
            @"CodecProfiles": @[],
            @"ContainerProfiles": @[],
            @"SubtitleProfiles": @[@{@"Format": @"srt", @"Method": @"External"}]
        };
    }

    NSInteger w = [s widthForResolution];
    NSInteger h = [s heightForResolution];
    NSInteger vbr = s.maxVideoBitrate;
    NSInteger abr = s.maxAudioBitrate;

    if (isAudio) {
        return @{
            @"Name": @"OldEmby Audio",
            @"MaxStaticBitrate": @(100000000),
            @"MusicStreamingTranscodingBitrate": @(abr),
            // Disable direct play in transcode mode so the requested audio
            // bitrate is actually applied even for AAC/MP3 source files.
            @"DirectPlayProfiles": @[],
            @"TranscodingProfiles": @[
                // Keep a single MP3 profile. Advertising AAC lets Emby select
                // ADTS AAC instead, which is a common iOS 6 AVPlayer failure.
                @{@"Container": @"mp3", @"Type": @"Audio", @"AudioCodec": @"mp3", @"Context": @"Streaming", @"Protocol": @"http"}
            ],
            @"CodecProfiles": @[],
            @"ContainerProfiles": @[],
            @"SubtitleProfiles": @[]
        };
    }

    // Video: force H.264 720p 4Mbps default, as per PRD
    // MaxWidth/MaxHeight + VideoCodec h264 enforces transcode on Emby Server
    return @{
        @"Name": @"OldEmby 720p H264",
        @"MaxStaticBitrate": @(vbr),
        @"MusicStreamingTranscodingBitrate": @(abr),
        @"MaxStreamingBitrate": @(vbr),
        @"DirectPlayProfiles": @[],
        @"TranscodingProfiles": @[
            // HLS is the only transcode delivery iOS 6 MPMoviePlayer reliably
            // plays; raw http MPEG-TS progressive streams stall on it. Mirrors
            // Emby web: Container=ts segments carried over the hls protocol.
            @{
                @"Container": @"ts",
                @"Type": @"Video",
                @"VideoCodec": @"h264",
                @"AudioCodec": @"aac",
                @"Context": @"Streaming",
                @"Protocol": @"hls",
                @"MaxAudioChannels": @"2",
                @"MinSegments": @"1",
                @"BreakOnNonKeyFrames": @NO
            }
        ],
        @"CodecProfiles": @[
            @{
                @"Type": @"Video",
                @"Codec": @"h264",
                @"Conditions": @[
                    @{@"Condition": @"LessThanEqual", @"Property": @"Width", @"Value": @(w).stringValue, @"IsRequired": @NO},
                    @{@"Condition": @"LessThanEqual", @"Property": @"Height", @"Value": @(h).stringValue, @"IsRequired": @NO},
                    @{@"Condition": @"LessThanEqual", @"Property": @"VideoBitrate", @"Value": @(vbr).stringValue, @"IsRequired": @NO}
                ]
            }
        ],
        @"ContainerProfiles": @[],
        @"SubtitleProfiles": @[
            @{@"Format": @"srt", @"Method": @"External"},
            @{@"Format": @"ass", @"Method": @"External"}
        ],
        @"ResponseProfiles": @[
            @{@"Container": @"m3u8", @"Type": @"Video", @"MimeType": @"application/x-mpegURL"}
        ]
    };
}

+ (NSDictionary *)playbackInfoBodyForItemId:(NSString *)itemId userId:(NSString *)userId settings:(OETranscodeSettings *)s isAudio:(BOOL)isAudio {
    NSDictionary *profile = [self deviceProfileForSettings:s isAudio:isAudio];
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    if (userId) body[@"UserId"] = userId;
    if (itemId) body[@"ItemId"] = itemId;
    body[@"DeviceProfile"] = profile;
    // MediaSourceId is the server's source identifier, not the item ID.  Do
    // not send a guessed value on the initial PlaybackInfo request.
    // Emby expects these top-level for legacy 3.x
    body[@"MaxStreamingBitrate"] = @(s.directPlay ? 100000000 : s.maxVideoBitrate);
    body[@"MusicStreamingTranscodingBitrate"] = @(s.maxAudioBitrate);
    // StartTimeTicks = 0 for fresh playback
    body[@"StartTimeTicks"] = @(0);
    // In transcode mode disable both direct-play and direct-stream for audio
    // as well as video; otherwise Emby may legally return the original file
    // and ignore the requested bitrate.
    if (!s.directPlay) {
        body[@"EnableDirectPlay"] = @NO;
        body[@"EnableDirectStream"] = @NO;
        body[@"EnableTranscoding"] = @YES;
        body[@"AllowVideoStreamCopy"] = @NO;
        body[@"AllowAudioStreamCopy"] = @NO;
    } else if (s.directPlay) {
        body[@"EnableDirectPlay"] = @YES;
        body[@"EnableDirectStream"] = @YES;
        body[@"EnableTranscoding"] = @NO;
    }
    return [body copy];
}

+ (NSString *)transcodeQueryStringForSettings:(OETranscodeSettings *)s isAudio:(BOOL)isAudio {
    if (s.directPlay) return @"Static=true";
    if (isAudio) {
        // MP3, not ADTS AAC: iOS 6 AVPlayer is unreliable on headerless AAC
        // progressive streams but plays MP3 from any Emby transcode.
        return [NSString stringWithFormat:@"AudioCodec=mp3&MaxAudioBitrate=%ld&Container=mp3&Static=false", (long)s.maxAudioBitrate];
    }
    NSInteger w = [s widthForResolution];
    NSInteger h = [s heightForResolution];
    return [NSString stringWithFormat:@"VideoCodec=h264&AudioCodec=aac&MaxWidth=%ld&MaxHeight=%ld&MaxVideoBitrate=%ld&VideoBitrate=%ld&AudioBitrate=%ld&Container=ts&Static=false",
            (long)w, (long)h, (long)s.maxVideoBitrate, (long)s.maxVideoBitrate, (long)s.maxAudioBitrate];
}

+ (NSString *)streamURLFromPlaybackInfoResponse:(NSDictionary *)response itemId:(NSString *)itemId isAudio:(BOOL)isAudio host:(NSString *)host settings:(OETranscodeSettings *)s mediaSourceId:(NSString **)outId {
    NSArray *sources = response[@"MediaSources"];
    if (![sources isKindOfClass:[NSArray class]] || sources.count == 0) return nil;
    NSDictionary *src = nil;
    NSString *url = nil;
    // Select only URLs for the requested mode. A direct URL in a transcode
    // response must use our fallback, not hand an original MKV to the player.
    // PlaybackInfo may contain multiple versions/tracks and the first entry
    // is not guaranteed to be playable for this device profile.
    for (NSDictionary *candidate in sources) {
        if (![candidate isKindOfClass:[NSDictionary class]]) continue;
        id candidateURL = candidate[s.directPlay ? @"DirectStreamUrl" : @"TranscodingUrl"];
        if ([candidateURL isKindOfClass:[NSString class]] && [candidateURL length]) {
            src = candidate;
            url = candidateURL;
            break;
        }
    }
    // If no source includes a URL, retain the first valid source for the
    // fallback /{Audio,Videos}/{item}/stream endpoint.
    if (!src) {
        for (NSDictionary *candidate in sources) {
            if ([candidate isKindOfClass:[NSDictionary class]]) { src = candidate; break; }
        }
    }
    if (!src) return nil;
    NSString *msId = [src[@"Id"] isKindOfClass:[NSString class]] ? src[@"Id"] : @"";
    if (outId) *outId = msId;
    NSString *resolvedItemId = itemId.length ? itemId : ([response[@"ItemId"] isKindOfClass:[NSString class]] ? response[@"ItemId"] : nil);
    NSString *encodedItemId = OEEncodeStreamComponent(resolvedItemId);
    NSString *msParam = msId.length ? [NSString stringWithFormat:@"MediaSourceId=%@&", OEEncodeStreamComponent(msId)] : @"";
    if (!url.length && !s.directPlay && !isAudio) {
        // Some servers (notably Emby 4.9 with selective profiles) answer a
        // transcode PlaybackInfo without any TranscodingUrl.  Official
        // clients do not give up there: they build the canonical HLS master
        // endpoint themselves and the server starts transcoding on request.
        // This mirrors Emby web / Kodi: /Videos/{id}/master.m3u8 with the
        // media source and codec constraints in the query string.  api_key is
        // appended by the caller (OEEmbyAPIClient fetchStreamURLForItem).
        if (!resolvedItemId.length) return nil;
        OEServerConfig *config = [OEServerConfig sharedConfig];
        url = [NSString stringWithFormat:@"/Videos/%@/master.m3u8?%@DeviceId=%@&VideoCodec=h264&AudioCodec=aac&VideoBitrate=%ld&AudioBitrate=%ld&MaxWidth=%ld&MaxHeight=%ld&TranscodingMaxAudioChannels=2&SegmentContainer=ts&MinSegments=1&Static=false&AllowVideoStreamCopy=false&AllowAudioStreamCopy=false",
               encodedItemId, msParam, OEEncodeStreamComponent(config.deviceId),
               (long)s.maxVideoBitrate, (long)s.maxAudioBitrate,
               (long)[s widthForResolution], (long)[s heightForResolution]];
    }
    if (!url.length && !s.directPlay && isAudio) {
        // The universal endpoint is the audio endpoint guaranteed to honor a
        // transcode request; /Audio/.../stream can return the source file
        // untouched.  MP3 because iOS 6 AVPlayer chokes on ADTS AAC streams.
        OEServerConfig *config = [OEServerConfig sharedConfig];
        if (!resolvedItemId.length) return nil;
        url = [NSString stringWithFormat:@"/Audio/%@/universal?%@UserId=%@&DeviceId=%@&MaxStreamingBitrate=%ld&Container=mp3&AudioCodec=mp3&EnableDirectPlay=false&EnableDirectStream=false&AllowAudioStreamCopy=false",
               encodedItemId, msParam, OEEncodeStreamComponent(config.userId), OEEncodeStreamComponent(config.deviceId),
               (long)s.maxAudioBitrate];
    }
    if (!url.length) {
        // Emby 4.x may return MediaSources with SupportsDirectStream etc,
        // but no URL -> build the appropriate audio/video stream endpoint.
        // The media-source ID cannot be used as the video item ID.  Use the
        // original item ID supplied by the caller for this fallback URL.
        if (!resolvedItemId.length) return nil;
        NSString *resource = isAudio ? @"Audio" : @"Videos";
        NSString *staticFlag = s.directPlay ? @"Static=true" : @"Static=false";
        // An empty MediaSourceId query value makes some Emby versions reject
        // the request outright - omit the key entirely in that case.
        url = [NSString stringWithFormat:@"/%@/%@/stream?%@%@", resource, encodedItemId, msParam, staticFlag];
    }
    // Ensure absolute URL
    if ([[url lowercaseString] hasPrefix:@"http://"] || [[url lowercaseString] hasPrefix:@"https://"]) return url;
    NSString *base = host;
    if (!base.length) return nil;
    while ([base hasSuffix:@"/"] && base.length > 1) base = [base substringToIndex:base.length - 1];
    if (![url hasPrefix:@"/"]) url = [@"/" stringByAppendingString:url];
    // Avoid duplicate /emby/emby if both base host and server URL carry the prefix
    if ([base hasSuffix:@"/emby"] && [url hasPrefix:@"/emby/"]) {
        url = [url substringFromIndex:5];
    }
    return [base stringByAppendingString:url];
}

@end
