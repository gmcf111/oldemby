#import "OEMusicPlayerViewController.h"
#import "OEMusicPlayQueueViewController.h"
#import "Models/OEEmbyItem.h"
#import "Models/OELyricsLine.h"
#import "Models/OETranscodeSettings.h"
#import "Services/OEMusicPlaybackManager.h"
#import "Services/OEEmbyAPIClient.h"
#import "Views/OETheme.h"
#import "Views/OEIconFactory.h"
#import "Views/OEErrorAlertView.h"
#import "Constants.h"
#import <MediaPlayer/MediaPlayer.h>
#import <Accelerate/Accelerate.h>
#import <math.h>

// Full-screen music player presented modally (cover-vertical, sliding up over
// the mini player). The backdrop is the artwork blurred with Accelerate's
// vImage box blur (the reliable iOS 6 technique) under a translucent theme
// overlay. Landscape uses a two-pane layout (artwork left, info + lyrics
// right); portrait stacks vertically.
//
// The bottom bar is one row on a single shared centerline:
//
//   [prev play/pause next]      [ -------- progress -------- ]      [volume mode favorite queue]
//
//   - prev/play-pause/next are native UIBarButtonItem system items hosted by
//     the bar's UIToolbar, so they are drawn by UIKit (no hand-rolled icons).
//     iOS 6 has no system item for "previous/next track", so Rewind and
//     FastForward stand in — the native transport pair.
//   - progress is a stock UISlider, horizontally centred on the bar and as
//     long as the gap between the two clusters allows.
//   - volume (MPVolumeView) and the drawn mode / favorite / queue buttons are
//     direct subviews: packing sliders into UIBarButtonItem custom views made
//     them vanish on iOS 6 once the row overflowed the bar width. Only the
//     transport lives in the toolbar, and it never carries a slider.

@interface OEMusicPlayerViewController ()
@property (nonatomic, strong) UIImageView *backgroundImageView;
@property (nonatomic, strong) UIView *blurOverlay;
@property (nonatomic, strong) UIImage *blurredSourceImage;
@property (nonatomic, strong) UIButton *collapseButton;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITableView *lyricsTable;
@property (nonatomic, strong) UILabel *lyricsEmptyLabel;
@property (nonatomic, strong) NSArray *lyrics;
@property (nonatomic, copy) NSString *lyricsItemId;
@property (nonatomic, assign) NSInteger highlightedLyricsIndex;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIToolbar *bottomChrome;
// Native transport. The toolbar hosts these as real bar items; the slider and
// the auxiliary buttons stay direct subviews (bar-item custom views clip and
// vanish on iOS 6 as soon as the row overflows).
@property (nonatomic, strong) UIBarButtonItem *previousItem;
@property (nonatomic, strong) UIBarButtonItem *playPauseItem;
@property (nonatomic, strong) UIBarButtonItem *nextItem;
@property (nonatomic, assign) UIBarButtonSystemItem playPauseSystemItem;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) MPVolumeView *volumeView;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) UIButton *queueButton;
@property (nonatomic, assign) BOOL favoriteRequestInFlight;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, assign) BOOL seeking;
@end

@implementation OEMusicPlayerViewController

- (instancetype)initWithItem:(OEEmbyItem *)item playlist:(NSArray *)playlist {
    // item/playlist are accepted for API compatibility but deliberately not
    // stored: opening the player must not start or restart playback.
    self = [super init];
    if (self) {
        _highlightedLyricsIndex = NSNotFound;
        _playPauseSystemItem = UIBarButtonSystemItemPlay;
    }
    return self;
}

- (UIButton *)iconButtonWithAction:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

#pragma mark - Native transport items

// The transport is rebuilt only when the play/pause glyph actually changes;
// refreshing on every progress tick would reflow the toolbar twice a second.
- (void)updatePlayPauseItem {
    UIBarButtonSystemItem wanted = [OEMusicPlaybackManager sharedManager].isPlaying
        ? UIBarButtonSystemItemPause : UIBarButtonSystemItemPlay;
    if (self.playPauseSystemItem == wanted) return;
    self.playPauseSystemItem = wanted;
    [self rebuildTransportItems];
}

