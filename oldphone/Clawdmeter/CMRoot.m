#import "CMRoot.h"
#import "CMPalette.h"
#import "CMPanel.h"
#import "CMClawd.h"
#import "CMPet.h"
#import "CMSettings.h"
#import "CMUsage.h"
#import "CMScanner.h"
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>

// A quiet stretch this long and he curls up for a nap.
static NSTimeInterval const CMSleepAfter = 70.0;
// The shortest gap between two buzzes, so nothing ever turns into a burst.
static NSTimeInterval const CMBuzzGap = 0.8;

@interface CMRoot () <CMUsageClientDelegate, UIGestureRecognizerDelegate, CMScannerDelegate>
{
    CAGradientLayer *_sky;
    CALayer *_ground;
    CALayer *_food;
    CMPanel *_panel;
    CMClawd *_clawd;
    UIView *_alertMark;
    CALayer *_markBar;
    CALayer *_markDot;
    UILabel *_alertText;

    CMUsageClient *_client;
    CMUsage *_usage;
    BOOL _offline;
    BOOL _sawAnswer;
    BOOL _knowTurn;
    long long _lastTurn;
    BOOL _alerting;
    BOOL _celebrating;

    CADisplayLink *_link;
    CFTimeInterval _lastFrame;
    NSTimeInterval _quietFor;
    NSTimeInterval _sincePetTick;
    NSTimeInterval _sinceSave;
    NSTimeInterval _untilWander;

    BOOL _carrying;
    CGFloat _lastPanX;
    CGPoint _panStart;
    NSInteger _panDirection;
    NSInteger _reversals;
    NSTimeInterval _lastBuzz;
    NSTimeInterval _lastPet;

    BOOL _foodOut;
    CGFloat _foodX;
    BOOL _settingsOpen;
    BOOL _offeredScan;
}
@end

@implementation CMRoot

#pragma mark - Setting up

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = [CMPalette backgroundBottom];

    _sky = [CAGradientLayer layer];
    _sky.colors = @[(id)[CMPalette backgroundTop].CGColor,
                    (id)[CMPalette backgroundBottom].CGColor];
    [self.view.layer insertSublayer:_sky atIndex:0];

    _ground = [CALayer layer];
    _ground.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.07f].CGColor;
    [self.view.layer addSublayer:_ground];

    _panel = [[CMPanel alloc] initWithFrame:CGRectZero];
    [self.view addSubview:_panel];

    // The exclamation mark is drawn, not typed, so it matches the squares Clawd is
    // made of and reads from across a room.
    _alertMark = [[UIView alloc] initWithFrame:CGRectZero];
    _alertMark.userInteractionEnabled = NO;
    _alertMark.alpha = 0;
    _markBar = [CALayer layer];
    _markBar.backgroundColor = [CMPalette amber].CGColor;
    _markDot = [CALayer layer];
    _markDot.backgroundColor = [CMPalette amber].CGColor;
    [_alertMark.layer addSublayer:_markBar];
    [_alertMark.layer addSublayer:_markDot];
    [self.view addSubview:_alertMark];

    _alertText = [[UILabel alloc] initWithFrame:CGRectZero];
    _alertText.textAlignment = NSTextAlignmentLeft;
    _alertText.textColor = [CMPalette paper];
    _alertText.font = [UIFont systemFontOfSize:15.0f];
    _alertText.numberOfLines = 2;
    _alertText.alpha = 0;
    [self.view addSubview:_alertText];

    // Clawd goes on last so he walks in front of the waiting mark.
    _clawd = [[CMClawd alloc] initWithFrame:CGRectZero];
    [self.view addSubview:_clawd];

    [self addGestures];

    _client = [[CMUsageClient alloc] init];
    _client.delegate = self;

    [_panel showWaitingWithText:[[CMSettings shared] usageURL] != nil
                                ? @"asking the computer" : @"hold down to scan the code"];

    _untilWander = 3.0;
    [[CMPet shared] catchUpAfterBreak];
    _clawd.vigor = [[CMPet shared] lowestNeed];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(goingQuiet)
                   name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(comingBack)
                   name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_link invalidate];
    [_client stop];
}

