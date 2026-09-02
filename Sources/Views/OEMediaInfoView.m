#import "OEMediaInfoView.h"
#import "OETheme.h"

// Layout constants
static const CGFloat kInfoPadding = 12.0;
static const CGFloat kInfoRowHeight = 18.0;
static const CGFloat kInfoRowGap = 2.0;
static const CGFloat kInfoSectionGap = 10.0;
static const CGFloat kInfoHeaderHeight = 22.0;
static const CGFloat kInfoLabelWidth = 90.0;
static const CGFloat kInfoBorderWidth = 0.5;
static const CGFloat kInfoCornerRadius = 8.0;

@interface OEMediaInfoView ()
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, assign) CGFloat cachedHeight;
@end

@implementation OEMediaInfoView

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        _containerView = [[UIView alloc] initWithFrame:CGRectZero];
        _containerView.layer.cornerRadius = kInfoCornerRadius;
        _containerView.layer.borderWidth = kInfoBorderWidth;
        _containerView.layer.borderColor = [OETheme separatorColor].CGColor;
        _containerView.backgroundColor = [OETheme cellColor];
        [self addSubview:_containerView];
    }
    return self;
}

- (void)setMediaSources:(NSArray *)mediaSources {
    _mediaSources = mediaSources;
    [self rebuild];
}

- (void)applyTheme {
    _containerView.layer.borderColor = [OETheme separatorColor].CGColor;
    _containerView.backgroundColor = [OETheme cellColor];
    for (UIView *v in [_containerView subviews]) {
        if ([v isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)v;
            // Header labels have tag 1000, key labels 1001, value labels 1002
            if (label.tag == 1000) label.textColor = [OETheme accentColor];
            else if (label.tag == 1001) label.textColor = [OETheme secondaryTextColor];
            else if (label.tag == 1002) label.textColor = [OETheme primaryTextColor];
        }
    }
}

- (NSString *)safeString:(id)value {
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length]) return value;
    return nil;
}

- (NSString *)safeNumberString:(id)value {
    if (![value respondsToSelector:@selector(stringValue)]) return nil;
    return [value stringValue];
}

- (NSString *)formatBitrate:(id)value {
    NSString *s = [self safeNumberString:value];
    if (!s) return nil;
    long bps = [s longLongValue];
    if (bps >= 1000000) {
        double mbps = bps / 1000000.0;
        if (mbps >= 10) return [NSString stringWithFormat:@"%.0f mbps", mbps];
        return [NSString stringWithFormat:@"%.1f mbps", mbps];
    }
    if (bps >= 1000) return [NSString stringWithFormat:@"%ld kbps", (long)(bps / 1000)];
    return [NSString stringWithFormat:@"%ld bps", bps];
}

- (NSString *)formatSampleRate:(id)value {
    NSString *s = [self safeNumberString:value];
    if (!s) return nil;
    long hz = [s longLongValue];
    return [NSString stringWithFormat:@"%ld Hz", hz];
}

- (NSString *)formatBool:(id)value suffix:(NSString *)suffix {
    if (value == nil) return nil;
    if ([value isKindOfClass:[NSNumber class]]) {
        NSString *yn = [value boolValue] ? @"是" : @"否";
        return suffix.length ? [NSString stringWithFormat:@"%@ %@", yn, suffix] : yn;
    }
    return [self safeString:value];
}

- (void)addHeaderLabel:(NSString *)text container:(UIView *)container y:(CGFloat)y width:(CGFloat)w {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(kInfoPadding, y, w - 2 * kInfoPadding, kInfoHeaderHeight)];
    label.font = [UIFont boldSystemFontOfSize:14];
    label.text = text;
    label.tag = 1000;
    label.textColor = [OETheme accentColor];
    label.backgroundColor = [UIColor clearColor];
    [container addSubview:label];
}

- (CGFloat)addRow:(NSString *)key value:(NSString *)val container:(UIView *)container y:(CGFloat)y width:(CGFloat)w {
    if (!val.length) return y;
    UILabel *keyLabel = [[UILabel alloc] initWithFrame:CGRectMake(kInfoPadding, y, kInfoLabelWidth, kInfoRowHeight)];
    keyLabel.font = [UIFont systemFontOfSize:12];
    keyLabel.text = key;
    keyLabel.tag = 1001;
    keyLabel.textColor = [OETheme secondaryTextColor];
    keyLabel.backgroundColor = [UIColor clearColor];
    [container addSubview:keyLabel];

    UILabel *valLabel = [[UILabel alloc] initWithFrame:CGRectMake(kInfoPadding + kInfoLabelWidth, y, w - 2 * kInfoPadding - kInfoLabelWidth, kInfoRowHeight)];
    valLabel.font = [UIFont systemFontOfSize:12];
    valLabel.text = val;
    valLabel.tag = 1002;
    valLabel.textColor = [OETheme primaryTextColor];
    valLabel.backgroundColor = [UIColor clearColor];
    valLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [container addSubview:valLabel];

    return y + kInfoRowHeight + kInfoRowGap;
}

