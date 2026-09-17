#import "CMPanel.h"
#import "CMPalette.h"
#import <math.h>

#pragma mark - CMBar

@implementation CMBar

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        _severity = CMSeverityNormal;
    }
    return self;
}

- (void)setFraction:(double)fraction
{
    if (!isfinite(fraction)) fraction = 0;
    if (fraction < 0) fraction = 0;
    if (fraction > 1) fraction = 1;
    if (fabs(fraction - _fraction) < 0.0005) return;
    _fraction = fraction;
    [self setNeedsDisplay];
}

- (void)setSeverity:(CMSeverity)severity
{
    if (_severity == severity) return;
    _severity = severity;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    (void)rect;
    CGRect bounds = self.bounds;
    if (bounds.size.width <= 1 || bounds.size.height <= 1) return;

    CGFloat radius = bounds.size.height * 0.5f;

    UIBezierPath *track = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:radius];
    [[UIColor colorWithWhite:1.0f alpha:0.12f] setFill];
    [track fill];

    CGFloat width = bounds.size.width * (CGFloat)self.fraction;
    if (width < bounds.size.height && self.fraction > 0) width = bounds.size.height;
    if (width <= 0) return;

    CGRect fill = CGRectMake(0, 0, width, bounds.size.height);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:fill cornerRadius:radius];
    [path addClip];

    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context == NULL) return;

    CGFloat parts[2] = {0.0f, 1.0f};
    NSArray *colors = @[(id)[CMPalette deepForSeverity:self.severity].CGColor,
                        (id)[CMPalette tintForSeverity:self.severity].CGColor];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, parts);
    if (gradient != NULL) {
        CGContextDrawLinearGradient(context, gradient,
                                    CGPointMake(0, 0), CGPointMake(width, 0), 0);
        CGGradientRelease(gradient);
    }
    CGColorSpaceRelease(space);
}

@end

#pragma mark - CMPanel

@interface CMPanel ()
{
    UILabel *_plan;
    UILabel *_value;
    UILabel *_reset;
    UILabel *_detail;

    UILabel *_barTitle;
    UILabel *_barValue;
    CMBar *_bar;

    UILabel *_secondTitle;
    UILabel *_secondValue;
    CMBar *_secondBar;

    UILabel *_today;
    UILabel *_quiet;

    BOOL _hasSecond;
    BOOL _waiting;
    CGFloat _contentBottom;
}
@end

@implementation CMPanel

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;

        _plan = [self labelWithSize:10 bold:YES color:[CMPalette faint]];
        _value = [self labelWithSize:58 bold:YES color:[CMPalette clayLight]];
        _reset = [self labelWithSize:12 bold:NO color:[CMPalette faint]];
        _detail = [self labelWithSize:11 bold:NO color:[CMPalette faint]];

        _barTitle = [self labelWithSize:11 bold:YES color:[CMPalette paper]];
        _barValue = [self labelWithSize:11 bold:NO color:[CMPalette faint]];
        _barValue.textAlignment = NSTextAlignmentRight;
        _bar = [[CMBar alloc] initWithFrame:CGRectZero];
        [self addSubview:_bar];

        _secondTitle = [self labelWithSize:10 bold:YES color:[CMPalette paper]];
        _secondValue = [self labelWithSize:10 bold:NO color:[CMPalette faint]];
        _secondValue.textAlignment = NSTextAlignmentRight;
        _secondBar = [[CMBar alloc] initWithFrame:CGRectZero];
        [self addSubview:_secondBar];

        _today = [self labelWithSize:11 bold:NO color:[CMPalette faint]];
        _quiet = [self labelWithSize:11 bold:NO color:[CMPalette amber]];
        _quiet.textAlignment = NSTextAlignmentRight;
        _quiet.alpha = 0;

        _value.adjustsFontSizeToFitWidth = YES;
        _value.minimumScaleFactor = 0.5f;
    }
    return self;
}

- (UILabel *)labelWithSize:(CGFloat)size bold:(BOOL)bold color:(UIColor *)color
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    label.numberOfLines = 1;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:label];
    return label;
}

