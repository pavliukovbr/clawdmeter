#import <Foundation/Foundation.h>

/// Three needs from 0 to 100 that drift while real time passes, including the time the
/// app was closed. Nothing here can reach a state that punishes the user: the numbers
/// sink slowly, they stop at zero, and a low number only changes how Clawd looks.
@interface CMPet : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) double hunger;
@property (nonatomic, readonly) double happiness;
@property (nonatomic, readonly) double energy;

/// Catch up on the stretch where the app was not running. Clawd naps while it is
/// closed, so that gap costs a little hunger and cheer and gives energy back.
- (void)catchUpAfterBreak;

/// Called while the app runs. Resting drains less and puts energy back.
- (void)advanceResting:(BOOL)resting;

- (void)feed;
- (void)petByHand;
- (void)save;

/// The lowest of the three, which is what decides how he looks when Claude is quiet.
- (double)lowestNeed;

@end
