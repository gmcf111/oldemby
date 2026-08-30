#import "OETranscodeBuilder.h"

@implementation OETranscodeBuilder

+ (NSDictionary *)deviceProfileForSettings:(OETranscodeSettings *)s isAudio:(BOOL)isAudio {
    if (s.directPlay) {
        // Empty profile -> allow direct play if source is already H264/AAC compatible
        return @{
            @"Name": @"OldEmby Direct",
            @"MaxStaticBitrate": @(100000000),
            @"MusicStreamingTranscodingBitrate": @(s.maxAudioBitrate),
            @"MaxStreamingBitrate": @(s.maxVideoBitrate),
            @"DirectPlayProfiles": @[@{@"Container": @"mp4,mkv,avi,mov", @"Type": @"Video"}],
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
            @"DirectPlayProfiles": @[@{@"Container": @"mp3,aac,flac,ogg,wav", @"Type": @"Audio"}],
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
    body[@"MediaSourceId"] = itemId ?: @"";
    body[@"AudioStreamIndex"] = @(1);
    // Emby expects these top-level for legacy 3.x
    body[@"MaxStreamingBitrate"] = @(s.directPlay ? 100000000 : s.maxVideoBitrate);
    body[@"MusicStreamingTranscodingBitrate"] = @(s.maxAudioBitrate);
    // StartTimeTicks = 0 for fresh playback
    body[@"StartTimeTicks"] = @(0);
    // For video, request HLS if transcoding, else static
    if (!isAudio && !s.directPlay) {
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
        return [NSString stringWithFormat:@"AudioCodec=aac&MaxAudioBitrate=%ld&Container=mp3", (long)s.maxAudioBitrate];
    }
    NSInteger w = [s widthForResolution];
    NSInteger h = [s heightForResolution];
    return [NSString stringWithFormat:@"VideoCodec=h264&AudioCodec=aac&MaxWidth=%ld&MaxHeight=%ld&MaxVideoBitrate=%ld&VideoBitrate=%ld&AudioBitrate=%ld&Container=mp4&Static=false",
            (long)w, (long)h, (long)s.maxVideoBitrate, (long)s.maxVideoBitrate, (long)s.maxAudioBitrate];
}

+ (NSString *)streamURLFromPlaybackInfoResponse:(NSDictionary *)response host:(NSString *)host mediaSourceId:(NSString **)outId {
    NSArray *sources = response[@"MediaSources"];
    if (![sources isKindOfClass:[NSArray class]] || sources.count == 0) return nil;
    NSDictionary *src = sources[0];
    NSString *msId = src[@"Id"] ?: src[@"ETag"] ?: @"";
    if (outId) *outId = msId;
    // Prefer TranscodingUrl, else DirectStreamUrl
    NSString *url = src[@"TranscodingUrl"] ?: src[@"DirectStreamUrl"];
    if (!url) {
        // Emby 4.x may return MediaSources with SupportsDirectStream etc, but no URL -> build via /Videos/{Id}/stream
        NSString *itemId = response[@"ItemId"] ?: src[@"Id"] ?: @"";
        // Caller will append query string via builder
        url = [NSString stringWithFormat:@"/Videos/%@/stream?MediaSourceId=%@&Static=false", itemId, msId];
    }
    // Ensure absolute URL
    if ([url hasPrefix:@"http"]) return url;
    NSString *base = host;
    while ([base hasSuffix:@"/"] && base.length>1) base=[base substringToIndex:base.length-1];
    if (![url hasPrefix:@"/"]) url = [@"/" stringByAppendingString:url];
    return [base stringByAppendingString:url];
}

@end