- (void)rebuildTransportItems {
    if (!self.previousItem) {
        self.previousItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRewind
                                                                         target:self action:@selector(previousTapped)];
        self.nextItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFastForward
                                                                     target:self action:@selector(nextTapped)];
    }
    self.playPauseItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:self.playPauseSystemItem
                                                                      target:self action:@selector(playPauseTapped)];
    UIBarButtonItem *gapA = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    gapA.width = 16;
    UIBarButtonItem *gapB = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    gapB.width = 16;
    // Trailing flexible space keeps the trio pinned to the left edge instead
    // of letting the toolbar stretch the buttons across the whole row.
    UIBarButtonItem *tail = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    [self.bottomChrome setItems:@[self.previousItem, gapA, self.playPauseItem, gapB, self.nextItem, tail] animated:NO];
}

// Union of the toolbar's own transport button frames, in bottomBar
// coordinates. Item widths and the bar's inner stack differ between iOS 6
// (bordered buttons) and iOS 7+ (borderless buttons inside a stack view), so
// measuring beats guessing: the layout uses this both to keep the progress
// slider clear of the transport and to put every other control on the
// transport's own centerline. Views spanning most of the bar are backgrounds,
// not buttons.
- (CGRect)transportClusterRect {
    [self.bottomChrome layoutIfNeeded];
    CGFloat width = MAX(1.0, self.bottomChrome.bounds.size.width);
    CGRect cluster = CGRectNull;
    NSMutableArray *queue = [NSMutableArray arrayWithArray:self.bottomChrome.subviews];
    while (queue.count) {
        UIView *view = queue[0];
        [queue removeObjectAtIndex:0];
        BOOL spansBar = view.frame.size.width > width * 0.7;
        if (!spansBar && !view.hidden && [view isKindOfClass:[UIControl class]]) {
            CGRect rect = [view.superview convertRect:view.frame toView:self.bottomBar];
            cluster = CGRectIsNull(cluster) ? rect : CGRectUnion(cluster, rect);
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return cluster;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [OETheme prepareViewController:self];

    // Frosted backdrop: blurred artwork, aspect-fill, dimmed by the overlay.
    self.backgroundImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.backgroundImageView.clipsToBounds = YES;
    [self.view addSubview:self.backgroundImageView];

    self.blurOverlay = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.blurOverlay];

    self.artworkView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFit;
    self.artworkView.clipsToBounds = YES;
    self.artworkView.layer.cornerRadius = 6.0;
    self.artworkView.userInteractionEnabled = YES;
    [self.view addSubview:self.artworkView];
    // Swiping down on the artwork collapses the player, matching the chevron.
    UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(collapseTapped)];
    swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
    [self.artworkView addGestureRecognizer:swipeDown];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.titleLabel];

    self.artistLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.artistLabel.font = [UIFont systemFontOfSize:13];
    self.artistLabel.textAlignment = NSTextAlignmentCenter;
    self.artistLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.artistLabel];

    // Small bordered quality badge ("192k" / "直连"), QQ-Music style.
    self.badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.badgeLabel.font = [UIFont systemFontOfSize:10];
    self.badgeLabel.textAlignment = NSTextAlignmentCenter;
    self.badgeLabel.backgroundColor = [UIColor clearColor];
    self.badgeLabel.layer.borderWidth = 1.0;
    self.badgeLabel.layer.cornerRadius = 3.0;
    [self.view addSubview:self.badgeLabel];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.font = [UIFont systemFontOfSize:11];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.statusLabel];

    self.lyricsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.lyricsTable.dataSource = self;
    self.lyricsTable.delegate = self;
    self.lyricsTable.rowHeight = 28;
    self.lyricsTable.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.lyricsTable.showsVerticalScrollIndicator = NO;
    self.lyricsTable.opaque = NO;
    [self.view addSubview:self.lyricsTable];

    self.lyricsEmptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.lyricsEmptyLabel.text = @"正在加载歌词…";
    self.lyricsEmptyLabel.textAlignment = NSTextAlignmentCenter;
    self.lyricsEmptyLabel.font = [UIFont systemFontOfSize:13];
    self.lyricsEmptyLabel.backgroundColor = [UIColor clearColor];
    [self.lyricsTable addSubview:self.lyricsEmptyLabel];

    // Bottom bar: native toolbar chrome carrying the native transport items,
    // then the slider and the auxiliary buttons as direct subviews on the
    // same centerline.
    self.bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.bottomBar];

    self.bottomChrome = [[UIToolbar alloc] initWithFrame:CGRectZero];
    [self.bottomBar addSubview:self.bottomChrome];
    [self rebuildTransportItems];

    // Stock native slider — no tint overrides, iOS 6 glossy blue look.
    self.progressSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    self.progressSlider.minimumValue = 0.0;
    self.progressSlider.maximumValue = 1.0;
    self.progressSlider.continuous = YES;
    self.progressSlider.exclusiveTouch = YES;
    [self.progressSlider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [self.progressSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    // Commit the seek only on a genuine touch-up/cancel. TouchDragExit and
    // TouchDragEnter fire the moment a finger leaves and re-enters this
    // 30pt-tall control on its way along the track; treating those as a
    // release committed a seek mid-drag and cleared `seeking`, after which
    // the next progress tick snapped the thumb back to the playback
    // position — the "slider cannot be dragged" bug.
    [self.progressSlider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.bottomBar addSubview:self.progressSlider];

    self.volumeView = [[MPVolumeView alloc] initWithFrame:CGRectZero];
    self.volumeView.showsRouteButton = NO;
    [self.bottomBar addSubview:self.volumeView];

    self.repeatButton = [self iconButtonWithAction:@selector(repeatTapped)];
    [self.bottomBar addSubview:self.repeatButton];
    self.favoriteButton = [self iconButtonWithAction:@selector(favoriteTapped)];
    [self.bottomBar addSubview:self.favoriteButton];
    self.queueButton = [self iconButtonWithAction:@selector(queueTapped)];
    [self.bottomBar addSubview:self.queueButton];

    // "01:23 / 04:56" caption just above the bar.
    self.timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.timeLabel.font = [UIFont systemFontOfSize:10];
    self.timeLabel.textAlignment = NSTextAlignmentCenter;
    self.timeLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.timeLabel];

    // Added last so no content can cover the collapse target.
    self.collapseButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.collapseButton addTarget:self action:@selector(collapseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.collapseButton];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:kNotificationMusicPlaybackStateChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshProgress) name:kNotificationMusicPlaybackProgressChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:kNotificationThemeDidChange object:nil];
    [self applyTheme];
    [self refresh];
}

