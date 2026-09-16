#import <UIKit/UIKit.h>
#import "CMUsage.h"

/// Clawd, drawn as a 16 by 10 grid of square layers. No images anywhere, so the whole
/// thing stays sharp on a 3.5 inch screen and costs almost nothing to move around.
///
/// The view is a little wider and taller than the grid: the extra room on the right is
/// where a prop goes, the room on top is for a hat, thinking dots and sleepy letters.
@interface CMClawd : UIView

/// Side of one square in points. Everything else is derived from it.
@property (nonatomic, assign) CGFloat pixel;

/// What Claude is doing, which picks the prop he carries.
@property (nonatomic, assign) CMActivity activity;

/// Lowest of the three needs, 0 to 100. Only changes how tired he looks.
@property (nonatomic, assign) double vigor;

/// The strip he walks along, in the coordinates of his superview.
@property (nonatomic, assign) CGFloat groundY;
@property (nonatomic, assign) CGFloat roamMin;
@property (nonatomic, assign) CGFloat roamMax;

/// Where his feet are now, in superview coordinates.
@property (nonatomic, readonly) CGFloat footX;

/// Still in the middle of a wave.
@property (nonatomic, readonly) BOOL waving;

/// The size this view wants for a given square side.
+ (CGSize)sizeForPixel:(CGFloat)pixel;

/// Drive everything: one call every frame with the seconds since the last one.
- (void)tick:(NSTimeInterval)seconds;

- (void)standAtX:(CGFloat)x;
- (void)walkTowardX:(CGFloat)x;
- (void)goToSleep;
- (void)wakeUp;

/// While a finger is carrying him.
- (void)liftToPoint:(CGPoint)point;
- (void)dropFromHand;
- (BOOL)containsPoint:(CGPoint)point inView:(UIView *)view;

- (void)startle;
- (void)showHeart;
- (void)wave;
- (void)munch;

@end
