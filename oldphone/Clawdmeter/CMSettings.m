#import "CMSettings.h"

static NSString *const CMAddressKey = @"pcAddress";
static NSString *const CMKeyKey = @"pcKey";
static NSInteger const CMDefaultPort = 47848;

@implementation CMSettings

+ (instancetype)shared
{
    static CMSettings *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[CMSettings alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSDictionary *bundled = [self bundledSettings];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        _address = [[self trimmed:[defaults stringForKey:CMAddressKey]] copy];
        if (_address.length == 0) {
            _address = [[self trimmed:bundled[@"address"]] copy];
        }

        _key = [[self trimmed:[defaults stringForKey:CMKeyKey]] copy];
        if (_key.length == 0) {
            _key = [[self trimmed:bundled[@"key"]] copy];
        }
    }
    return self;
}

- (NSDictionary *)bundledSettings
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"plist"];
    if (path.length == 0) return nil;
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    return [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
}

- (NSString *)trimmed:(id)value
{
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)saveAddress:(NSString *)address key:(NSString *)key
{
    self.address = [self trimmed:address];
    self.key = [self trimmed:key];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.address forKey:CMAddressKey];
    [defaults setObject:self.key forKey:CMKeyKey];
    [defaults synchronize];
}

- (NSURL *)usageURL
{
    NSString *host = [self trimmed:self.address];
    if (host.length == 0) return nil;

    // Accept a pasted address with a scheme and a trailing slash, not just a bare host.
    NSRange scheme = [host rangeOfString:@"://"];
    if (scheme.location != NSNotFound) {
        host = [host substringFromIndex:scheme.location + scheme.length];
    }
    NSRange slash = [host rangeOfString:@"/"];
    if (slash.location != NSNotFound) {
        host = [host substringToIndex:slash.location];
    }
    if (host.length == 0) return nil;

    if ([host rangeOfString:@":"].location == NSNotFound) {
        host = [NSString stringWithFormat:@"%@:%ld", host, (long)CMDefaultPort];
    }

    NSString *text = [NSString stringWithFormat:@"http://%@/usage?k=%@", host, [self escapedKey]];
    return [NSURL URLWithString:text];
}

/// The key goes in a query string, so anything that would end the value has to go.
- (NSString *)escapedKey
{
    NSString *key = [self trimmed:self.key];
    if (key.length == 0) return @"";

    NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowed removeCharactersInString:@"&=+?#%"];
    NSString *escaped = [key stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return escaped.length > 0 ? escaped : @"";
}

@end