// On iOS 7+ the modally presented view extends under the transparent status
// bar; on iOS 6 the system already positions it below the status bar.
- (CGFloat)topInset {
    return [self respondsToSelector:@selector(topLayoutGuide)] ? 20.0 : 0.0;
}

- (void)applyTheme {
    self.view.backgroundColor = [OETheme libraryBackgroundColor];
    // The overlay keeps text readable over the blurred artwork; without
    // artwork the plain background color shows through instead.
    self.blurOverlay.backgroundColor = [OETheme isLight] ? [UIColor colorWithWhite:1.0 alpha:0.5]
                                                         : [UIColor colorWithWhite:0.0 alpha:0.5];
    self.artworkView.backgroundColor = [UIColor clearColor];
    self.titleLabel.textColor = [OETheme primaryTextColor];
    self.artistLabel.textColor = [OETheme secondaryTextColor];
    self.badgeLabel.textColor = [OETheme accentColor];
    self.badgeLabel.layer.borderColor = [OETheme accentColor].CGColor;
    self.statusLabel.textColor = [OETheme accentColor];
    self.timeLabel.textColor = [OETheme secondaryTextColor];
    self.lyricsTable.backgroundColor = [UIColor clearColor];
    self.lyricsEmptyLabel.textColor = [OETheme secondaryTextColor];
    [OETheme applyToBarsInView:self.bottomBar];
    // The toolbar now hosts the native transport items, so its tint paints
    // the glyphs. applyToBarsInView points tintColor at the bar colour, which
    // would make the items invisible on iOS 7+ where barTintColor paints the
    // bar and tintColor only the items.
    if ([self.bottomChrome respondsToSelector:@selector(setBarTintColor:)]) {
        self.bottomChrome.barTintColor = [OETheme navigationBarColor];
        self.bottomChrome.tintColor = [OETheme primaryTextColor];
    }
    [self refresh];
    [self.lyricsTable reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat topInset = [self topInset];

    self.backgroundImageView.frame = self.view.bounds;
    self.blurOverlay.frame = self.view.bounds;
    self.collapseButton.frame = CGRectMake(4, topInset + 4, 44, 44);

    [self layoutBottomBarWithWidth:w height:h];
    CGFloat barH = self.bottomBar.frame.size.height;
    self.timeLabel.frame = CGRectMake(0, h - barH - 16, w, 12);
    CGFloat bottomReserved = barH + 16 + 6;

    if (w > h) {
        [self layoutLandscapeWithWidth:w height:h topInset:topInset bottomReserved:bottomReserved];
    } else {
        [self layoutPortraitWithWidth:w height:h topInset:topInset bottomReserved:bottomReserved];
    }
    self.lyricsEmptyLabel.frame = self.lyricsTable.bounds;
}

// One row, one centerline. The toolbar lays out the native transport itself,
// and every other control is then placed on the centerline *measured from
// those transport buttons* — not an assumed one — so the volume track, the
// progress track and the three drawn buttons always line up with play/pause.
- (void)layoutBottomBarWithWidth:(CGFloat)w height:(CGFloat)h {
    CGFloat barH = 56;
    self.bottomBar.frame = CGRectMake(0, h - barH, w, barH);
    self.bottomChrome.frame = self.bottomBar.bounds;

    CGRect transport = [self transportClusterRect];
    CGFloat cy = barH / 2.0;
    if (!CGRectIsNull(transport)) {
        CGFloat measured = CGRectGetMidY(transport);
        // Only trust a plausible reading; a bad one would tilt the whole row.
        if (measured > barH * 0.25 && measured < barH * 0.75) cy = measured;
    }
    // The native transport lives inside the toolbar; never draw over it.
    CGFloat leftEdge = (CGRectIsNull(transport) ? MIN(w * 0.5, 154.0) : CGRectGetMaxX(transport)) + 8.0;

    // Auxiliary cluster against the trailing edge, left to right: volume,
    // play mode, favorite, play queue. Native transport items are wide (they
    // grow further on iOS 7+), so on tight rows the auxiliary controls shrink
    // — volume first, then the buttons — instead of running off the bar.
    BOOL wide = w >= 480;
    CGFloat aux = wide ? 30 : 24;
    CGFloat auxGap = wide ? 8 : 6;
    CGFloat volW = wide ? 68 : 34;
    CGFloat volGap = wide ? 10 : 6;
    CGFloat clusterW = volW + volGap + aux * 3 + auxGap * 2;
    CGFloat maxClusterW = MAX(96.0, w - 8 - leftEdge - 56.0);
    if (clusterW > maxClusterW) {
        volW = MAX(30.0, volW - (clusterW - maxClusterW));
        clusterW = volW + volGap + aux * 3 + auxGap * 2;
        if (clusterW > maxClusterW) {
            aux = MAX(22.0, aux - (clusterW - maxClusterW) / 3.0);
            auxGap = MAX(4.0, auxGap - 2.0);
            clusterW = volW + volGap + aux * 3 + auxGap * 2;
        }
    }
    CGFloat rx = MAX(leftEdge + 8.0, w - 8 - clusterW);
    // MPVolumeView draws its inner slider centered in its own frame, so a
    // symmetric, slider-height frame puts its track on cy as well.
    self.volumeView.frame = CGRectMake(rx, cy - 17, volW, 34);
    CGFloat bx = rx + volW + volGap;
    self.repeatButton.frame = CGRectMake(bx, cy - aux / 2.0, aux, aux);
    self.favoriteButton.frame = CGRectMake(bx + aux + auxGap, cy - aux / 2.0, aux, aux);
    self.queueButton.frame = CGRectMake(bx + (aux + auxGap) * 2, cy - aux / 2.0, aux, aux);

    // Progress: centered on the bar's midpoint and as long as the gap between
    // the two clusters allows. Wide screens get a long, genuinely centered
    // track; narrow ones shrink it instead of letting it collide.
    CGFloat rightEdge = rx - 8;
    CGFloat avail = MAX(24.0, rightEdge - leftEdge);
    CGFloat cap = wide ? MIN(420.0, w * 0.55) : 280.0;
    CGFloat sliderW = MAX(24.0, MIN(cap, avail));
    CGFloat sx = w / 2.0 - sliderW / 2.0;
    if (sx < leftEdge) sx = leftEdge;
    if (sx + sliderW > rightEdge) sx = MAX(leftEdge, rightEdge - sliderW);
    self.progressSlider.frame = CGRectMake(sx, cy - 15, sliderW, 30);
}

- (void)layoutPortraitWithWidth:(CGFloat)w height:(CGFloat)h topInset:(CGFloat)topInset bottomReserved:(CGFloat)bottomReserved {
    CGFloat y = topInset + 44;
    self.titleLabel.frame = CGRectMake(56, y, w - 112, 22); y += 24;
    self.artistLabel.frame = CGRectMake(56, y, w - 112, 16); y += 20;
    y = [self layoutBadgeAndStatusRowAtY:y centerX:w / 2.0] + 8;

    CGFloat lyricsMin = 56;
    CGFloat avail = h - bottomReserved - lyricsMin - y - 10;
    CGFloat side = MIN(w - 96, MIN(300, avail));
    side = MAX(72, side);
    self.artworkView.frame = CGRectMake((w - side) / 2.0, y, side, side);
    y += side + 8;
    self.lyricsTable.frame = CGRectMake(16, y, w - 32, MAX(40, h - bottomReserved - y - 2));
}

- (void)layoutLandscapeWithWidth:(CGFloat)w height:(CGFloat)h topInset:(CGFloat)topInset bottomReserved:(CGFloat)bottomReserved {
    CGFloat paneTop = topInset + 44; // keep clear of the collapse button
    CGFloat paneBottom = h - bottomReserved;
    CGFloat paneH = MAX(80, paneBottom - paneTop);
    CGFloat leftW = MIN(w * 0.40, paneH + 60);

    CGFloat side = MIN(paneH - 16, leftW - 32);
    side = MAX(64, side);
    CGFloat ax = (leftW - side) / 2.0;
    CGFloat ay = paneTop + (paneH - side) / 2.0;
    self.artworkView.frame = CGRectMake(ax, ay, side, side);

    CGFloat rx = leftW + 8;
    CGFloat rw = w - rx - 16;
    CGFloat ry = paneTop + 2;
    self.titleLabel.frame = CGRectMake(rx, ry, rw, 24); ry += 27;
    self.artistLabel.frame = CGRectMake(rx, ry, rw, 17); ry += 21;
    ry = [self layoutBadgeAndStatusRowAtY:ry centerX:rx + rw / 2.0] + 8;
    self.lyricsTable.frame = CGRectMake(rx + 8, ry, rw - 16, MAX(40, paneBottom - ry - 2));
}

// Centers the quality badge, with the transient status text ("正在缓冲…")
// trailing it; the pair is centered as a group. Returns the Y below the row.
- (CGFloat)layoutBadgeAndStatusRowAtY:(CGFloat)y centerX:(CGFloat)centerX {
    CGSize badgeFit = [self.badgeLabel sizeThatFits:CGSizeMake(200, 16)];
    CGFloat badgeW = MAX(34, badgeFit.width + 12);
    BOOL hasStatus = self.statusLabel.text.length > 0;
    CGSize statusFit = hasStatus ? [self.statusLabel sizeThatFits:CGSizeMake(160, 16)] : CGSizeZero;
    CGFloat total = badgeW + (hasStatus ? 8 + statusFit.width : 0);
    CGFloat x = centerX - total / 2.0;
    self.badgeLabel.frame = CGRectMake(x, y, badgeW, 16);
    self.statusLabel.frame = hasStatus ? CGRectMake(x + badgeW + 8, y + 1, statusFit.width, 14) : CGRectZero;
    return y + 20;
}

#pragma mark - Blurred background

// Renders the artwork into a small thumbnail, then box-blurs it with
// vImage (Accelerate) — the standard iOS 6 approach, with no dependency on
// CIFilter availability. Blurring ~96px is cheap even on an iPhone 4, and
// once the image view scales it back up the result is indistinguishable
// from blurring the full-size cover. Runs on a background queue.
- (UIImage *)blurredImageFromImage:(UIImage *)image {
    CGImageRef cg = image.CGImage;
    if (!cg) return nil;
    size_t srcW = CGImageGetWidth(cg), srcH = CGImageGetHeight(cg);
    if (srcW < 1 || srcH < 1) return nil;
    CGFloat scale = 96.0 / MAX(srcW, srcH);
    size_t tw = MAX(1, (size_t)(srcW * scale));
    size_t th = MAX(1, (size_t)(srcH * scale));
    size_t rowBytes = tw * 4;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    uint32_t bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
    CGContextRef inContext = CGBitmapContextCreate(NULL, tw, th, 8, rowBytes, colorSpace, bitmapInfo);
    if (!inContext) { CGColorSpaceRelease(colorSpace); return nil; }
    CGContextDrawImage(inContext, CGRectMake(0, 0, tw, th), cg);

    void *outData = malloc(th * rowBytes);
    if (!outData) {
        CGContextRelease(inContext);
        CGColorSpaceRelease(colorSpace);
        return nil;
    }
    vImage_Buffer inBuffer = { CGBitmapContextGetData(inContext), th, tw, rowBytes };
    vImage_Buffer outBuffer = { outData, th, tw, rowBytes };
    // Two box-blur passes approximate a Gaussian. Edge-extend keeps the
    // borders from darkening into a vignette. The box must be odd and
    // smaller than the thumbnail.
    uint32_t boxSize = 11;
    size_t minDim = MIN(tw, th);
    if (boxSize >= minDim) boxSize = minDim > 2 ? (uint32_t)((minDim - 1) | 1) : 1;
    vImage_Error err = vImageBoxConvolve_ARGB8888(&inBuffer, &outBuffer, NULL, 0, 0, boxSize, boxSize, NULL, kvImageEdgeExtend);
    if (err == kvImageNoError) err = vImageBoxConvolve_ARGB8888(&outBuffer, &inBuffer, NULL, 0, 0, boxSize, boxSize, NULL, kvImageEdgeExtend);
    free(outData);
    if (err != kvImageNoError) {
        CGContextRelease(inContext);
        CGColorSpaceRelease(colorSpace);
        return nil;
    }
    // The second pass wrote back into inContext's buffer.
    CGImageRef blurred = CGBitmapContextCreateImage(inContext);
    CGContextRelease(inContext);
    CGColorSpaceRelease(colorSpace);
    if (!blurred) return nil;
    UIImage *result = [UIImage imageWithCGImage:blurred];
    CGImageRelease(blurred);
    return result;
}

- (void)updateBlurredBackground {
    UIImage *artwork = [OEMusicPlaybackManager sharedManager].artwork;
    if (artwork == self.blurredSourceImage) return;
    self.blurredSourceImage = artwork;
    if (!artwork) {
        self.backgroundImageView.image = nil;
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *blurred = [self blurredImageFromImage:artwork];
        dispatch_async(dispatch_get_main_queue(), ^{
            // A newer track may have replaced the artwork while blurring.
            if (self.blurredSourceImage != artwork) return;
            self.backgroundImageView.image = blurred;
        });
    });
}