#pragma mark - Layout

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    if (width <= 0 || height <= 0) return;

    CGFloat margin = 16.0f;
    BOOL wide = (width >= height);

    CGFloat valueSize = wide ? 76.0f : 64.0f;
    CGFloat valueHigh = ceilf(valueSize * 1.08f);
    _value.font = [UIFont boldSystemFontOfSize:valueSize];

    CGFloat barHigh = 13.0f;
    CGFloat secondHigh = 9.0f;

    // The block sits near the top with room to breathe, and what is left underneath is
    // where Clawd walks and where the waiting mark goes.
    CGFloat leftX = margin;
    CGFloat rightX = margin;
    CGFloat leftWidth = width - margin * 2.0f;
    CGFloat rightWidth = leftWidth;
    CGFloat top = wide ? 22.0f : 26.0f;
    CGFloat barY = top;

    CGFloat leftHigh = 13 + 5 + valueHigh + 6 + 17 + 16;

    if (wide) {
        leftWidth = floorf((width - margin * 3.0f) * 0.44f);
        rightX = margin * 2.0f + leftWidth;
        rightWidth = width - rightX - margin;
    }

    // Left: the plan, the number itself, when it comes back, one line of detail.
    CGFloat y = top;
    _plan.frame = CGRectMake(leftX, y, leftWidth, 13);
    y += 18;
    _value.frame = CGRectMake(leftX - 3.0f, y, leftWidth, valueHigh);
    y += valueHigh + 6.0f;
    _reset.frame = CGRectMake(leftX, y, leftWidth, 17);
    y += 18;
    _detail.frame = CGRectMake(leftX, y, leftWidth, 16);
    CGFloat leftBottom = y + 16;

    // Right: every limit named once, with its bar.
    if (!wide) barY = top + leftHigh + 26.0f;

    _barTitle.frame = CGRectMake(rightX, barY, rightWidth * 0.62f, 16);
    _barValue.frame = CGRectMake(rightX + rightWidth * 0.62f, barY, rightWidth * 0.38f, 16);
    barY += 20;
    _bar.frame = CGRectMake(rightX, barY, rightWidth, barHigh);
    barY += barHigh + 18.0f;

    if (_hasSecond) {
        _secondTitle.frame = CGRectMake(rightX, barY, rightWidth * 0.62f, 15);
        _secondValue.frame = CGRectMake(rightX + rightWidth * 0.62f, barY, rightWidth * 0.38f, 15);
        barY += 19;
        _secondBar.frame = CGRectMake(rightX, barY, rightWidth, secondHigh);
        barY += secondHigh + 18.0f;
    } else {
        _secondTitle.frame = CGRectZero;
        _secondValue.frame = CGRectZero;
        _secondBar.frame = CGRectZero;
    }

    // The day total drops to the same line the left column ends on, so the two columns
    // finish together instead of leaving a step.
    CGFloat todayY = wide ? MAX(barY, leftBottom - 16.0f) : barY;
    _today.frame = CGRectMake(rightX, todayY, rightWidth, 16);
    _quiet.frame = CGRectMake(rightX, todayY + 20.0f, rightWidth, 16);

    _contentBottom = MAX(leftBottom, todayY + 20.0f + 16.0f);
}

/// How far down the last line reaches, so the screen can use what is left below it.
- (CGFloat)contentBottom
{
    return _contentBottom;
}

#pragma mark - Filling in

- (void)showUsage:(CMUsage *)usage
{
    if (usage == nil) return;
    _waiting = NO;

    UIColor *tint = [CMPalette tintForSeverity:usage.severity];

    _plan.text = [usage.plan uppercaseString];
    _value.text = usage.value.length > 0 ? usage.value : @"...";
    _value.textColor = tint;

    NSString *reset = [usage resetText];
    _reset.text = reset.length > 0 ? [NSString stringWithFormat:@"resets in %@", reset] : @"";
    _detail.text = usage.detail.length > 0 ? usage.detail : usage.note;

    // The big number already says how much of this one is gone, so the bar only names it.
    _barTitle.text = usage.title.length > 0 ? usage.title : @"limit";
    _barValue.text = @"";
    _bar.severity = usage.severity;
    _bar.fraction = usage.fraction;

    _hasSecond = usage.hasSecond;
    _secondTitle.text = usage.secondTitle;
    _secondValue.text = usage.secondValue;
    _secondBar.severity = usage.secondSeverity;
    _secondBar.fraction = usage.secondFraction;
    _secondTitle.hidden = !_hasSecond;
    _secondValue.hidden = !_hasSecond;
    _secondBar.hidden = !_hasSecond;

    NSString *today = usage.today.length > 0 ? usage.today : @"";
    if (usage.requests > 0) {
        NSString *count = [NSString stringWithFormat:@"%ld %@", (long)usage.requests,
                           usage.requests == 1 ? @"request" : @"requests"];
        today = today.length > 0 ? [NSString stringWithFormat:@"%@ today, %@", today, count]
                                 : [NSString stringWithFormat:@"%@ today", count];
    } else if (today.length > 0) {
        today = [NSString stringWithFormat:@"%@ today", today];
    }
    _today.text = today;

    [self setNeedsLayout];
}

- (void)setOffline:(BOOL)offline
{
    _quiet.text = offline ? @"no answer from the computer" : @"";
    [UIView animateWithDuration:0.25
                     animations:^{
                         _quiet.alpha = offline ? 1.0f : 0.0f;
                         CGFloat dim = offline ? 0.45f : 1.0f;
                         if (!_waiting) {
                             _value.alpha = dim;
                             _bar.alpha = dim;
                             _secondBar.alpha = dim;
                         }
                     }];
}

- (void)showWaitingWithText:(NSString *)text
{
    _waiting = YES;
    _hasSecond = NO;
    _plan.text = @"";
    _value.text = @"...";
    _value.textColor = [CMPalette faint];
    _value.alpha = 1.0f;
    _reset.text = text.length > 0 ? text : @"looking for the computer";
    _detail.text = @"";
    _barTitle.text = @"";
    _barValue.text = @"";
    _bar.fraction = 0;
    _bar.alpha = 1.0f;
    _secondTitle.hidden = YES;
    _secondValue.hidden = YES;
    _secondBar.hidden = YES;
    _today.text = @"";
    [self setNeedsLayout];
}

@end
