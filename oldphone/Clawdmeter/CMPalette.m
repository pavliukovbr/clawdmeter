#import "CMPalette.h"

static UIColor *CMRGB(CGFloat r, CGFloat g, CGFloat b)
{
    return [UIColor colorWithRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:1.0f];
}

@implementation CMPalette

+ (UIColor *)clay { return CMRGB(215, 119, 87); }
+ (UIColor *)clayLight { return CMRGB(236, 150, 118); }
+ (UIColor *)clayDeep { return CMRGB(190, 92, 62); }
+ (UIColor *)amber { return CMRGB(245, 178, 76); }
+ (UIColor *)amberDeep { return CMRGB(222, 140, 44); }
+ (UIColor *)red { return CMRGB(255, 105, 94); }
+ (UIColor *)redDeep { return CMRGB(226, 62, 58); }
+ (UIColor *)heart { return CMRGB(255, 110, 128); }
+ (UIColor *)sweat { return CMRGB(140, 204, 255); }
+ (UIColor *)backgroundTop { return CMRGB(52, 43, 39); }
+ (UIColor *)backgroundBottom { return CMRGB(29, 25, 23); }
+ (UIColor *)ink { return CMRGB(20, 16, 14); }
+ (UIColor *)paper { return [UIColor colorWithWhite:0.96f alpha:1.0f]; }
+ (UIColor *)faint { return [UIColor colorWithWhite:1.0f alpha:0.45f]; }

+ (UIColor *)tintForSeverity:(CMSeverity)severity
{
    switch (severity) {
        case CMSeverityWarning: return [self amber];
        case CMSeverityCritical: return [self red];
        default: return [self clayLight];
    }
}

+ (UIColor *)deepForSeverity:(CMSeverity)severity
{
    switch (severity) {
        case CMSeverityWarning: return [self amberDeep];
        case CMSeverityCritical: return [self redDeep];
        default: return [self clayDeep];
    }
}

+ (CMSeverity)severityFromName:(NSString *)name
{
    if ([name isKindOfClass:[NSString class]]) {
        if ([name isEqualToString:@"critical"]) return CMSeverityCritical;
        if ([name isEqualToString:@"warning"]) return CMSeverityWarning;
    }
    return CMSeverityNormal;
}

@end