#pragma mark - Refresh

- (void)refresh {
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    OEEmbyItem *item = manager.currentItem;
    self.titleLabel.text = item.name ?: @"未播放";
    self.artistLabel.text = item.artist ?: item.album ?: @"";
    // Transient states only; steady "正在播放/已暂停" adds no information here.
    BOOL transient = manager.state == OEMusicPlaybackStateLoading || manager.state == OEMusicPlaybackStateBuffering || manager.state == OEMusicPlaybackStateFailed;
    self.statusLabel.text = transient ? (manager.statusText ?: @"") : @"";
    self.artworkView.image = manager.artwork;
    [self updateBlurredBackground];

    OETranscodeSettings *settings = [OETranscodeSettings sharedSettings];
    self.badgeLabel.text = settings.directPlay ? @"直连" : [NSString stringWithFormat:@"%ldk", (long)(settings.maxAudioBitrate / 1000)];

    // Native transport: swap the toolbar's play/pause system item in place.
    [self updatePlayPauseItem];
    [self updateRepeatButton];
    [self.queueButton setImage:[OEIconFactory imageForIconType:OEIconTypeList size:CGSizeMake(20, 20) color:[OETheme secondaryTextColor]] forState:UIControlStateNormal];
    [self updateFavoriteButton];
    [self.collapseButton setImage:[OEIconFactory imageForIconType:OEIconTypeChevronDown size:CGSizeMake(24, 24) color:[OETheme secondaryTextColor]] forState:UIControlStateNormal];

    [self requestLyricsForItemIfNeeded:item];
    [self refreshProgress];
    [self.view setNeedsLayout];
}

