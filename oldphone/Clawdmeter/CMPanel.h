#import <UIKit/UIKit.h>
#import "CMUsage.h"

/// One rounded bar. The track is always there, the fill grows from the left.
@interface CMBar : UIView

@property (nonatomic, assign) double fraction;
@property (nonatomic, assign) CMSeverity severity;

@end

/// Everything the numbers need: the big percentage, what limit it is, how long until it
/// resets, the session bar, a smaller second bar and the day total.
@interface CMPanel : UIView

- (void)showUsage:(CMUsage *)usage;

/// How far down the lowest line reaches, so the screen knows what is free below it.
- (CGFloat)contentBottom;

/// Dim the last good answer and say so, quietly, in a corner.
- (void)setOffline:(BOOL)offline;

/// Shown before the first answer arrives and when there is no address yet.
- (void)showWaitingWithText:(NSString *)text;

@end
