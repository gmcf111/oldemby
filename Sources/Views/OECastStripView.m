#import "OECastStripView.h"
#import "Models/OECastItem.h"
#import "Services/OEImageCache.h"
#import "Services/OEEmbyAPIClient.h"
#import "Models/OEServerConfig.h"
#import "OETheme.h"

// Layout constants
static const CGFloat kCastPhotoSize = 72.0;
static const CGFloat kCastCellWidth = 84.0;
static const CGFloat kCastStripHeight = 110.0;
static const CGFloat kCastPadding = 8.0;

@interface OECastStripView ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *noCastLabel;
@property (nonatomic, strong) NSMutableArray *imageViews;
@property (nonatomic, strong) NSMutableArray *nameLabels;
@property (nonatomic, strong) NSMutableArray *placeholderTags; // track item IDs
@end

@implementation OECastStripView

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];

        _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scrollView.showsHorizontalScrollIndicator = NO;
        [self addSubview:_scrollView];

        _noCastLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _noCastLabel.font = [UIFont systemFontOfSize:12];
        _noCastLabel.textColor = [OETheme secondaryTextColor];
        _noCastLabel.backgroundColor = [UIColor clearColor];
        _noCastLabel.text = @"暂无演职人员";
        _noCastLabel.textAlignment = NSTextAlignmentCenter;
        _noCastLabel.hidden = YES;
        [self addSubview:_noCastLabel];

        _imageViews = [NSMutableArray array];
        _nameLabels = [NSMutableArray array];
        _placeholderTags = [NSMutableArray array];
    }
    return self;
}

- (void)setCasts:(NSArray *)casts {
    _casts = casts;
    [self reloadData];
}

- (void)reloadData {
    // Remove all old subviews from scrollView
    for (UIView *v in [_scrollView.subviews copy]) [v removeFromSuperview];
    [_imageViews removeAllObjects];
    [_nameLabels removeAllObjects];
    [_placeholderTags removeAllObjects];

    NSArray *casts = self.casts ?: @[];

    if (casts.count == 0) {
        _noCastLabel.hidden = NO;
        _noCastLabel.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
        _scrollView.contentSize = CGSizeZero;
        return;
    }
    _noCastLabel.hidden = YES;

    CGFloat x = kCastPadding;
    CGFloat contentWidth = kCastPadding;

    for (NSInteger i = 0; i < casts.count; i++) {
        OECastItem *cast = casts[i];

        // Photo (circular)
        UIImageView *imgView = [[UIImageView alloc] initWithFrame:CGRectMake(x, 0, kCastPhotoSize, kCastPhotoSize)];
        imgView.contentMode = UIViewContentModeScaleAspectFill;
        imgView.clipsToBounds = YES;
        imgView.layer.cornerRadius = kCastPhotoSize / 2.0;
        imgView.layer.borderWidth = 0.5;
        imgView.layer.borderColor = [OETheme separatorColor].CGColor;
        imgView.backgroundColor = [OETheme imagePlaceholderColor];
        imgView.tag = i;
        [self.scrollView addSubview:imgView];
        [_imageViews addObject:imgView];

        // Name label
        UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, kCastPhotoSize + 4, kCastCellWidth, 34)];
        nameLabel.font = [UIFont systemFontOfSize:11];
        nameLabel.textColor = [OETheme primaryTextColor];
        nameLabel.backgroundColor = [UIColor clearColor];
        nameLabel.numberOfLines = 2;
        nameLabel.textAlignment = NSTextAlignmentCenter;
        nameLabel.text = cast.name ?: @"";
        [self.scrollView addSubview:nameLabel];
        [_nameLabels addObject:nameLabel];

        // Track the person ID for async image callback validation
        [_placeholderTags addObject:cast.personId ?: @""];

        // Load image
        if (cast.personId.length && cast.primaryImageTag.length) {
            NSString *url = [[OEEmbyAPIClient sharedClient] personImageURLWithHost:[OEServerConfig sharedConfig].baseURL personId:cast.personId tag:cast.primaryImageTag maxWidth:120];
            [[OEImageCache sharedCache] loadImageFromURL:url placeholder:nil completion:^(UIImage *image) {
                if (i < _placeholderTags.count && [cast.personId isEqualToString:_placeholderTags[i]]) {
                    imgView.image = image;
                }
            }];
        }

        x += kCastCellWidth;
        contentWidth = x;
    }

    _scrollView.contentSize = CGSizeMake(contentWidth + kCastPadding, self.bounds.size.height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _scrollView.frame = self.bounds;
    if (self.casts.count == 0) {
        _noCastLabel.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    }
}

@end
