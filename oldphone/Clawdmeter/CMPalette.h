#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, CMSeverity) {
    CMSeverityNormal = 0,
    CMSeverityWarning,
    CMSeverityCritical
};

/// The colors the rest of Clawdmeter uses, written out again here because this app
/// shares no code with the Swift and C# versions.
@interface CMPalette : NSObject

+ (UIColor *)clay;
+ (UIColor *)clayLight;
+ (UIColor *)clayDeep;
+ (UIColor *)amber;
+ (UIColor *)amberDeep;
+ (UIColor *)red;
+ (UIColor *)redDeep;
+ (UIColor *)heart;
+ (UIColor *)sweat;
+ (UIColor *)backgroundTop;
+ (UIColor *)backgroundBottom;
+ (UIColor *)ink;
+ (UIColor *)paper;
+ (UIColor *)faint;

+ (UIColor *)tintForSeverity:(CMSeverity)severity;
+ (UIColor *)deepForSeverity:(CMSeverity)severity;
+ (CMSeverity)severityFromName:(NSString *)name;

@end
