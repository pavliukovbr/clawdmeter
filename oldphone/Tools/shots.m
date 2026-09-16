// Draws the screens to PNG files on a Mac, so the layout can be checked at the exact
// size the phone uses without an iPhone in hand.
//
// This file is NOT part of the app. build.sh compiles Clawdmeter/*.m and nothing else,
// so none of this reaches the phone. It builds against the same sources through
// Tools/shots.sh, which uses Mac Catalyst and leaves the shipped build alone.
//
//   ./Tools/shots.sh [output folder]

#import <UIKit/UIKit.h>
#import "CMRoot.h"
#import "CMClawd.h"
#import "CMUsage.h"

static NSString *const CMIdleJSON =
@"{\"plan\":\"Max 20x\",\"title\":\"Weekly limit\",\"value\":\"64%\",\"fraction\":0.64,"
 "\"severity\":\"normal\",\"detail\":\"resets Monday at 9am\",\"note\":\"\",\"mood\":\"idle\","
 "\"working\":false,\"activity\":\"idle\",\"asking\":false,\"turnId\":null,\"turnText\":\"\","
 "\"resetSeconds\":8040,\"today\":\"1.2M tokens\",\"requests\":34,"
 "\"second\":{\"title\":\"Session\",\"value\":\"18%\",\"fraction\":0.18,\"severity\":\"normal\"}}";

static NSString *const CMTypingJSON =
@"{\"plan\":\"Max 20x\",\"title\":\"Weekly limit\",\"value\":\"64%\",\"fraction\":0.64,"
 "\"severity\":\"normal\",\"detail\":\"resets Monday at 9am\",\"mood\":\"busy\","
 "\"working\":true,\"activity\":\"typing\",\"asking\":false,\"turnId\":null,"
 "\"resetSeconds\":8040,\"today\":\"1.2M tokens\",\"requests\":34,"
 "\"second\":{\"title\":\"Session\",\"value\":\"31%\",\"fraction\":0.31,\"severity\":\"normal\"}}";

static NSString *const CMBuildingJSON =
@"{\"plan\":\"Max 20x\",\"title\":\"Weekly limit\",\"value\":\"64%\",\"fraction\":0.64,"
 "\"severity\":\"normal\",\"detail\":\"resets Monday at 9am\",\"mood\":\"busy\","
 "\"working\":true,\"activity\":\"building\",\"asking\":false,\"turnId\":null,"
 "\"resetSeconds\":8040,\"today\":\"1.4M tokens\",\"requests\":41,"
 "\"second\":{\"title\":\"Session\",\"value\":\"44%\",\"fraction\":0.44,\"severity\":\"warning\"}}";

static NSString *const CMAskingJSON =
@"{\"plan\":\"Max 20x\",\"title\":\"Weekly limit\",\"value\":\"64%\",\"fraction\":0.64,"
 "\"severity\":\"normal\",\"detail\":\"resets Monday at 9am\",\"mood\":\"busy\","
 "\"working\":true,\"activity\":\"thinking\",\"asking\":true,\"turnId\":7,"
 "\"turnText\":\"Claude is waiting on you\",\"resetSeconds\":8040,\"today\":\"1.4M tokens\","
 "\"requests\":41,\"second\":{\"title\":\"Session\",\"value\":\"44%\",\"fraction\":0.44,"
 "\"severity\":\"warning\"}}";

static NSString *const CMSleepingJSON =
@"{\"plan\":\"Max 20x\",\"title\":\"Weekly limit\",\"value\":\"64%\",\"fraction\":0.64,"
 "\"severity\":\"normal\",\"detail\":\"resets Monday at 9am\",\"mood\":\"sleeping\","
 "\"working\":false,\"activity\":\"sleeping\",\"asking\":false,\"turnId\":null,"
 "\"resetSeconds\":8040,\"today\":\"1.4M tokens\",\"requests\":41,"
 "\"second\":{\"title\":\"Session\",\"value\":\"12%\",\"fraction\":0.12,\"severity\":\"normal\"}}";

static NSString *const CMCriticalJSON =
@"{\"plan\":\"Max 20x\",\"title\":\"Weekly limit\",\"value\":\"96%\",\"fraction\":0.96,"
 "\"severity\":\"critical\",\"detail\":\"almost out for this week\",\"mood\":\"tired\","
 "\"working\":true,\"activity\":\"reading\",\"asking\":false,\"turnId\":null,"
 "\"resetSeconds\":10800,\"today\":\"2.6M tokens\",\"requests\":118,"
 "\"second\":{\"title\":\"Session\",\"value\":\"88%\",\"fraction\":0.88,\"severity\":\"critical\"}}";

#pragma mark - Small helpers

static CMClawd *FindClawd(UIView *view)
{
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:[CMClawd class]]) return (CMClawd *)child;
    }
    return nil;
}

static CMRoot *MakeRoot(CGSize size)
{
    CMRoot *root = [[CMRoot alloc] init];
    root.view.frame = CGRectMake(0, 0, size.width, size.height);
    [root.view setNeedsLayout];
    [root.view layoutIfNeeded];
    return root;
}

