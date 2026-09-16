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
    UILabel *_title;
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
        _title = [self labelWithSize:12 bold:NO color:[CMPalette faint]];
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

    CGFloat margin = 14.0f;
    BOOL wide = (width >= height);

    CGFloat leftWidth = wide ? floorf((width - margin * 3.0f) * 0.44f) : (width - margin * 2.0f);
    CGFloat rightX = wide ? (margin * 2.0f + leftWidth) : margin;
    CGFloat rightWidth = wide ? (width - rightX - margin) : (width - margin * 2.0f);

    // Left: which limit, how much of it is gone, when it comes back.
    CGFloat y = margin * 0.6f;
    _plan.frame = CGRectMake(margin, y, leftWidth, 12);
    y += 14;
    _title.frame = CGRectMake(margin, y, leftWidth, 15);
    y += 17;

    CGFloat valueHeight = wide ? 62.0f : 54.0f;
    _value.font = [UIFont boldSystemFontOfSize:wide ? 58.0f : 50.0f];
    _value.frame = CGRectMake(margin - 2.0f, y, leftWidth, valueHeight);
    y += valueHeight + 2.0f;

    _reset.frame = CGRectMake(margin, y, leftWidth, 15);
    y += 16;
    _detail.frame = CGRectMake(margin, y, leftWidth, 14);

    // Right: the bars and the day total.
    CGFloat barY = wide ? (margin * 1.4f) : (y + 24.0f);
    _barTitle.frame = CGRectMake(rightX, barY, rightWidth * 0.62f, 14);
    _barValue.frame = CGRectMake(rightX + rightWidth * 0.62f, barY, rightWidth * 0.38f, 14);
    barY += 17;
    _bar.frame = CGRectMake(rightX, barY, rightWidth, 11);
    barY += 17;

    if (_hasSecond) {
        _secondTitle.frame = CGRectMake(rightX, barY, rightWidth * 0.62f, 13);
        _secondValue.frame = CGRectMake(rightX + rightWidth * 0.62f, barY, rightWidth * 0.38f, 13);
        barY += 15;
        _secondBar.frame = CGRectMake(rightX, barY, rightWidth, 7);
        barY += 14;
    } else {
        _secondTitle.frame = CGRectZero;
        _secondValue.frame = CGRectZero;
        _secondBar.frame = CGRectZero;
    }

    _today.frame = CGRectMake(rightX, barY + 2.0f, rightWidth, 14);
    _quiet.frame = CGRectMake(rightX, barY + 18.0f, rightWidth, 14);
}

#pragma mark - Filling in

- (void)showUsage:(CMUsage *)usage
{
    if (usage == nil) return;
    _waiting = NO;

    UIColor *tint = [CMPalette tintForSeverity:usage.severity];

    _plan.text = [usage.plan uppercaseString];
    _title.text = usage.title.length > 0 ? usage.title : @"usage";
    _value.text = usage.value.length > 0 ? usage.value : @"...";
    _value.textColor = tint;

    NSString *reset = [usage resetText];
    _reset.text = reset.length > 0 ? [NSString stringWithFormat:@"resets in %@", reset] : @"";
    _detail.text = usage.detail.length > 0 ? usage.detail : usage.note;

    _barTitle.text = usage.title.length > 0 ? usage.title : @"session";
    _barValue.text = usage.value;
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
    _quiet.text = offline ? @"no answer from the PC" : @"";
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
    _title.text = text.length > 0 ? text : @"looking for the PC";
    _value.text = @"...";
    _value.textColor = [CMPalette faint];
    _value.alpha = 1.0f;
    _reset.text = @"";
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
