#import "CMScanner.h"
#import "CMPalette.h"
#import <AVFoundation/AVFoundation.h>

@interface CMScanner () <AVCaptureMetadataOutputObjectsDelegate>
{
    AVCaptureSession *_session;
    AVCaptureVideoPreviewLayer *_preview;
    dispatch_queue_t _cameraQueue;
    UILabel *_hint;
    UIButton *_cancel;
    UIButton *_typing;
    BOOL _done;
    NSTimeInterval _lastComplaint;
}
@end

@implementation CMScanner

+ (BOOL)parseCode:(NSString *)text address:(NSString **)address key:(NSString **)key
{
    if (text.length == 0 || text.length > 512) return NO;
    NSURL *url = [NSURL URLWithString:[text stringByTrimmingCharactersInSet:
                                       [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    if (url == nil || url.host.length == 0) return NO;
    if (![[url.scheme lowercaseString] isEqualToString:@"http"]) return NO;

    NSString *found = nil;
    for (NSString *pair in [url.query componentsSeparatedByString:@"&"]) {
        NSRange mark = [pair rangeOfString:@"="];
        if (mark.location == NSNotFound) continue;
        if (![[pair substringToIndex:mark.location] isEqualToString:@"k"]) continue;
        found = [[pair substringFromIndex:mark.location + 1] stringByRemovingPercentEncoding];
        break;
    }
    if (found.length == 0) return NO;

    NSInteger port = url.port != nil ? url.port.integerValue : 47848;
    if (port <= 0 || port > 65535) return NO;

    if (address != NULL) *address = [NSString stringWithFormat:@"%@:%ld", url.host, (long)port];
    if (key != NULL) *key = found;
    return YES;
}

#pragma mark - Screen

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    _hint = [[UILabel alloc] initWithFrame:CGRectZero];
    _hint.textColor = [CMPalette paper];
    _hint.font = [UIFont systemFontOfSize:15.0f];
    _hint.textAlignment = NSTextAlignmentCenter;
    _hint.numberOfLines = 2;
    _hint.text = @"Point the camera at the code Clawdmeter shows on your computer";
    _hint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55f];
    [self.view addSubview:_hint];

    _cancel = [self buttonWithTitle:@"Cancel" action:@selector(cancelTapped)];
    _typing = [self buttonWithTitle:@"Type it instead" action:@selector(typingTapped)];

    _cameraQueue = dispatch_queue_create("clawdmeter.camera", DISPATCH_QUEUE_SERIAL);

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(stopCamera)
                   name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(startCameraIfAllowed)
                   name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[CMPalette clayLight] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16.0f];
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55f];
    button.layer.cornerRadius = 8.0f;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
    return button;
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGRect bounds = self.view.bounds;
    _preview.frame = bounds;
    [self matchOrientation];

    CGFloat side = 12.0f;
    _hint.frame = CGRectMake(0, 0, bounds.size.width, 52.0f);
    CGFloat width = (bounds.size.width - side * 3) / 2;
    CGFloat y = bounds.size.height - 44.0f - side;
    _cancel.frame = CGRectMake(side, y, width, 44.0f);
    _typing.frame = CGRectMake(side * 2 + width, y, width, 44.0f);
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self startCameraIfAllowed];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self stopCamera];
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark - Camera

- (void)startCameraIfAllowed
{
    if (_done || self.view.window == nil) return;

    if ([AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] == nil) {
        [self say:@"This phone has no camera Clawdmeter can use. Tap Type it instead."];
        return;
    }

    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        [self startCamera];
    } else if (status == AVAuthorizationStatusNotDetermined) {
        __weak CMScanner *weakSelf = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                CMScanner *me = weakSelf;
                if (me == nil) return;
                if (granted) [me startCamera];
                else [me say:@"Camera access is off. Turn it on in Settings, Privacy, Camera."];
            });
        }];
    } else {
        [self say:@"Camera access is off. Turn it on in Settings, Privacy, Camera."];
    }
}

- (void)startCamera
{
    if (_done) return;

    if (_session == nil) {
        NSError *error = nil;
        AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
        if (input == nil) {
            [self say:@"The camera would not start. Tap Type it instead."];
            return;
        }

        AVCaptureSession *session = [[AVCaptureSession alloc] init];
        if (![session canAddInput:input]) {
            [self say:@"The camera would not start. Tap Type it instead."];
            return;
        }
        [session addInput:input];

        AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
        if (![session canAddOutput:output]) {
            [self say:@"The camera would not start. Tap Type it instead."];
            return;
        }
        [session addOutput:output];

        // The kinds of codes can only be picked once the output belongs to a session.
        if (![output.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode]) {
            [self say:@"This camera cannot read codes. Tap Type it instead."];
            return;
        }
        [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
        output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];

        _preview = [AVCaptureVideoPreviewLayer layerWithSession:session];
        _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
        _preview.frame = self.view.bounds;
        [self.view.layer insertSublayer:_preview atIndex:0];
        [self matchOrientation];

        _session = session;
    }

    AVCaptureSession *session = _session;
    dispatch_async(_cameraQueue, ^{
        // Starting a session blocks for a moment, so keep it off the main thread.
        if (!session.running) [session startRunning];
    });
}

- (void)stopCamera
{
    AVCaptureSession *session = _session;
    if (session == nil) return;
    dispatch_async(_cameraQueue, ^{
        if (session.running) [session stopRunning];
    });
}

- (void)matchOrientation
{
    AVCaptureConnection *connection = _preview.connection;
    if (connection == nil || !connection.supportsVideoOrientation) return;
    switch ([UIApplication sharedApplication].statusBarOrientation) {
        case UIInterfaceOrientationLandscapeLeft:
            connection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIInterfaceOrientationLandscapeRight:
            connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            connection.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        default:
            connection.videoOrientation = AVCaptureVideoOrientationPortrait;
            break;
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputMetadataObjects:(NSArray *)objects
       fromConnection:(AVCaptureConnection *)connection
{
    (void)output;
    (void)connection;
    if (_done) return;

    for (id object in objects) {
        if (![object isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) continue;
        NSString *text = [(AVMetadataMachineReadableCodeObject *)object stringValue];
        NSString *address = nil;
        NSString *key = nil;
        if ([CMScanner parseCode:text address:&address key:&key]) {
            _done = YES;
            [self stopCamera];
            [self.delegate scanner:self didFindAddress:address key:key];
            return;
        }
    }

    // Some other code is in view. Say so, but not on every frame.
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - _lastComplaint > 2.0) {
        _lastComplaint = now;
        [self say:@"That code is not from Clawdmeter. Turn on Screen on an Old Phone on your computer."];
    }
}

#pragma mark - Buttons

- (void)say:(NSString *)text
{
    _hint.text = text;
}

- (void)cancelTapped
{
    _done = YES;
    [self stopCamera];
    [self.delegate scannerDidCancel:self];
}

- (void)typingTapped
{
    _done = YES;
    [self stopCamera];
    [self.delegate scannerWantsTyping:self];
}

@end