- (void)addGestures
{
    UITapGestureRecognizer *twice = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                           action:@selector(handleDoubleTap:)];
    twice.numberOfTapsRequired = 2;
    twice.delegate = self;
    [self.view addGestureRecognizer:twice];

    UITapGestureRecognizer *once = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handleTap:)];
    once.delegate = self;
    [once requireGestureRecognizerToFail:twice];
    [self.view addGestureRecognizer:once];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(handlePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.delegate = self;
    [self.view addGestureRecognizer:pan];

    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                      action:@selector(handleHold:)];
    hold.minimumPressDuration = 1.1;
    hold.delegate = self;
    [self.view addGestureRecognizer:hold];
}

- (BOOL)prefersStatusBarHidden { return YES; }

- (BOOL)shouldAutorotate { return YES; }

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

#pragma mark - Layout

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];

    CGRect bounds = self.view.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;
    if (width <= 0 || height <= 0) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _sky.frame = bounds;

    // Clawd gets the bottom strip, the numbers get the rest.
    CGFloat pixel = (width >= height) ? 4.4f : 3.8f;
    CGSize clawdSize = [CMClawd sizeForPixel:pixel];
    CGFloat strip = clawdSize.height + 34.0f;
    CGFloat groundY = height - 34.0f;

    _panel.frame = CGRectMake(0, 0, width, MAX(60.0f, height - strip));
    _ground.frame = CGRectMake(0, groundY, width, 1.0f);

    _clawd.pixel = pixel;
    _clawd.groundY = groundY;
    // He uses the whole width: his body stays on screen at one end, his prop at the other.
    _clawd.roamMin = 8.0f * pixel + 6.0f;
    _clawd.roamMax = MAX(_clawd.roamMin, width - clawdSize.width + 8.0f * pixel - 6.0f);
    if (_clawd.footX < _clawd.roamMin || _clawd.footX > _clawd.roamMax) {
        [_clawd standAtX:(_clawd.roamMin + _clawd.roamMax) * 0.5f];
    } else {
        [_clawd standAtX:_clawd.footX];
    }

    if (_food != nil) {
        CGFloat size = pixel * 2.0f;
        _food.frame = CGRectMake(_foodX - size * 0.5f, groundY - size, size, size);
    }
    [CATransaction commit];

    // The mark and its line stand in the free band above the ground, next to Clawd,
    // so nothing has to be hidden behind them.
    CGFloat bandTop = MIN([_panel contentBottom] + 12.0f, groundY - 44.0f);
    CGFloat markHigh = MIN(96.0f, groundY - bandTop - 2.0f);
    if (markHigh < 40.0f) markHigh = 40.0f;

    CGFloat thick = roundf(markHigh * 0.17f);
    CGFloat gap = roundf(markHigh * 0.12f);
    CGFloat stem = markHigh - thick - gap;
    CGFloat markX = 26.0f;

    _alertMark.frame = CGRectMake(markX, groundY - markHigh, thick, markHigh);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _markBar.frame = CGRectMake(0, 0, thick, stem);
    _markDot.frame = CGRectMake(0, stem + gap, thick, thick);
    [CATransaction commit];

    // The line sits level with the top of the mark, clear of Clawd walking underneath.
    CGFloat textX = markX + thick + 16.0f;
    _alertText.frame = CGRectMake(textX, groundY - markHigh - 3.0f,
                                  MAX(60.0f, width - textX - 16.0f), 30.0f);
}

#pragma mark - The clock

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self comingBack];

    // First launch knows nowhere to look yet, so go straight to the camera.
    if (!_offeredScan && [[CMSettings shared] usageURL] == nil) {
        _offeredScan = YES;
        [self openScanner];
    }
}

