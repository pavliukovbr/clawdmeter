#import "CMClawd.h"
#import "CMPalette.h"
#import <math.h>

// The grid he is drawn on. Everything on screen is a multiple of one square.
static CGFloat const CMGridWidth = 16.0f;
static CGFloat const CMGridHeight = 10.0f;
static CGFloat const CMPropRoom = 6.0f;   // squares to the right, where a prop stands
static CGFloat const CMHeadRoom = 3.0f;   // squares above, for a hat and sleepy letters

static CGFloat const CMGravity = 900.0f;
static CGFloat const CMWalkSpeed = 36.0f;

typedef NS_ENUM(NSInteger, CMAction) {
    CMActionStand = 0,
    CMActionWalk,
    CMActionHeld,
    CMActionSleep
};

@interface CMClawd ()
{
    CALayer *_body;
    CALayer *_crown;
    CALayer *_armLeft;
    CALayer *_armRight;
    CALayer *_legs[4];
    CALayer *_eyeLeft;
    CALayer *_eyeRight;
    CALayer *_prop;
    CALayer *_heart;

    NSMutableArray *_blinkers;   // prop parts that pulse, thinking dots and sparkles
    NSMutableArray *_sleepies;   // the floating letters

    CMAction _action;
    BOOL _propBuilt;

    CGFloat _footX;
    CGFloat _targetX;
    CGFloat _hop;        // height above the ground line
    CGFloat _hopSpeed;
    CGFloat _fallSpeed;  // how hard he hit the ground last time

    CGFloat _breathPhase;
    CGFloat _walkPhase;
    CGFloat _blinkWait;
    CGFloat _blinkLeft;
    CGFloat _squash;
    CGFloat _waveLeft;
    CGFloat _munchLeft;
    CGFloat _wideLeft;
    CGFloat _heartLeft;
    CGFloat _sleepPhase;
    CGFloat _pulsePhase;
}
@end

@implementation CMClawd

+ (CGSize)sizeForPixel:(CGFloat)pixel
{
    return CGSizeMake((CMGridWidth + CMPropRoom) * pixel,
                      (CMGridHeight + CMHeadRoom) * pixel);
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _pixel = 3.0f;
        _vigor = 80.0f;
        _blinkWait = 2.0f;
        _blinkers = [NSMutableArray array];
        _sleepies = [NSMutableArray array];
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.clipsToBounds = NO;
        [self buildBody];
    }
    return self;
}

#pragma mark - Building

- (CALayer *)squareAtX:(CGFloat)x y:(CGFloat)y wide:(CGFloat)wide high:(CGFloat)high color:(UIColor *)color
{
    CALayer *layer = [CALayer layer];
    layer.backgroundColor = color.CGColor;
    layer.anchorPoint = CGPointMake(0.5f, 0.5f);
    // Held in grid units; layoutSubviews turns them into points.
    layer.name = [NSString stringWithFormat:@"%g %g %g %g", (double)x, (double)y, (double)wide, (double)high];
    return layer;
}

- (void)placeLayer:(CALayer *)layer
{
    if (layer.name.length == 0) return;
    NSArray *parts = [layer.name componentsSeparatedByString:@" "];
    if (parts.count != 4) return;

    CGFloat px = self.pixel;
    CGFloat x = [parts[0] doubleValue] * px;
    CGFloat y = ([parts[1] doubleValue] + CMHeadRoom) * px;
    CGFloat wide = [parts[2] doubleValue] * px;
    CGFloat high = [parts[3] doubleValue] * px;

    layer.bounds = CGRectMake(0, 0, wide, high);
    layer.position = CGPointMake(x + wide * 0.5f, y + high * 0.5f);
}