- (void)updateFavoriteButton {
    OEEmbyItem *item = [OEMusicPlaybackManager sharedManager].currentItem;
    BOOL fav = item.favorite;
    OEIconType icon = fav ? OEIconTypeHeartFilled : OEIconTypeHeart;
    UIColor *color = fav ? [OETheme accentColor] : [OETheme secondaryTextColor];
    [self.favoriteButton setImage:[OEIconFactory imageForIconType:icon size:CGSizeMake(20, 20) color:color] forState:UIControlStateNormal];
}

// Each play mode gets its own Apple-Music-style glyph: the plain loop for
// repeat-all, the loop with a "1" for repeat-one, and a slashed loop for the
// off state. Off is additionally drawn in the muted colour.
- (void)updateRepeatButton {
    OEMusicRepeatMode mode = [OEMusicPlaybackManager sharedManager].repeatMode;
    OEIconType icon = OEIconTypeRepeatOff;
    if (mode == OEMusicRepeatModeAll) icon = OEIconTypeRepeat;
    else if (mode == OEMusicRepeatModeOne) icon = OEIconTypeRepeatOne;
    UIColor *color = mode == OEMusicRepeatModeOff ? [OETheme secondaryTextColor] : [OETheme accentColor];
    [self.repeatButton setImage:[OEIconFactory imageForIconType:icon size:CGSizeMake(21, 21) color:color] forState:UIControlStateNormal];
}