- (void)comingBack
{
    if (_link == nil) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
        _link.frameInterval = 2;    // half of sixty is plenty for a pixel animal
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    _lastFrame = 0;
    [[CMPet shared] catchUpAfterBreak];
    _clawd.vigor = [[CMPet shared] lowestNeed];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    [_client start];
}

- (void)goingQuiet
{
    [_link invalidate];
    _link = nil;
    [_client stop];
    [[CMPet shared] save];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}

- (void)frame:(CADisplayLink *)link
{
    CFTimeInterval now = link.timestamp;
    if (_lastFrame <= 0) { _lastFrame = now; return; }
    NSTimeInterval dt = now - _lastFrame;
    _lastFrame = now;
    if (dt <= 0 || dt > 0.5) dt = 1.0 / 30.0;

    _quietFor += dt;
    _sincePetTick += dt;
    _sinceSave += dt;

    CMPet *pet = [CMPet shared];
    if (_sincePetTick >= 20.0) {
        _sincePetTick = 0;
        [pet advanceResting:[self clawdShouldSleep]];
        _clawd.vigor = [pet lowestNeed];
    }
    if (_sinceSave >= 120.0) {
        _sinceSave = 0;
        [pet save];
    }

    // He keeps waving for as long as the mark is up.
    if (_alerting && !_clawd.waving) [_clawd wave];

    [self stepBehaviour:dt];
    [_clawd tick:dt];
}

- (BOOL)clawdShouldSleep
{
    if (_carrying || _alerting) return NO;
    if (_usage != nil && !_offline) {
        if (_usage.working) return NO;
        if (_usage.activity == CMActivitySleeping) return YES;
        if ([_usage.mood isEqualToString:@"sleeping"]) return YES;
    }
    return _quietFor > CMSleepAfter;
}

- (void)stepBehaviour:(NSTimeInterval)dt
{
    if (_carrying) return;

    if (_foodOut) {
        [_clawd walkTowardX:_foodX];
        if (fabs(_clawd.footX - _foodX) < 8.0f) {
            [self eatFood];
        }
        return;
    }

    if ([self clawdShouldSleep]) {
        [_clawd goToSleep];
        return;
    }
    [_clawd wakeUp];

    _untilWander -= dt;
    if (_untilWander <= 0) {
        BOOL busy = (_usage != nil && !_offline && _usage.working);
        _untilWander = busy ? (3.0 + (double)arc4random_uniform(4000) / 1000.0)
                            : (5.0 + (double)arc4random_uniform(9000) / 1000.0);
        CGFloat span = _clawd.roamMax - _clawd.roamMin;
        if (span > 1.0f) {
            CGFloat spot = _clawd.roamMin + (CGFloat)arc4random_uniform((uint32_t)span);
            [_clawd walkTowardX:spot];
        }
    }
}

#pragma mark - Numbers from the computer

- (void)usageClient:(CMUsageClient *)client didReceiveUsage:(CMUsage *)usage
{
    (void)client;
    if (usage == nil) return;

    _usage = usage;
    _offline = NO;
    [_panel showUsage:usage];
    [_panel setOffline:NO];

    // A turn that just finished gets a wave to go with the sparkles.
    BOOL nowCelebrating = (usage.activity == CMActivityCelebrating);
    if (nowCelebrating && !_celebrating) [_clawd wave];
    _celebrating = nowCelebrating;

    if (!_alerting) _clawd.activity = usage.activity;

    BOOL first = !_sawAnswer;
    _sawAnswer = YES;

    if (usage.asking && usage.hasTurn) {
        BOOL fresh = !_knowTurn || usage.turnId != _lastTurn;
        _knowTurn = YES;
        _lastTurn = usage.turnId;
        // The answer that happens to be waiting at launch is not news worth buzzing for.
        if (fresh && !first) {
            [self raiseAlertWithText:usage.turnText];
        }
    } else if (usage.hasTurn) {
        _knowTurn = YES;
        _lastTurn = usage.turnId;
    }

    if (!usage.asking) {
        [self clearAlert];
    }
}

