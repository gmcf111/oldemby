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
            // Single eighth note — clean oval head + stem + flag, reads well at 30pt.
            CGContextSetLineWidth(ctx, MAX(1.4, w * 0.075));
            CGFloat headW = w * 0.36, headH = h * 0.26;
            CGRect head = CGRectMake(w * 0.18, h * 0.55, headW, headH);
            // Slight tilt for a more musical feel
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, CGRectGetMidX(head), CGRectGetMidY(head));
            CGContextRotateCTM(ctx, -0.18);
            CGContextTranslateCTM(ctx, -CGRectGetMidX(head), -CGRectGetMidY(head));
            CGContextFillEllipseInRect(ctx, head);
            CGContextRestoreGState(ctx);
            CGFloat stemX = w * 0.51;
            CGFloat stemTop = h * 0.18;
            CGFloat stemBot = h * 0.67;
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, stemX, stemBot);
            CGContextAddLineToPoint(ctx, stemX, stemTop);
            CGContextStrokePath(ctx);
            // Flag — filled teardrop curve off the stem top
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, stemX, stemTop);
            CGContextAddCurveToPoint(ctx, stemX + w * 0.22, stemTop + h * 0.04,
                                     stemX + w * 0.24, stemTop + h * 0.18,
                                     stemX + w * 0.02, stemTop + h * 0.22);
            CGContextAddLineToPoint(ctx, stemX, stemTop + h * 0.12);
            CGContextAddCurveToPoint(ctx, stemX + w * 0.10, stemTop + h * 0.10,
                                     stemX + w * 0.08, stemTop + h * 0.02,
                                     stemX, stemTop);
            CGContextClosePath(ctx);
            CGContextFillPath(ctx);
            break;
        }
        case OEIconTypeSettings: {
            // Proper gear — outer ring + 8 rectangular teeth + inner hub.
            CGFloat cx = w / 2.0, cy = h / 2.0;
            CGFloat outerR = w * 0.25;
            CGFloat toothW = w * 0.16;
            CGFloat toothH = w * 0.09;
            CGFloat toothR = outerR + toothH * 0.38;
            // Teeth as filled rects arranged radially
            for (NSInteger i = 0; i < 8; i++) {
                CGFloat a = (CGFloat)i * M_PI / 4.0;
                CGContextSaveGState(ctx);
                CGContextTranslateCTM(ctx, cx, cy);
                CGContextRotateCTM(ctx, a);
                CGRect tooth = CGRectMake(toothR, -toothW / 2.0, toothH, toothW);
                CGFloat cr = toothW * 0.22;
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, tooth.origin.x + cr, tooth.origin.y);
                CGContextAddLineToPoint(ctx, tooth.origin.x + tooth.size.width - cr, tooth.origin.y);
                CGContextAddArcToPoint(ctx, tooth.origin.x + tooth.size.width, tooth.origin.y,
                                       tooth.origin.x + tooth.size.width, tooth.origin.y + cr, cr);
                CGContextAddLineToPoint(ctx, tooth.origin.x + tooth.size.width, tooth.origin.y + tooth.size.height - cr);
                CGContextAddArcToPoint(ctx, tooth.origin.x + tooth.size.width, tooth.origin.y + tooth.size.height,
                                       tooth.origin.x + tooth.size.width - cr, tooth.origin.y + tooth.size.height, cr);
                CGContextAddLineToPoint(ctx, tooth.origin.x + cr, tooth.origin.y + tooth.size.height);
                CGContextAddArcToPoint(ctx, tooth.origin.x, tooth.origin.y + tooth.size.height,
                                       tooth.origin.x, tooth.origin.y + tooth.size.height - cr, cr);
                CGContextAddLineToPoint(ctx, tooth.origin.x, tooth.origin.y + cr);
                CGContextAddArcToPoint(ctx, tooth.origin.x, tooth.origin.y,
                                       tooth.origin.x + cr, tooth.origin.y, cr);
                CGContextClosePath(ctx);
                CGContextFillPath(ctx);
                CGContextRestoreGState(ctx);
            }
            CGContextSetLineWidth(ctx, MAX(1.4, w * 0.07));
            CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - outerR, cy - outerR, outerR * 2, outerR * 2));
            CGFloat innerR = w * 0.11;
            CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - innerR, cy - innerR, innerR * 2, innerR * 2));
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
        case OEIconTypeChevronDown: {
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, w * 0.20, h * 0.32);
            CGContextAddLineToPoint(ctx, w * 0.50, h * 0.62);
            CGContextAddLineToPoint(ctx, w * 0.80, h * 0.32);
            CGContextStrokePath(ctx);
            break;
        }
        case OEIconTypeHeart:
        case OEIconTypeHeartFilled: {
            // Symmetric cubic heart: bottom tip -> left flank -> left lobe ->
            // center dip, mirrored on the right. Inset keeps the stroke inside
            // the bitmap.
            CGFloat ix = w * 0.12, iy = h * 0.10;
            CGFloat hw = w - ix * 2, hh = h - iy * 2;
            CGFloat x0 = ix, x1 = ix + hw;          // left/right extremes
            CGFloat yT = iy, yB = iy + hh;          // top/bottom
            CGFloat cx = ix + hw * 0.5;
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, cx, yT + hh * 0.92);                                    // bottom tip
            CGContextAddCurveToPoint(ctx, ix + hw * 0.15, yT + hh * 0.70,
                                          x0,                 yT + hh * 0.55,
                                          x0,                 yT + hh * 0.32);                // left flank
            CGContextAddCurveToPoint(ctx, x0,                 yT + hh * 0.06,
                                          ix + hw * 0.20,     yT,
                                          ix + hw * 0.38,     yT + hh * 0.02);                // left lobe crest
            CGContextAddCurveToPoint(ctx, ix + hw * 0.48,     yT + hh * 0.02,
                                          cx,                 yT + hh * 0.10,
                                          cx,                 yT + hh * 0.28);                // center dip
            CGContextAddCurveToPoint(ctx, cx,                 yT + hh * 0.10,
                                          ix + hw * 0.52,     yT + hh * 0.02,
                                          ix + hw * 0.62,     yT + hh * 0.02);                // dip -> right lobe
            CGContextAddCurveToPoint(ctx, ix + hw * 0.80,     yT,
                                          x1,                 yT + hh * 0.06,
                                          x1,                 yT + hh * 0.32);                // right lobe crest
            CGContextAddCurveToPoint(ctx, x1,                 yT + hh * 0.55,
                                          ix + hw * 0.85,     yT + hh * 0.70,
                                          cx,                 yT + hh * 0.92);                // right flank
            CGContextClosePath(ctx);
            if (type == OEIconTypeHeartFilled) CGContextFillPath(ctx);
            else CGContextStrokePath(ctx);
            break;
        }
        case OEIconTypeRepeat:
        case OEIconTypeRepeatOne: {
            // Two chasing arrows forming a loop.
            CGContextSetLineWidth(ctx, MAX(1.4, w * 0.08));
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, w * 0.28, h * 0.36);
            CGContextAddLineToPoint(ctx, w * 0.78, h * 0.36);
            CGContextAddCurveToPoint(ctx, w * 0.86, h * 0.36, w * 0.86, h * 0.44, w * 0.86, h * 0.50);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, w * 0.72, h * 0.64);
            CGContextAddLineToPoint(ctx, w * 0.22, h * 0.64);
            CGContextAddCurveToPoint(ctx, w * 0.14, h * 0.64, w * 0.14, h * 0.56, w * 0.14, h * 0.50);
            CGContextStrokePath(ctx);
            // Arrowheads
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, w * 0.20, h * 0.28);
            CGContextAddLineToPoint(ctx, w * 0.30, h * 0.36);
            CGContextAddLineToPoint(ctx, w * 0.20, h * 0.44);
            CGContextStrokePath(ctx);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, w * 0.80, h * 0.72);
            CGContextAddLineToPoint(ctx, w * 0.70, h * 0.64);
            CGContextAddLineToPoint(ctx, w * 0.80, h * 0.56);
            CGContextStrokePath(ctx);
            if (type == OEIconTypeRepeatOne) {
                // "1" badge centered in the loop.
                CGContextSetLineWidth(ctx, MAX(1.2, w * 0.06));
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, w * 0.46, h * 0.47);
                CGContextAddLineToPoint(ctx, w * 0.51, h * 0.43);
                CGContextAddLineToPoint(ctx, w * 0.51, h * 0.58);
                CGContextStrokePath(ctx);
            }
            break;
        }
        case OEIconTypeList: {
            // Queue list: three bullet dots + three lines.
            CGContextSetLineWidth(ctx, MAX(1.4, w * 0.08));
            for (NSInteger i = 0; i < 3; i++) {
                CGFloat y = h * (0.28 + 0.22 * i);
                CGContextFillEllipseInRect(ctx, CGRectMake(w * 0.16, y - w * 0.035, w * 0.07, w * 0.07));
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, w * 0.32, y);
                CGContextAddLineToPoint(ctx, w * 0.84, y);
                CGContextStrokePath(ctx);
            }
            break;
        }
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@end