- (void)requestLyricsForItemIfNeeded:(OEEmbyItem *)item {
    if (!item.itemId.length || [item.itemId isEqualToString:self.lyricsItemId]) return;
    self.lyricsItemId = item.itemId;
    self.lyrics = @[];
    self.highlightedLyricsIndex = NSNotFound;
    self.lyricsEmptyLabel.text = @"正在加载歌词…";
    self.lyricsEmptyLabel.hidden = NO;
    [self.lyricsTable reloadData];
    NSString *itemId = [item.itemId copy];
    [[OEEmbyAPIClient sharedClient] fetchLyricsForAudioItem:item completion:^(id result, NSError *error) {
        if (![itemId isEqualToString:self.lyricsItemId]) return;
        if ([result isKindOfClass:[NSString class]]) {
            self.lyrics = [OELyricsLine linesFromTextSubtitleString:result];
        } else {
            self.lyrics = error ? @[] : [OELyricsLine linesFromEmbyResponse:result];
        }
        self.lyricsEmptyLabel.text = self.lyrics.count ? @"" : @"此歌曲暂无可显示歌词";
        self.lyricsEmptyLabel.hidden = self.lyrics.count > 0;
        [self.lyricsTable reloadData];
        [self updateHighlightedLyricsAtTime:[OEMusicPlaybackManager sharedManager].currentTime scroll:NO];
    }];
}

