#import "CMPet.h"
#import <math.h>

static NSString *const CMHungerKey = @"petHunger";
static NSString *const CMHappinessKey = @"petHappiness";
static NSString *const CMEnergyKey = @"petEnergy";
static NSString *const CMStampKey = @"petStamp";

// Per hour, so a full bar takes most of a day to run down and nothing changes while
// you watch. A clock that jumped backwards or a very long gap is clamped below.
static double const CMHungerPerHour = 3.5;
static double const CMCheerPerHour = 2.2;
static double const CMEnergyPerHour = 4.0;
static double const CMEnergyBackPerHour = 9.0;
static double const CMLongestGap = 60.0 * 60.0 * 48.0;

@interface CMPet ()
@property (nonatomic, assign) double hunger;
@property (nonatomic, assign) double happiness;
@property (nonatomic, assign) double energy;
@property (nonatomic, strong) NSDate *stamp;
@end

@implementation CMPet

+ (instancetype)shared
{
    static CMPet *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[CMPet alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        id stamp = [defaults objectForKey:CMStampKey];

        if ([stamp isKindOfClass:[NSDate class]]) {
            _hunger = [self clamp:[defaults doubleForKey:CMHungerKey]];
            _happiness = [self clamp:[defaults doubleForKey:CMHappinessKey]];
            _energy = [self clamp:[defaults doubleForKey:CMEnergyKey]];
            _stamp = (NSDate *)stamp;
        } else {
            // First launch: he arrives fed, cheerful and rested.
            _hunger = 80;
            _happiness = 80;
            _energy = 90;
            _stamp = [NSDate date];
        }
    }
    return self;
}

- (double)clamp:(double)value
{
    if (!isfinite(value)) return 50;
    if (value < 0) return 0;
    if (value > 100) return 100;
    return value;
}

/// Seconds since the last stamp, ignoring a clock that moved the wrong way.
- (NSTimeInterval)takeElapsed
{
    NSDate *now = [NSDate date];
    NSTimeInterval elapsed = [now timeIntervalSinceDate:self.stamp];
    self.stamp = now;
    if (!isfinite(elapsed) || elapsed <= 0) return 0;
    return elapsed > CMLongestGap ? CMLongestGap : elapsed;
}

- (void)catchUpAfterBreak
{
    double hours = [self takeElapsed] / 3600.0;
    if (hours <= 0) return;

    self.hunger = [self clamp:self.hunger - CMHungerPerHour * hours];
    self.happiness = [self clamp:self.happiness - CMCheerPerHour * hours];
    self.energy = [self clamp:self.energy + CMEnergyBackPerHour * hours];
    [self save];
}

- (void)advanceResting:(BOOL)resting
{
    double hours = [self takeElapsed] / 3600.0;
    if (hours <= 0) return;

    self.hunger = [self clamp:self.hunger - CMHungerPerHour * hours];
    self.happiness = [self clamp:self.happiness - CMCheerPerHour * hours];
    if (resting) {
        self.energy = [self clamp:self.energy + CMEnergyBackPerHour * hours];
    } else {
        self.energy = [self clamp:self.energy - CMEnergyPerHour * hours];
    }
}

- (void)feed
{
    self.hunger = [self clamp:self.hunger + 34];
    self.happiness = [self clamp:self.happiness + 6];
    [self save];
}

- (void)petByHand
{
    self.happiness = [self clamp:self.happiness + 5];
    [self save];
}

- (double)lowestNeed
{
    double lowest = self.hunger;
    if (self.happiness < lowest) lowest = self.happiness;
    if (self.energy < lowest) lowest = self.energy;
    return lowest;
}

- (void)save
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:self.hunger forKey:CMHungerKey];
    [defaults setDouble:self.happiness forKey:CMHappinessKey];
    [defaults setDouble:self.energy forKey:CMEnergyKey];
    [defaults setObject:self.stamp forKey:CMStampKey];
    [defaults synchronize];
}

@end