static void Feed(CMRoot *root, NSString *json)
{
    CMUsage *usage = [CMUsage usageFromData:[json dataUsingEncoding:NSUTF8StringEncoding]];
    if (usage == nil) {
        printf("bad test json\n");
        return;
    }
    [(id<CMUsageClientDelegate>)root usageClient:nil didReceiveUsage:usage];
}

static void GoQuiet(CMRoot *root)
{
    [(id<CMUsageClientDelegate>)root usageClientDidFail:nil];
}

static void Tick(CMRoot *root, int frames, CGFloat step)
{
    CMClawd *clawd = FindClawd(root.view);
    for (int i = 0; i < frames; i++) [clawd tick:step];
}

static void Shoot(CMRoot *root, NSString *folder, NSString *name)
{
    [root.view setNeedsLayout];
    [root.view layoutIfNeeded];
    // A layout pass puts every limb back on its resting mark, and only a tick puts the
    // pose back. On the phone the next frame does this within a thirtieth of a second.
    [FindClawd(root.view) tick:0.016f];

    CGSize size = root.view.bounds.size;
    UIGraphicsBeginImageContextWithOptions(size, YES, 2.0f);   // 2x, same as a 4S screen
    [root.view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    NSString *path = [folder stringByAppendingPathComponent:name];
    NSData *png = UIImagePNGRepresentation(image);
    [png writeToFile:path atomically:YES];
    printf("%s  %.0fx%.0f pt\n", path.UTF8String, (double)size.width, (double)size.height);
}

#pragma mark - The shots

int main(int argc, char *argv[])
{
    @autoreleasepool {
        NSString *folder = (argc > 1) ? [NSString stringWithUTF8String:argv[1]] : @"shots";
        [[NSFileManager defaultManager] createDirectoryAtPath:folder
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];

        CGSize wide = CGSizeMake(480, 320);
        CGSize tall = CGSizeMake(320, 480);

        // Nothing going on, the everyday screen.
        CMRoot *root = MakeRoot(wide);
        Feed(root, CMIdleJSON);
        [FindClawd(root.view) standAtX:150];
        Tick(root, 20, 0.05f);
        Shoot(root, folder, @"01-idle.png");

        // Claude typing, laptop out.
        root = MakeRoot(wide);
        Feed(root, CMTypingJSON);
        [FindClawd(root.view) standAtX:150];
        Tick(root, 20, 0.05f);
        Shoot(root, folder, @"02-typing.png");

        // Claude running commands, hard hat and hammer.
        root = MakeRoot(wide);
        Feed(root, CMBuildingJSON);
        [FindClawd(root.view) standAtX:150];
        Tick(root, 20, 0.05f);
        Shoot(root, folder, @"03-building.png");

        // Claude asking something. The first answer never raises the mark, so feed twice.
        root = MakeRoot(wide);
        Feed(root, CMTypingJSON);
        Feed(root, CMAskingJSON);
        [FindClawd(root.view) standAtX:150];
        Tick(root, 10, 0.05f);
        Shoot(root, folder, @"04-asking.png");

        // Nothing happening for a while, so he naps.
        root = MakeRoot(wide);
        Feed(root, CMSleepingJSON);
        CMClawd *sleeper = FindClawd(root.view);
        [sleeper standAtX:150];
        [sleeper goToSleep];
        Tick(root, 26, 0.1f);
        Shoot(root, folder, @"05-sleeping.png");

        // Nearly out of the weekly limit.
        root = MakeRoot(wide);
        Feed(root, CMCriticalJSON);
        [FindClawd(root.view) standAtX:150];
        Tick(root, 20, 0.05f);
        Shoot(root, folder, @"06-critical.png");

        // The PC stopped answering.
        root = MakeRoot(wide);
        Feed(root, CMIdleJSON);
        GoQuiet(root);
        [FindClawd(root.view) standAtX:150];
        Tick(root, 20, 0.05f);
        Shoot(root, folder, @"07-offline.png");

        // Halfway through a drag, Clawd up in the air.
        root = MakeRoot(wide);
        Feed(root, CMIdleJSON);
        [FindClawd(root.view) liftToPoint:CGPointMake(300, 150)];
        Tick(root, 8, 0.05f);
        Shoot(root, folder, @"08-held.png");

        // Just been stroked.
        root = MakeRoot(wide);
        Feed(root, CMIdleJSON);
        CMClawd *petted = FindClawd(root.view);
        [petted standAtX:200];
        [petted showHeart];
        Tick(root, 5, 0.05f);
        Shoot(root, folder, @"09-petted.png");

        // Upright, which has to work even though the phone is meant to lie on its side.
        root = MakeRoot(tall);
        Feed(root, CMTypingJSON);
        [FindClawd(root.view) standAtX:120];
        Tick(root, 20, 0.05f);
        Shoot(root, folder, @"10-portrait.png");
    }
    return 0;
}