- (void)refreshProgress {
    if (self.seeking) return;
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    // Suppress the ValueChanged event so setting the value programmatically
    // does not re-trigger sliderChanged: and create a feedback loop.
    self.progressSlider.userInteractionEnabled = NO;
    self.progressSlider.value = manager.progress;
    self.progressSlider.userInteractionEnabled = YES;
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [self stringForTime:manager.currentTime], [self stringForTime:manager.duration]];
    [self updateHighlightedLyricsAtTime:manager.currentTime scroll:YES];
}

- (void)updateHighlightedLyricsAtTime:(NSTimeInterval)time scroll:(BOOL)scroll {
    NSInteger selected = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)self.lyrics.count; i++) {
        OELyricsLine *line = self.lyrics[i];
        if (line.startTime <= time) selected = i;
        else break;
    }
    if (selected == self.highlightedLyricsIndex) return;
    NSInteger previous = self.highlightedLyricsIndex;
    self.highlightedLyricsIndex = selected;
    NSMutableArray *reload = [NSMutableArray array];
    if (previous != NSNotFound && previous < (NSInteger)self.lyrics.count) [reload addObject:[NSIndexPath indexPathForRow:previous inSection:0]];
    if (selected != NSNotFound) [reload addObject:[NSIndexPath indexPathForRow:selected inSection:0]];
    if (reload.count) [self.lyricsTable reloadRowsAtIndexPaths:reload withRowAnimation:UITableViewRowAnimationNone];
    if (scroll && selected != NSNotFound) {
        [self.lyricsTable scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:selected inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
}

- (NSString *)stringForTime:(NSTimeInterval)time {
    if (!isfinite(time) || time < 0) return @"--:--";
    NSInteger seconds = (NSInteger)time;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}

#pragma mark - Actions

- (void)collapseTapped {
    // On iOS 6 sending dismiss to the presented VC forwards to the presenter.
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)playPauseTapped { [[OEMusicPlaybackManager sharedManager] togglePlayPause]; }
- (void)previousTapped { [[OEMusicPlaybackManager sharedManager] previous]; }
- (void)nextTapped { [[OEMusicPlaybackManager sharedManager] next]; }

- (void)repeatTapped {
    [[OEMusicPlaybackManager sharedManager] cycleRepeatMode];
}

- (void)queueTapped {
    OEMusicPlayQueueViewController *queue = [[OEMusicPlayQueueViewController alloc] initWithStyle:UITableViewStylePlain];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:queue];
    nav.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    [OETheme applyToNavigationBar:nav.navigationBar];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)favoriteTapped {
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    OEEmbyItem *item = manager.currentItem;
    if (!item.itemId.length || self.favoriteRequestInFlight) return;
    BOOL target = !item.favorite;
    self.favoriteRequestInFlight = YES;
    // Optimistic icon flip; reverted if the server call fails.
    OEIconType optimisticIcon = target ? OEIconTypeHeartFilled : OEIconTypeHeart;
    UIColor *optimisticColor = target ? [OETheme accentColor] : [OETheme secondaryTextColor];
    [self.favoriteButton setImage:[OEIconFactory imageForIconType:optimisticIcon size:CGSizeMake(20, 20) color:optimisticColor] forState:UIControlStateNormal];
    __weak typeof(self) weakSelf = self;
    [[OEEmbyAPIClient sharedClient] setItem:item.itemId favorite:target completion:^(id result, NSError *error) {
        weakSelf.favoriteRequestInFlight = NO;
        if (error) {
            [weakSelf updateFavoriteButton];
            [OEErrorAlertView showWithTitle:target ? @"收藏失败" : @"取消收藏失败" error:error];
            return;
        }
        item.favorite = target;
        if (manager.currentItem == item) [weakSelf updateFavoriteButton];
    }];
}

