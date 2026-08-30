#import "OETranscodeBuilder.h"

@implementation OETranscodeBuilder

+ (NSDictionary *)deviceProfileForSettings:(OETranscodeSettings *)s isAudio:(BOOL)isAudio {
    if (s.directPlay) {
        // Advertise the media type being requested.  A video-only profile
        // makes PlaybackInfo reject otherwise playable music sources.
        NSDictionary *directProfile = isAudio
            ? @{ @"Container": @"mp3,aac,m4a,wav", @"Type": @"Audio" }
            : @{ @"Container": @"mp4,mkv,avi,mov", @"Type": @"Video" };
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
                @{@"Container": @"mp3", @"Type": @"Audio", @"AudioCodec": @"mp3", @"Context": @"Streaming", @"Protocol": @"http"},
                @{@"Container": @"aac", @"Type": @"Audio", @"AudioCodec": @"aac", @"Context": @"Streaming", @"Protocol": @"http"}
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
            @{
                @"Container": @"mp4",
                @"Type": @"Video",
                @"VideoCodec": @"h264",
                @"AudioCodec": @"aac,mp3",
                @"Context": @"Streaming",
                @"Protocol": @"http",
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
            @{@"Container": @"m3u8", @"Type": @"Video", @"MimeType": @"application/x-mpegURL"},
            @{@"Container": @"mp4", @"Type": @"Video", @"MimeType": @"video/mp4"}
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
        return [NSString stringWithFormat:@"AudioCodec=aac&MaxAudioBitrate=%ld&Container=aac&Static=false", (long)s.maxAudioBitrate];
    }
    NSInteger w = [s widthForResolution];
    NSInteger h = [s heightForResolution];
    return [NSString stringWithFormat:@"VideoCodec=h264&AudioCodec=aac&MaxWidth=%ld&MaxHeight=%ld&MaxVideoBitrate=%ld&VideoBitrate=%ld&AudioBitrate=%ld&Container=mp4&Static=false",
            (long)w, (long)h, (long)s.maxVideoBitrate, (long)s.maxVideoBitrate, (long)s.maxAudioBitrate];
}

+ (NSString *)streamURLFromPlaybackInfoResponse:(NSDictionary *)response itemId:(NSString *)itemId isAudio:(BOOL)isAudio host:(NSString *)host mediaSourceId:(NSString **)outId {
    NSArray *sources = response[@"MediaSources"];
    if (![sources isKindOfClass:[NSArray class]] || sources.count == 0) return nil;
    NSDictionary *src = nil;
    NSString *url = nil;
    // Prefer a source with an explicit transcoding URL, then any direct URL.
    // PlaybackInfo may contain multiple versions/tracks and the first entry
    // is not guaranteed to be playable for this device profile.
    for (NSDictionary *candidate in sources) {
        if (![candidate isKindOfClass:[NSDictionary class]]) continue;
        id candidateURL = candidate[@"TranscodingUrl"];
        if ([candidateURL isKindOfClass:[NSString class]] && [candidateURL length]) {
            src = candidate;
            url = candidateURL;
            break;
        }
    }
    if (!url) {
        for (NSDictionary *candidate in sources) {
            if (![candidate isKindOfClass:[NSDictionary class]]) continue;
            id candidateURL = candidate[@"DirectStreamUrl"];
            if ([candidateURL isKindOfClass:[NSString class]] && [candidateURL length]) {
                src = candidate;
                url = candidateURL;
                break;
            }
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
    NSString *msId = [src[@"Id"] isKindOfClass:[NSString class]] ? src[@"Id"] : ([src[@"ETag"] isKindOfClass:[NSString class]] ? src[@"ETag"] : @"");
    if (outId) *outId = msId;
    if (!url.length) {
        // Emby 4.x may return MediaSources with SupportsDirectStream etc,
        // but no URL -> build the appropriate audio/video stream endpoint.
        // The media-source ID cannot be used as the video item ID.  Use the
        // original item ID supplied by the caller for this fallback URL.
        NSString *resolvedItemId = itemId ?: response[@"ItemId"] ?: @"";
        if (!resolvedItemId.length) return nil;
        NSString *resource = isAudio ? @"Audio" : @"Videos";
        // This method takes no settings argument; the Static flag mirrors the
        // global preference the caller used when building the PlaybackInfo body.
        NSString *staticFlag = [OETranscodeSettings sharedSettings].directPlay ? @"Static=true" : @"Static=false";
        url = [NSString stringWithFormat:@"/%@/%@/stream?MediaSourceId=%@&%@", resource, resolvedItemId, msId, staticFlag];
    }
    // Ensure absolute URL
    if ([url hasPrefix:@"http"]) return url;
    NSString *base = host;
    if (!base.length) return nil;
    while ([base hasSuffix:@"/"] && base.length>1) base=[base substringToIndex:base.length-1];
    if (![url hasPrefix:@"/"]) url = [@"/" stringByAppendingString:url];
    return [base stringByAppendingString:url];
}

@end
