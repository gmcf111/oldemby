#import "OEIconFactory.h"
#import <math.h>

@implementation OEIconFactory

+ (UIImage *)imageForIconType:(OEIconType)type size:(CGSize)size color:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    UIColor *drawColor = color ?: [UIColor whiteColor];
    CGContextSetStrokeColorWithColor(ctx, drawColor.CGColor);
    CGContextSetFillColorWithColor(ctx, drawColor.CGColor);
    CGContextSetLineWidth(ctx, MAX(1.5, size.width * 0.09));
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);

    CGFloat w = size.width;
    CGFloat h = size.height;
    switch (type) {
        case OEIconTypeVideo: {
            CGRect body = CGRectMake(w * 0.08, h * 0.24, w * 0.58, h * 0.52);
            CGContextStrokeRect(ctx, body);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, w * 0.68, h * 0.36);
            CGContextAddLineToPoint(ctx, w * 0.92, h * 0.25);
            CGContextAddLineToPoint(ctx, w * 0.92, h * 0.75);
            CGContextAddLineToPoint(ctx, w * 0.68, h * 0.64);
            CGContextClosePath(ctx);
            CGContextStrokePath(ctx);
            break;
        }
        case OEIconTypeMusic: {
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, w * 0.60, h * 0.18);
            CGContextAddLineToPoint(ctx, w * 0.60, h * 0.68);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, w * 0.60, h * 0.20);
            CGContextAddLineToPoint(ctx, w * 0.87, h * 0.12);
            CGContextStrokePath(ctx);
            CGContextFillEllipseInRect(ctx, CGRectMake(w * 0.17, h * 0.56, w * 0.30, h * 0.25));
            CGContextFillEllipseInRect(ctx, CGRectMake(w * 0.47, h * 0.56, w * 0.30, h * 0.25));
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, w * 0.60, h * 0.46);
            CGContextAddLineToPoint(ctx, w * 0.87, h * 0.38);
            CGContextAddLineToPoint(ctx, w * 0.87, h * 0.62);
            CGContextStrokePath(ctx);
            break;
        }
        case OEIconTypeSettings: {
            CGFloat cx = w / 2.0, cy = h / 2.0;
            CGContextStrokeEllipseInRect(ctx, CGRectMake(w * 0.27, h * 0.27, w * 0.46, h * 0.46));
            CGContextStrokeEllipseInRect(ctx, CGRectMake(w * 0.42, h * 0.42, w * 0.16, h * 0.16));
            for (NSInteger i = 0; i < 8; i++) {
                CGFloat a = (CGFloat)i * M_PI / 4.0;
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, cx + cos(a) * w * 0.30, cy + sin(a) * h * 0.30);
                CGContextAddLineToPoint(ctx, cx + cos(a) * w * 0.43, cy + sin(a) * h * 0.43);
                CGContextStrokePath(ctx);
            }
            break;
        }
        case OEIconTypePlay: {
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, w * 0.30, h * 0.18);
            CGContextAddLineToPoint(ctx, w * 0.78, h * 0.50);
            CGContextAddLineToPoint(ctx, w * 0.30, h * 0.82);
            CGContextClosePath(ctx);
            CGContextFillPath(ctx);
            break;
        }
        case OEIconTypePause: {
            CGContextFillRect(ctx, CGRectMake(w * 0.27, h * 0.19, w * 0.18, h * 0.62));
            CGContextFillRect(ctx, CGRectMake(w * 0.57, h * 0.19, w * 0.18, h * 0.62));
            break;
        }
        case OEIconTypePrevious:
        case OEIconTypeNext: {
            BOOL previous = type == OEIconTypePrevious;
            CGFloat x0 = previous ? w * 0.70 : w * 0.30;
            CGFloat x1 = previous ? w * 0.30 : w * 0.70;
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, x0, h * 0.20);
            CGContextAddLineToPoint(ctx, x1, h * 0.50);
            CGContextAddLineToPoint(ctx, x0, h * 0.80);
            CGContextClosePath(ctx);
            CGContextFillPath(ctx);
            CGFloat lineX = previous ? w * 0.22 : w * 0.78;
            CGContextFillRect(ctx, CGRectMake(lineX - w * 0.04, h * 0.20, w * 0.08, h * 0.60));
            break;
        }
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@end