- (void)sliderTouchDown {
    // Freeze the periodic progress feed for the whole gesture. Dragging stays
    // entirely on the slider's own value until the finger lifts, which is
    // what makes the thumb track the finger instead of snapping back.
    self.seeking = YES;
}
- (void)sliderChanged:(UISlider *)slider {
    OEMusicPlaybackManager *manager = [OEMusicPlaybackManager sharedManager];
    NSTimeInterval previewTime = slider.value * manager.duration;
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [self stringForTime:previewTime], [self stringForTime:manager.duration]];
    [self updateHighlightedLyricsAtTime:previewTime scroll:NO];
}
- (void)sliderTouchUp {
    // Committed by TouchUpInside/TouchUpOutside/TouchCancel only; guard
    // against a second event firing for the same gesture.
    if (!self.seeking) return;
    float progress = self.progressSlider.value;
    __weak typeof(self) weakSelf = self;
    [[OEMusicPlaybackManager sharedManager] seekToProgress:progress completion:^(BOOL finished) {
        // The manager clears its own seeking flag after a delay; clear the
        // VC flag here too so refreshProgress can resume updating.
        weakSelf.seeking = NO;
        [weakSelf refreshProgress];
    }];
}

#pragma mark - Lyrics table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.lyrics.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"LyricsLine";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [UIFont systemFontOfSize:13];
        cell.textLabel.backgroundColor = [UIColor clearColor];
    }
    OELyricsLine *line = self.lyrics[indexPath.row];
    cell.textLabel.text = line.text;
    BOOL current = indexPath.row == self.highlightedLyricsIndex;
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = current ? [OETheme accentColor] : [OETheme secondaryTextColor];
    cell.textLabel.font = current ? [UIFont boldSystemFontOfSize:14] : [UIFont systemFontOfSize:13];
    return cell;
}

#pragma mark - Visibility

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationMusicFullPlayerVisibilityChanged object:self];
    [self refresh];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Defer the visibility notification until the dismiss animation has started
    // so OERootTabBarController re-shows the mini player only once the player
    // is actually leaving. Post with object:nil and avoid capturing self so
    // this VC can deallocate promptly.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationMusicFullPlayerVisibilityChanged object:nil];
    });
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end
