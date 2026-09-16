#import <UIKit/UIKit.h>
#import "CMRoot.h"
#import "CMPet.h"
#import "CMPalette.h"

@interface CMApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation CMApp

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)options
{
    (void)options;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [CMPalette backgroundBottom];
    self.window.rootViewController = [[CMRoot alloc] init];
    [self.window makeKeyAndVisible];

    // This one lives on a desk, plugged in, so the screen should stay on.
    application.idleTimerDisabled = YES;
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    (void)application;
    [[CMPet shared] save];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    (void)application;
    [[CMPet shared] save];
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([CMApp class]));
    }
}