- (void)buildBody
{
    _body = [self squareAtX:2 y:0 wide:12 high:8 color:[CMPalette clay]];
    _crown = [self squareAtX:3 y:0 wide:10 high:1 color:[CMPalette clayLight]];
    _armLeft = [self squareAtX:0 y:4 wide:2 high:2 color:[CMPalette clayDeep]];
    _armRight = [self squareAtX:14 y:4 wide:2 high:2 color:[CMPalette clayDeep]];
    _eyeLeft = [self squareAtX:4 y:2 wide:1 high:2 color:[CMPalette ink]];
    _eyeRight = [self squareAtX:11 y:2 wide:1 high:2 color:[CMPalette ink]];

    CGFloat columns[4] = {3, 5, 10, 12};
    for (int i = 0; i < 4; i++) {
        _legs[i] = [self squareAtX:columns[i] y:7 wide:1 high:3 color:[CMPalette clayDeep]];
    }

    _prop = [CALayer layer];

    // Order matters: legs sit behind the body so the top of them is hidden.
    for (int i = 0; i < 4; i++) [self.layer addSublayer:_legs[i]];
    [self.layer addSublayer:_armLeft];
    [self.layer addSublayer:_armRight];
    [self.layer addSublayer:_body];
    [self.layer addSublayer:_crown];
    [self.layer addSublayer:_eyeLeft];
    [self.layer addSublayer:_eyeRight];
    [self.layer addSublayer:_prop];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    [self placeLayer:_body];
    [self placeLayer:_crown];
    [self placeLayer:_armLeft];
    [self placeLayer:_armRight];
    [self placeLayer:_eyeLeft];
    [self placeLayer:_eyeRight];
    for (int i = 0; i < 4; i++) [self placeLayer:_legs[i]];

    _prop.frame = self.layer.bounds;
    for (CALayer *part in _prop.sublayers) [self placeLayer:part];
    if (_heart != nil) {
        [self placeLayer:_heart];
        [self layoutHeartBits];
    }

    CGFloat px = self.pixel;
    CGFloat letter = px * 3.2f;
    for (UILabel *label in _sleepies) {
        label.font = [UIFont boldSystemFontOfSize:letter];
        [label sizeToFit];
    }

    [CATransaction commit];
    [self redraw];
}

- (void)setPixel:(CGFloat)pixel
{
    if (pixel <= 0) return;
    _pixel = pixel;
    CGSize size = [CMClawd sizeForPixel:pixel];
    self.bounds = CGRectMake(0, 0, size.width, size.height);
    [self setNeedsLayout];
}

#pragma mark - Props

- (void)setActivity:(CMActivity)activity
{
    if (_activity == activity && _propBuilt) return;
    _activity = activity;
    [self rebuildProp];
}