- (void)usageClientDidFail:(CMUsageClient *)client
{
    (void)client;
    _offline = YES;
    if (_usage == nil) {
        NSString *text = [[CMSettings shared] usageURL] != nil
                       ? @"no answer from the computer" : @"hold down to scan the code";
        [_panel showWaitingWithText:text];
    } else {
        [_panel setOffline:YES];
    }
    _clawd.activity = CMActivityIdle;
}

#pragma mark - The waiting mark

- (void)raiseAlertWithText:(NSString *)text
{
    _alerting = YES;
    _quietFor = 0;
    _alertText.text = text.length > 0 ? text : @"Claude is waiting on you";
    [_clawd wakeUp];
    _clawd.activity = CMActivityIdle;   // hands free while he waves
    [_clawd wave];
    [self buzzOnce];

    [UIView animateWithDuration:0.22 animations:^{
        _alertMark.alpha = 1.0f;
        _alertText.alpha = 1.0f;
        _panel.alpha = 0.6f;
    }];
}

- (void)clearAlert
{
    if (!_alerting) return;
    _alerting = NO;
    if (_usage != nil && !_offline) _clawd.activity = _usage.activity;
    [UIView animateWithDuration:0.22 animations:^{
        _alertMark.alpha = 0;
        _alertText.alpha = 0;
        _panel.alpha = 1.0f;
    }];
}

- (void)buzzOnce
{
    NSTimeInterval now = CACurrentMediaTime();
    if (now - _lastBuzz < CMBuzzGap) return;
    _lastBuzz = now;
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

#pragma mark - Hands on

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    _quietFor = 0;
    [self clearAlert];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)first
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)second
{
    (void)first; (void)second;
    return NO;
}

