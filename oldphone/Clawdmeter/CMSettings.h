#import <Foundation/Foundation.h>

/// Where the PC is and the key that opens its usage page.
///
/// The install script drops a Settings.plist inside the bundle, which is the normal
/// way to set this up. Anything typed in the settings panel is kept in NSUserDefaults
/// and wins over the bundle, so a reinstall does not throw away a hand edit.
@interface CMSettings : NSObject

+ (instancetype)shared;

/// A host on its own, a host with a port, or a whole http address. All three work.
@property (nonatomic, copy) NSString *address;
@property (nonatomic, copy) NSString *key;

/// Nil when there is no address yet, which is the "tell me where the PC is" state.
- (NSURL *)usageURL;

- (void)saveAddress:(NSString *)address key:(NSString *)key;

@end