- (void)rebuildProp
{
    _propBuilt = YES;

    for (CALayer *part in [_prop.sublayers copy]) [part removeFromSuperlayer];
    [_blinkers removeAllObjects];

    UIColor *clay = [CMPalette clay];
    UIColor *light = [CMPalette clayLight];
    UIColor *deep = [CMPalette clayDeep];
    UIColor *amber = [CMPalette amber];
    UIColor *paper = [CMPalette paper];
    UIColor *steel = [UIColor colorWithWhite:0.72f alpha:1.0f];

    switch (self.activity) {
        case CMActivityTyping: {
            [self addProp:[self squareAtX:16.4f y:9.0f wide:5.2f high:1.0f color:deep]];
            [self addProp:[self squareAtX:17.0f y:5.8f wide:4.0f high:3.0f color:clay]];
            [self addProp:[self squareAtX:17.5f y:6.3f wide:3.0f high:2.0f color:light]];
            break;
        }
        case CMActivityReading: {
            // An open book: two pages, the spine between them, a couple of lines of text.
            [self addProp:[self squareAtX:15.8f y:6.4f wide:3.0f high:3.6f color:paper]];
            [self addProp:[self squareAtX:19.2f y:6.4f wide:2.8f high:3.6f color:paper]];
            [self addProp:[self squareAtX:18.8f y:6.0f wide:0.5f high:4.0f color:deep]];
            [self addProp:[self squareAtX:16.2f y:7.2f wide:2.2f high:0.35f color:deep]];
            [self addProp:[self squareAtX:16.2f y:8.1f wide:1.6f high:0.35f color:deep]];
            [self addProp:[self squareAtX:19.6f y:7.2f wide:2.0f high:0.35f color:deep]];
            [self addProp:[self squareAtX:19.6f y:8.1f wide:1.4f high:0.35f color:deep]];
            break;
        }
        case CMActivitySearching: {
            CAShapeLayer *ring = [CAShapeLayer layer];
            ring.fillColor = [UIColor clearColor].CGColor;
            ring.strokeColor = amber.CGColor;
            ring.name = @"16.4 4.6 4.0 4.0";
            [self addProp:ring];
            [self addProp:[self squareAtX:19.6f y:8.6f wide:0.9f high:0.9f color:amber]];
            [self addProp:[self squareAtX:20.2f y:9.2f wide:0.9f high:0.9f color:amber]];
            break;
        }
        case CMActivityBuilding: {
            // Hard hat on his head, hammer standing next to him.
            [self addProp:[self squareAtX:2.5f y:-0.8f wide:11.0f high:0.8f color:[CMPalette amberDeep]]];
            [self addProp:[self squareAtX:5.0f y:-2.2f wide:6.0f high:1.6f color:amber]];
            [self addProp:[self squareAtX:18.8f y:5.4f wide:1.2f high:4.6f color:deep]];
            [self addProp:[self squareAtX:17.4f y:4.0f wide:4.2f high:1.8f color:steel]];
            break;
        }
        case CMActivityThinking: {
            CGFloat spots[3] = {16.6f, 18.2f, 19.8f};
            for (int i = 0; i < 3; i++) {
                CALayer *dot = [self squareAtX:spots[i] y:1.6f wide:1.0f high:1.0f color:light];
                [self addProp:dot];
                [_blinkers addObject:dot];
            }
            break;
        }
        case CMActivityCelebrating: {
            CGFloat spots[3][2] = {{16.6f, 1.2f}, {19.4f, 2.6f}, {17.6f, 4.4f}};
            for (int i = 0; i < 3; i++) {
                CALayer *spark = [self squareAtX:spots[i][0] y:spots[i][1] wide:1.0f high:1.0f color:amber];
                [self addProp:spark];
                [_blinkers addObject:spark];
            }
            break;
        }
        default:
            break;
    }

    [self setNeedsLayout];

    // The ring needs its path after layout has given it a size.
    for (CALayer *part in _prop.sublayers) {
        if ([part isKindOfClass:[CAShapeLayer class]]) {
            CAShapeLayer *ring = (CAShapeLayer *)part;
            [self placeLayer:ring];
            ring.lineWidth = MAX(1.0f, self.pixel * 0.7f);
            ring.path = [UIBezierPath bezierPathWithOvalInRect:
                         CGRectInset(ring.bounds, ring.lineWidth * 0.5f, ring.lineWidth * 0.5f)].CGPath;
        }
    }
}

- (void)addProp:(CALayer *)part
{
    [_prop addSublayer:part];
}

#pragma mark - Position

- (void)standAtX:(CGFloat)x
{
    _footX = x;
    _targetX = x;
    // A layout pass in the middle of a rotation must not take him out of a hand.
    if (_action != CMActionSleep && _action != CMActionHeld) _action = CMActionStand;
    [self applyPosition];
}

- (void)walkTowardX:(CGFloat)x
{
    if (_action == CMActionHeld) return;
    [self wakeUp];
    _targetX = [self clampRoam:x];
    _action = CMActionWalk;
}

- (void)goToSleep
{
    if (_action == CMActionHeld) return;
    _action = CMActionSleep;
    [self makeSleepies];
}

- (void)wakeUp
{
    if (_action == CMActionSleep) {
        _action = CMActionStand;
        for (UILabel *label in _sleepies) [label removeFromSuperview];
        [_sleepies removeAllObjects];
    }
}

- (void)liftToPoint:(CGPoint)point
{
    [self wakeUp];
    _action = CMActionHeld;
    _footX = [self clampRoam:point.x];
    _hop = MAX(0.0f, self.groundY - point.y);
    _hopSpeed = 0;
    [self applyPosition];
}

- (void)dropFromHand
{
    if (_action != CMActionHeld) return;
    _action = CMActionStand;
    _targetX = _footX;
    if (_hop <= 0) [self landed];
}

- (CGFloat)clampRoam:(CGFloat)x
{
    CGFloat low = self.roamMin;
    CGFloat high = self.roamMax;
    if (high < low) return low;
    if (x < low) return low;
    if (x > high) return high;
    return x;
}