- (void)handleTap:(UITapGestureRecognizer *)tap
{
    _quietFor = 0;
    [self clearAlert];
    CGPoint point = [tap locationInView:self.view];
    if ([_clawd containsPoint:point inView:self.view]) {
        [_clawd startle];
        [self buzzOnce];
    } else {
        [_clawd wakeUp];
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)tap
{
    _quietFor = 0;
    [self clearAlert];
    CGPoint point = [tap locationInView:self.view];
    [self dropFoodAtX:point.x];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan
{
    CGPoint point = [pan locationInView:self.view];
    _quietFor = 0;

    switch (pan.state) {
        case UIGestureRecognizerStateBegan: {
            [self clearAlert];
            if (![_clawd containsPoint:point inView:self.view]) return;
            _carrying = YES;
            _panStart = point;
            _lastPanX = point.x;
            _panDirection = 0;
            _reversals = 0;
            [_clawd liftToPoint:point];
            [self buzzOnce];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (!_carrying) return;
            [_clawd liftToPoint:point];
            [self watchForStrokingAt:point];
            break;
        }
        default: {
            if (!_carrying) return;
            _carrying = NO;
            [_clawd dropFromHand];
            break;
        }
    }
}

/// Back and forth over him counts as a stroke. Up and away is carrying him somewhere.
- (void)watchForStrokingAt:(CGPoint)point
{
    CGFloat step = point.x - _lastPanX;
    if (fabs(step) < 4.0f) return;

    NSInteger way = (step > 0) ? 1 : -1;
    if (_panDirection != 0 && way != _panDirection) _reversals += 1;
    _panDirection = way;
    _lastPanX = point.x;

    if (_reversals < 2) return;
    if (fabs(point.y - _panStart.y) > 44.0f) return;

    _reversals = 0;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - _lastPet < 1.2) return;
    _lastPet = now;

    [[CMPet shared] petByHand];
    _clawd.vigor = [[CMPet shared] lowestNeed];
    [_clawd showHeart];
    [self buzzOnce];
}

#pragma mark - Food

- (void)dropFoodAtX:(CGFloat)x
{
    CGFloat pixel = _clawd.pixel;
    CGFloat size = pixel * 2.0f;
    _foodX = x;
    if (_foodX < _clawd.roamMin) _foodX = _clawd.roamMin;
    if (_foodX > _clawd.roamMax) _foodX = _clawd.roamMax;

    if (_food == nil) {
        _food = [CALayer layer];
        _food.backgroundColor = [CMPalette amber].CGColor;
        [self.view.layer addSublayer:_food];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _food.opacity = 1.0f;
    _food.frame = CGRectMake(_foodX - size * 0.5f, _clawd.groundY - size, size, size);
    [CATransaction commit];

    _foodOut = YES;
    [_clawd wakeUp];
    [_clawd walkTowardX:_foodX];
    [self buzzOnce];
}

- (void)eatFood
{
    if (!_foodOut) return;
    _foodOut = NO;
    _food.opacity = 0;

    CMPet *pet = [CMPet shared];
    [pet feed];
    _clawd.vigor = [pet lowestNeed];
    [_clawd munch];
    [_clawd showHeart];
}

#pragma mark - Where the computer lives

- (void)handleHold:(UILongPressGestureRecognizer *)hold
{
    if (hold.state != UIGestureRecognizerStateBegan) return;
    _quietFor = 0;
    [self clearAlert];
    if (_settingsOpen) return;
    [self buzzOnce];
    [self openScanner];
}

- (void)openScanner
{
    if (_settingsOpen || self.presentedViewController != nil) return;
    _settingsOpen = YES;
    CMScanner *scanner = [[CMScanner alloc] init];
    scanner.delegate = self;
    [self presentViewController:scanner animated:YES completion:nil];
}

- (void)scanner:(CMScanner *)scanner didFindAddress:(NSString *)address key:(NSString *)key
{
    [[CMSettings shared] saveAddress:address key:key];
    [self buzzOnce];
    [scanner dismissViewControllerAnimated:YES completion:^{
        self->_settingsOpen = NO;
        [self settingsChanged];
    }];
}

- (void)scannerDidCancel:(CMScanner *)scanner
{
    [scanner dismissViewControllerAnimated:YES completion:^{
        self->_settingsOpen = NO;
    }];
}

- (void)scannerWantsTyping:(CMScanner *)scanner
{
    [scanner dismissViewControllerAnimated:YES completion:^{
        self->_settingsOpen = NO;
        [self showTyping];
    }];
}

- (void)showTyping
{
    if (_settingsOpen) return;
    _settingsOpen = YES;

    CMSettings *settings = [CMSettings shared];
    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:@"Clawdmeter"
                                            message:@"Address of the computer running Clawdmeter, and its key."
                                     preferredStyle:UIAlertControllerStyleAlert];

    [sheet addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"192.168.1.20:47848";
        field.text = settings.address;
        field.keyboardType = UIKeyboardTypeURL;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [sheet addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"key";
        field.text = settings.key;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];

    __weak CMRoot *weakSelf = self;
    __weak UIAlertController *weakSheet = sheet;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        (void)action;
        CMRoot *me = weakSelf;
        if (me != nil) me->_settingsOpen = NO;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Save"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        (void)action;
        CMRoot *me = weakSelf;
        if (me == nil) return;
        me->_settingsOpen = NO;
        NSArray *fields = weakSheet.textFields;
        NSString *address = fields.count > 0 ? [(UITextField *)fields[0] text] : @"";
        NSString *key = fields.count > 1 ? [(UITextField *)fields[1] text] : @"";
        [[CMSettings shared] saveAddress:address key:key];
        [me settingsChanged];
    }]];

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)settingsChanged
{
    _usage = nil;
    _sawAnswer = NO;
    _knowTurn = NO;
    [_panel showWaitingWithText:[[CMSettings shared] usageURL] != nil
                                ? @"asking the computer" : @"hold down to scan the code"];
    [_panel setOffline:NO];
    [_client refreshNow];
}

@end