- (void)rebuild {
    for (UIView *v in [_containerView subviews]) [v removeFromSuperview];

    CGFloat w = self.bounds.size.width;
    if (w < 1) w = [UIScreen mainScreen].bounds.size.width;

    NSArray *sources = self.mediaSources ?: @[];
    CGFloat y = kInfoPadding;
    BOOL hasVideo = NO;
    BOOL hasAudio = NO;

    // First pass: find video and audio streams
    NSMutableArray *videoStreams = [NSMutableArray array];
    NSMutableArray *audioStreams = [NSMutableArray array];
    for (NSDictionary *source in sources) {
        if (![source isKindOfClass:[NSDictionary class]]) continue;
        NSArray *streams = source[@"MediaStreams"];
        if (![streams isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *stream in streams) {
            if (![stream isKindOfClass:[NSDictionary class]]) continue;
            NSString *type = [self safeString:stream[@"Type"]];
            if ([type isEqualToString:@"Video"]) [videoStreams addObject:stream];
            else if ([type isEqualToString:@"Audio"]) [audioStreams addObject:stream];
        }
    }

    // Video section
    if (videoStreams.count > 0) {
        NSDictionary *v = videoStreams[0];
        y += 2;
        [self addHeaderLabel:@"视频" container:_containerView y:y width:w];
        y += kInfoHeaderHeight + 4;

        NSString *title = [self safeString:v[@"DisplayTitle"]];
        if (title.length) y = [self addRow:@"标题" value:title container:_containerView y:y width:w];

        NSString *codec = [self safeString:v[@"Codec"]];
        NSString *profile = [self safeString:v[@"Profile"]];
        // Build a summary line like "1080p H264"
        NSString *widthStr = [self safeNumberString:v[@"Width"]];
        NSString *heightStr = [self safeNumberString:v[@"Height"]];
        NSString *resSummary = nil;
        if (heightStr.length) {
            resSummary = [NSString stringWithFormat:@"%@p", heightStr];
            if (codec.length) resSummary = [NSString stringWithFormat:@"%@ %@", resSummary, codec.uppercaseString];
        }
        if (resSummary.length) y = [self addRow:@"概要" value:resSummary container:_containerView y:y width:w];

        if (codec.length) y = [self addRow:@"编解码器" value:codec.uppercaseString container:_containerView y:y width:w];
        if (profile.length) y = [self addRow:@"用户资料" value:profile container:_containerView y:y width:w];

        NSString *level = [self safeString:v[@"Level"]];
        if (level.length) y = [self addRow:@"等级" value:level container:_containerView y:y width:w];

        if (widthStr.length && heightStr.length) {
            y = [self addRow:@"分辨率" value:[NSString stringWithFormat:@"%@x%@", widthStr, heightStr] container:_containerView y:y width:w];
        }

        NSString *aspect = [self safeString:v[@"AspectRatio"]];
        if (aspect.length) y = [self addRow:@"长宽比" value:aspect container:_containerView y:y width:w];

        // Interlaced
        id interlaced = v[@"IsInterlaced"];
        if (interlaced != nil) y = [self addRow:@"交错" value:[self formatBool:interlaced suffix:@""] container:_containerView y:y width:w];

        // Frame rate
        NSString *fr = [self safeString:v[@"RealFrameRate"]] ?: [self safeString:v[@"AverageFrameRate"]] ?: [self safeString:v[@"FrameRate"]];
        if (fr.length) y = [self addRow:@"帧率" value:fr container:_containerView y:y width:w];

        // Bitrate
        NSString *br = [self formatBitrate:v[@"BitRate"]] ?: [self formatBitrate:v[@"VideoBitRate"]];
        if (br.length) y = [self addRow:@"比特率" value:br container:_containerView y:y width:w];

        // Color primaries / transfer / color range
        NSString *primaries = [self safeString:v[@"Color primaries"]] ?: [self safeString:v[@"ColorPrimaries"]] ?: [self safeString:v[@"Primary"]];
        if (primaries.length) y = [self addRow:@"基色" value:primaries container:_containerView y:y width:w];

        NSString *colorSpace = [self safeString:v[@"ColorSpace"]] ?: [self safeString:v[@"Color space"]] ?: [self safeString:v[@"ColorTransfer"]];
        if (colorSpace.length) y = [self addRow:@"色域" value:colorSpace container:_containerView y:y width:w];

        NSString *bitDepth = [self safeString:v[@"BitDepth"]] ?: [self safeNumberString:v[@"BitDepth"]];
        if (bitDepth.length) y = [self addRow:@"位深度" value:[NSString stringWithFormat:@"%@ bit", bitDepth] container:_containerView y:y width:w];

        NSString *pixFmt = [self safeString:v[@"PixelFormat"]] ?: [self safeString:v[@"Pixel format"]];
        if (pixFmt.length) y = [self addRow:@"像素格式" value:pixFmt container:_containerView y:y width:w];

        NSString *refFrames = [self safeString:v[@"RefFrames"]] ?: [self safeNumberString:v[@"RefFrames"]];
        if (refFrames.length) y = [self addRow:@"参考帧" value:refFrames container:_containerView y:y width:w];

        y += kInfoSectionGap;
        hasVideo = YES;
    }

    // Audio section(s) - show all audio tracks
    if (audioStreams.count > 0) {
        if (hasVideo) y += kInfoSectionGap;
        [self addHeaderLabel:@"音频" container:_containerView y:y width:w];
        y += kInfoHeaderHeight + 4;

        for (NSInteger i = 0; i < (NSInteger)audioStreams.count; i++) {
            NSDictionary *a = audioStreams[i];
            if (i > 0) y += kInfoRowGap * 2;

            NSString *title = [self safeString:a[@"DisplayTitle"]];
            NSString *codec = [self safeString:a[@"Codec"]];
            NSString *lang = [self safeString:a[@"Language"]];

            // Build a compact title: "Japanese EAC3 7.1 (默认)"
            NSMutableString *audioSummary = [NSMutableString string];
            if (lang.length) [audioSummary appendFormat:@"%@ ", [self languageDisplay:lang]];
            if (codec.length) [audioSummary appendFormat:@"%@ ", codec.uppercaseString];
            NSString *layout = [self safeString:a[@"ChannelLayout"]] ?: [self safeString:a[@"Layout"]];
            if (layout.length) [audioSummary appendString:layout];

            BOOL isDefault = [a[@"IsDefault"] boolValue];
            if (isDefault) [audioSummary appendString:@" (默认)"];

            if (audioSummary.length) y = [self addRow:@"标题" value:audioSummary container:_containerView y:y width:w];

            if (title.length && ![title isEqualToString:audioSummary]) {
                y = [self addRow:@"内嵌标题" value:title container:_containerView y:y width:w];
            }

            if (lang.length) y = [self addRow:@"语言" value:[self languageDisplay:lang] container:_containerView y:y width:w];
            if (codec.length) y = [self addRow:@"编解码器" value:codec.uppercaseString container:_containerView y:y width:w];

            NSString *channelLayout = [self safeString:a[@"ChannelLayout"]] ?: [self safeString:a[@"Layout"]];
            if (channelLayout.length) y = [self addRow:@"布局" value:channelLayout container:_containerView y:y width:w];

            NSString *channels = [self safeNumberString:a[@"Channels"]];
            if (channels.length) y = [self addRow:@"频道" value:[NSString stringWithFormat:@"%@ ch", channels] container:_containerView y:y width:w];

            NSString *br = [self formatBitrate:a[@"BitRate"]];
            if (br.length) y = [self addRow:@"比特率" value:br container:_containerView y:y width:w];

            NSString *sr = [self formatSampleRate:a[@"SampleRate"]];
            if (sr.length) y = [self addRow:@"采样率" value:sr container:_containerView y:y width:w];

            if (isDefault) y = [self addRow:@"默认" value:@"是" container:_containerView y:y width:w];
            else y = [self addRow:@"默认" value:@"否" container:_containerView y:y width:w];
        }
        hasAudio = YES;
    }

    if (!hasVideo && !hasAudio) {
        UILabel *none = [[UILabel alloc] initWithFrame:CGRectMake(kInfoPadding, y, w - 2 * kInfoPadding, kInfoRowHeight)];
        none.font = [UIFont systemFontOfSize:12];
        none.text = @"暂无媒体信息";
        none.textColor = [OETheme secondaryTextColor];
        none.backgroundColor = [UIColor clearColor];
        [self.containerView addSubview:none];
        y += kInfoRowHeight + kInfoPadding;
    } else {
        y += kInfoPadding;
    }

    _cachedHeight = y;
    _containerView.frame = CGRectMake(0, 0, w, y);
}

- (NSString *)languageDisplay:(NSString *)code {
    if (!code.length) return @"未知";
    NSDictionary *map = @{
        @"jpn": @"日语", @"japanese": @"日语", @"ja": @"日语",
        @"chi": @"中文", @"chinese": @"中文", @"zh": @"中文", @"zho": @"中文",
        @"eng": @"英语", @"english": @"英语", @"en": @"英语",
        @"kor": @"韩语", @"korean": @"韩语", @"ko": @"韩语",
        @"fra": @"法语", @"french": @"法语", @"fr": @"法语",
        @"ger": @"德语", @"deu": @"德语", @"german": @"德语", @"de": @"德语",
        @"spa": @"西班牙语", @"es": @"西班牙语",
        @"ita": @"意大利语", @"it": @"意大利语",
        @"tha": @"泰语", @"th": @"泰语",
        @"rus": @"俄语", @"ru": @"俄语",
        @"por": @"葡萄牙语", @"pt": @"葡萄牙语",
    };
    NSString *lower = [code lowercaseString];
    NSString *mapped = map[lower];
    return mapped ?: code;
}

- (CGFloat)heightForWidth:(CGFloat)width {
    // Recompute if width changed significantly
    if (fabs(self.bounds.size.width - width) > 1.0 || _cachedHeight == 0) {
        CGRect f = self.frame;
        f.size.width = width;
        self.frame = f;
        [self rebuild];
    }
    return _cachedHeight;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    if (_containerView.frame.size.width != w) {
        [self rebuild];
    }
}

@end