- (CGFloat)footX
{
    return _footX;
}

- (BOOL)waving
{
    return _waveLeft > 0;
}

- (BOOL)containsPoint:(CGPoint)point inView:(UIView *)view
{
    CGPoint local = [self convertPoint:point fromView:view];
    CGFloat px = self.pixel;
    CGRect body = CGRectMake(0, CMHeadRoom * px, CMGridWidth * px, CMGridHeight * px);
    return CGRectContainsPoint(CGRectInset(body, -px * 1.5f, -px * 1.5f), local);
}

- (void)applyPosition
{
    CGSize size = self.bounds.size;
    CGFloat px = self.pixel;
    // The grid sits on the left of the view, so his feet are eight squares in.
    CGFloat left = _footX - CMGridWidth * 0.5f * px;
    CGFloat top = (self.groundY - _hop) - size.height + 0.0f;
    self.frame = CGRectMake(roundf(left), roundf(top), size.width, size.height);
}

#pragma mark - Small moments

- (void)startle
{
    [self wakeUp];
    if (_action == CMActionHeld) return;
    _hopSpeed = 230.0f;
    _wideLeft = 0.7f;
}

- (void)wave
{
    [self wakeUp];
    _waveLeft = 1.8f;
}

- (void)munch
{
    [self wakeUp];
    _munchLeft = 1.0f;
}

- (void)showHeart
{
    [self wakeUp];
    if (_heart == nil) {
        _heart = [CALayer layer];
        _heart.name = @"6.6 -4.4 5.0 4.2";

        // Seven columns by six rows of little squares, the shape of a heart.
        CGFloat shape[7][4] = {
            {1, 0, 2, 1}, {4, 0, 2, 1},
            {0, 1, 7, 1}, {0, 2, 7, 1},
            {1, 3, 5, 1}, {2, 4, 3, 1}, {3, 5, 1, 1}
        };
        UIColor *pink = [CMPalette heart];
        for (int i = 0; i < 7; i++) {
            CALayer *bit = [CALayer layer];
            bit.backgroundColor = pink.CGColor;
            bit.anchorPoint = CGPointMake(0, 0);
            bit.name = [NSString stringWithFormat:@"%g %g %g %g",
                        (double)shape[i][0], (double)shape[i][1],
                        (double)shape[i][2], (double)shape[i][3]];
            [_heart addSublayer:bit];
        }
        _heart.opacity = 0;
        [self.layer addSublayer:_heart];
        [self placeLayer:_heart];
        [self layoutHeartBits];
    }
    _heartLeft = 1.4f;
}

/// The heart squares are kept in a 7 by 6 grid of their own, so they follow whatever
/// size the heart layer ends up with.
- (void)layoutHeartBits
{
    if (_heart == nil) return;
    CGFloat unitX = _heart.bounds.size.width / 7.0f;
    CGFloat unitY = _heart.bounds.size.height / 6.0f;

    for (CALayer *bit in _heart.sublayers) {
        NSArray *parts = [bit.name componentsSeparatedByString:@" "];
        if (parts.count != 4) continue;
        bit.frame = CGRectMake([parts[0] doubleValue] * unitX,
                               [parts[1] doubleValue] * unitY,
                               [parts[2] doubleValue] * unitX,
                               [parts[3] doubleValue] * unitY);
    }
}

- (void)makeSleepies
{
    if (_sleepies.count > 0) return;
    for (int i = 0; i < 3; i++) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = @"Z";
        label.textColor = [CMPalette faint];
        label.font = [UIFont boldSystemFontOfSize:self.pixel * 3.2f];
        label.alpha = 0;
        [label sizeToFit];
        [self addSubview:label];
        [_sleepies addObject:label];
    }
}

#pragma mark - Frame by frame

