#import "CMUsage.h"
#import "CMSettings.h"
#import <math.h>

#pragma mark - Reading JSON without trusting it

static NSDictionary *CMDictionary(id object)
{
    return [object isKindOfClass:[NSDictionary class]] ? (NSDictionary *)object : nil;
}

static NSString *CMString(NSDictionary *source, NSString *key)
{
    id value = source[key];
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return @"";
}

static NSNumber *CMNumber(NSDictionary *source, NSString *key)
{
    id value = source[key];
    if ([value isKindOfClass:[NSNumber class]]) return (NSNumber *)value;
    if ([value isKindOfClass:[NSString class]]) {
        NSScanner *scanner = [NSScanner scannerWithString:(NSString *)value];
        double parsed = 0;
        if ([scanner scanDouble:&parsed] && scanner.isAtEnd) return @(parsed);
    }
    return nil;
}

static double CMDouble(NSDictionary *source, NSString *key, double fallback)
{
    NSNumber *number = CMNumber(source, key);
    if (number == nil) return fallback;
    double value = number.doubleValue;
    return isfinite(value) ? value : fallback;
}

static NSInteger CMInteger(NSDictionary *source, NSString *key)
{
    double value = CMDouble(source, key, 0);
    if (value < 0) return 0;
    if (value > (double)NSIntegerMax) return NSIntegerMax;
    return (NSInteger)value;
}

static BOOL CMBool(NSDictionary *source, NSString *key)
{
    NSNumber *number = CMNumber(source, key);
    return number != nil && number.boolValue;
}

static double CMClamp(double value, double low, double high)
{
    if (!isfinite(value)) return low;
    if (value < low) return low;
    if (value > high) return high;
    return value;
}

static CMActivity CMActivityFromName(NSString *name)
{
    if (![name isKindOfClass:[NSString class]]) return CMActivityIdle;
    NSArray *names = @[@"idle", @"thinking", @"typing", @"reading",
                       @"searching", @"building", @"celebrating", @"sleeping"];
    NSUInteger index = [names indexOfObject:[name lowercaseString]];
    return index == NSNotFound ? CMActivityIdle : (CMActivity)index;
}

#pragma mark - CMUsage

@implementation CMUsage

- (instancetype)init
{
    self = [super init];
    if (self) {
        _plan = @"";
        _title = @"";
        _value = @"";
        _detail = @"";
        _note = @"";
        _mood = @"idle";
        _turnText = @"";
        _today = @"";
        _secondTitle = @"";
        _secondValue = @"";
        _receivedAt = [NSDate date];
    }
    return self;
}

+ (CMUsage *)usageFromData:(NSData *)data
{
    if (data.length == 0) return nil;

    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    NSDictionary *root = CMDictionary(parsed);
    if (root == nil) return nil;

    CMUsage *usage = [[CMUsage alloc] init];
    usage.plan = CMString(root, @"plan");
    usage.title = CMString(root, @"title");
    usage.value = CMString(root, @"value");
    usage.fraction = CMClamp(CMDouble(root, @"fraction", 0), 0, 1);
    usage.severity = [CMPalette severityFromName:CMString(root, @"severity")];
    usage.detail = CMString(root, @"detail");
    usage.note = CMString(root, @"note");
    usage.mood = CMString(root, @"mood");
    usage.working = CMBool(root, @"working");
    usage.activity = CMActivityFromName(CMString(root, @"activity"));
    usage.asking = CMBool(root, @"asking");
    usage.turnText = CMString(root, @"turnText");
    usage.resetSeconds = CMInteger(root, @"resetSeconds");
    usage.today = CMString(root, @"today");
    usage.requests = CMInteger(root, @"requests");

    NSNumber *turn = CMNumber(root, @"turnId");
    usage.hasTurn = turn != nil;
    usage.turnId = turn != nil ? turn.longLongValue : 0;

    NSDictionary *second = CMDictionary(root[@"second"]);
    if (second != nil) {
        usage.hasSecond = YES;
        usage.secondTitle = CMString(second, @"title");
        usage.secondValue = CMString(second, @"value");
        usage.secondFraction = CMClamp(CMDouble(second, @"fraction", 0), 0, 1);
        usage.secondSeverity = [CMPalette severityFromName:CMString(second, @"severity")];
    }

    usage.receivedAt = [NSDate date];
    return usage;
}

- (NSString *)resetText
{
    // Keep counting down from the moment the answer arrived, so a stale answer does not
    // sit there claiming the same two hours forever.
    NSTimeInterval since = [[NSDate date] timeIntervalSinceDate:self.receivedAt];
    if (!isfinite(since) || since < 0) since = 0;

    NSInteger seconds = self.resetSeconds - (NSInteger)since;
    if (seconds <= 0) return @"";

    NSInteger hours = seconds / 3600;
    NSInteger minutes = (seconds % 3600) / 60;
    if (hours > 0) return [NSString stringWithFormat:@"%ldh %02ldm", (long)hours, (long)minutes];
    if (minutes > 0) return [NSString stringWithFormat:@"%ldm", (long)minutes];
    return @"under a minute";
}

@end

#pragma mark - CMUsageClient

@interface CMUsageClient ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL inFlight;
@end

@implementation CMUsageClient

- (instancetype)init
{
    self = [super init];
    if (self) {
        _interval = 4.0;

        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 8.0;
        configuration.timeoutIntervalForResource = 12.0;
        configuration.HTTPShouldSetCookies = NO;
        configuration.HTTPMaximumConnectionsPerHost = 1;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (void)dealloc
{
    [_timer invalidate];
    [_session invalidateAndCancel];
}

- (void)start
{
    [self stop];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.interval
                                                  target:self
                                                selector:@selector(refreshNow)
                                                userInfo:nil
                                                 repeats:YES];
    // The run loop switches modes while a finger is down, and the poll should not pause.
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self refreshNow];
}

- (void)stop
{
    [self.timer invalidate];
    self.timer = nil;
}

- (void)refreshNow
{
    if (self.inFlight) return;

    NSURL *url = [[CMSettings shared] usageURL];
    if (url == nil) {
        [self.delegate usageClientDidFail:self];
        return;
    }

    self.inFlight = YES;
    __weak CMUsageClient *weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        CMUsage *usage = nil;
        if (error == nil) {
            NSInteger status = 200;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                status = [(NSHTTPURLResponse *)response statusCode];
            }
            if (status >= 200 && status < 300) {
                usage = [CMUsage usageFromData:data];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            CMUsageClient *client = weakSelf;
            if (client == nil) return;
            client.inFlight = NO;
            if (usage != nil) {
                [client.delegate usageClient:client didReceiveUsage:usage];
            } else {
                [client.delegate usageClientDidFail:client];
            }
        });
    }];
    [task resume];
}

@end