- (void)tick:(NSTimeInterval)seconds
{
    CGFloat dt = (CGFloat)seconds;
    if (!isfinite(dt) || dt <= 0) return;
    if (dt > 0.25f) dt = 0.25f;   // after a stall, do not teleport

    _breathPhase += dt * (_action == CMActionSleep ? 1.1f : 2.0f);
    _pulsePhase += dt * 3.0f;
    _sleepPhase += dt * 0.6f;

    [self stepWalk:dt];
    [self stepJump:dt];
    [self stepFaces:dt];

    if (_waveLeft > 0) _waveLeft -= dt;
    if (_munchLeft > 0) _munchLeft -= dt;
    if (_squash > 0) _squash = MAX(0.0f, _squash - dt * 3.2f);

    [self redraw];
}

/// Put every part where the current pose says it goes. A layout pass parks the parts on
/// their resting marks, so it ends by calling this too and nothing jumps.
- (void)redraw
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self applyPosition];
    [self drawBreath];
    [self drawLegs];
    [self drawArms];
    [self drawEyes];
    [self drawExtras];
    [CATransaction commit];
}

- (void)stepWalk:(CGFloat)dt
{
    BOOL moving = NO;
    if (_action == CMActionWalk) {
        CGFloat gap = _targetX - _footX;
        CGFloat step = CMWalkSpeed * dt;
        if (fabs(gap) <= step) {
            _footX = _targetX;
            _action = CMActionStand;
        } else {
            _footX += (gap > 0 ? step : -step);
            moving = YES;
        }
        _footX = [self clampRoam:_footX];
    }

    if (moving || _action == CMActionHeld) {
        _walkPhase += dt * (_action == CMActionHeld ? 11.0f : 7.0f);
    } else if (_munchLeft > 0) {
        _walkPhase += dt * 9.0f;
    }
}

- (void)stepJump:(CGFloat)dt
{
    if (_action == CMActionHeld) return;
    if (_hop <= 0 && _hopSpeed <= 0) return;

    _hopSpeed -= CMGravity * dt;
    _hop += _hopSpeed * dt;
    if (_hop <= 0) {
        _fallSpeed = fabs(_hopSpeed);
        _hop = 0;
        _hopSpeed = 0;
        [self landed];
    }
}

- (void)landed
{
    CGFloat force = _fallSpeed / 600.0f;
    if (force > 1.0f) force = 1.0f;
    _squash = MAX(_squash, 0.35f + 0.45f * force);
    _fallSpeed = 0;
}

- (void)stepFaces:(CGFloat)dt
{
    if (_wideLeft > 0) _wideLeft -= dt;
    if (_heartLeft > 0) _heartLeft -= dt;

    if (_blinkLeft > 0) {
        _blinkLeft -= dt;
    } else {
        _blinkWait -= dt;
        if (_blinkWait <= 0) {
            _blinkLeft = 0.12f;
            _blinkWait = 2.0f + (CGFloat)(arc4random_uniform(2600)) / 1000.0f;
        }
    }
}

- (void)drawBreath
{
    CGFloat px = self.pixel;
    CGFloat swell = 0.03f * sinf(_breathPhase);
    if (_munchLeft > 0) swell += 0.05f * sinf(_walkPhase * 1.6f);

    CGFloat tall = 1.0f + swell - _squash * 0.30f;
    CGFloat wide = 1.0f - swell * 0.5f + _squash * 0.26f;

    CGFloat bodyHeight = 8.0f * px;
    CGFloat bottom = ((CMHeadRoom + 8.0f) * px);
    _body.bounds = CGRectMake(0, 0, 12.0f * px * wide, bodyHeight * tall);
    _body.position = CGPointMake((2.0f + 6.0f) * px, bottom - _body.bounds.size.height * 0.5f);

    _crown.bounds = CGRectMake(0, 0, 10.0f * px * wide, 1.0f * px);
    _crown.position = CGPointMake((2.0f + 6.0f) * px,
                                  _body.position.y - _body.bounds.size.height * 0.5f + 0.5f * px);
}

- (void)drawLegs
{
    CGFloat px = self.pixel;
    CGFloat columns[4] = {3, 5, 10, 12};
    BOOL stepping = (_action == CMActionWalk || _action == CMActionHeld || _munchLeft > 0);

    for (int i = 0; i < 4; i++) {
        CGFloat lift = 0;
        if (stepping) {
            CGFloat swing = sinf(_walkPhase + (CGFloat)i * 1.6f);
            lift = MAX(0.0f, swing) * px * 0.9f;
        }
        CGFloat high = 3.0f * px - (_squash * 1.4f * px);
        if (high < px * 0.6f) high = px * 0.6f;
        _legs[i].bounds = CGRectMake(0, 0, 1.0f * px, high);
        _legs[i].position = CGPointMake((columns[i] + 0.5f) * px,
                                        (CMHeadRoom + 10.0f) * px - high * 0.5f - lift);
    }
}

- (void)drawArms
{
    CGFloat px = self.pixel;
    CGFloat restY = (CMHeadRoom + 5.0f) * px;
    CGFloat sway = sinf(_walkPhase) * px * 0.35f;
    if (_action != CMActionWalk && _action != CMActionHeld) sway = sinf(_breathPhase) * px * 0.12f;

    _armLeft.bounds = CGRectMake(0, 0, 2.0f * px, 2.0f * px);
    _armLeft.position = CGPointMake(1.0f * px, restY + sway);

    CGFloat rightY = restY - sway;
    if (_waveLeft > 0) {
        CGFloat wave = sinf(_waveLeft * 13.0f);
        rightY = restY - px * (3.0f + 1.0f * wave);   // high enough to read as a wave
    }
    _armRight.bounds = CGRectMake(0, 0, 2.0f * px, 2.0f * px);
    _armRight.position = CGPointMake(15.0f * px, rightY);
}

- (void)drawEyes
{
    CGFloat px = self.pixel;
    CGFloat open = 1.0f;

    if (_action == CMActionSleep) {
        open = 0.16f;
    } else if (_blinkLeft > 0) {
        open = 0.16f;
    } else if (_wideLeft > 0) {
        open = 1.45f;
    } else if (self.vigor < 30.0f) {
        open = 0.55f;
    } else if (self.vigor < 55.0f) {
        open = 0.8f;
    }

    CGFloat high = 2.0f * px * open;
    CGFloat middle = (CMHeadRoom + 3.0f) * px;
    CGFloat lids = (_action == CMActionSleep || _blinkLeft > 0) ? px * 0.3f : 0;

    _eyeLeft.bounds = CGRectMake(0, 0, 1.0f * px, high);
    _eyeLeft.position = CGPointMake(4.5f * px, middle + lids);
    _eyeRight.bounds = CGRectMake(0, 0, 1.0f * px, high);
    _eyeRight.position = CGPointMake(11.5f * px, middle + lids);
}

- (void)drawExtras
{
    CGFloat px = self.pixel;

    // Thinking dots and celebration sparkles take turns lighting up.
    NSUInteger count = _blinkers.count;
    if (count > 0) {
        for (NSUInteger i = 0; i < count; i++) {
            CALayer *dot = _blinkers[i];
            CGFloat phase = _pulsePhase - (CGFloat)i * 0.7f;
            CGFloat lit = 0.35f + 0.65f * (0.5f + 0.5f * sinf(phase));
            dot.opacity = (float)lit;
        }
    }

    _prop.opacity = (_action == CMActionSleep) ? 0.0f : 1.0f;

    if (_heart != nil) {
        if (_heartLeft > 0) {
            CGFloat done = 1.0f - (_heartLeft / 1.4f);
            _heart.opacity = (float)(1.0f - done * done);
            [self placeLayer:_heart];
            _heart.position = CGPointMake(_heart.position.x, _heart.position.y - done * px * 4.0f);
        } else {
            _heart.opacity = 0;
        }
    }

    if (_action == CMActionSleep && _sleepies.count > 0) {
        for (NSUInteger i = 0; i < _sleepies.count; i++) {
            UILabel *label = _sleepies[i];
            CGFloat phase = _sleepPhase - (CGFloat)i * 0.33f;
            CGFloat step = phase - floorf(phase);
            label.alpha = (step < 0.15f) ? step / 0.15f : (1.0f - step) * 0.9f;
            CGFloat rise = step * px * 5.0f;
            CGFloat drift = step * px * 2.4f;
            label.center = CGPointMake(13.0f * px + drift, (CMHeadRoom - 0.4f) * px - rise);
        }
    } else {
        for (UILabel *label in _sleepies) label.alpha = 0;
    }
}

@end
