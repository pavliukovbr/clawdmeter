#import <Foundation/Foundation.h>
#import "CMPalette.h"

typedef NS_ENUM(NSInteger, CMActivity) {
    CMActivityIdle = 0,
    CMActivityThinking,
    CMActivityTyping,
    CMActivityReading,
    CMActivitySearching,
    CMActivityBuilding,
    CMActivityCelebrating,
    CMActivitySleeping
};

/// One answer from the PC. Every field has a safe default, because a missing or
/// oddly typed value in the JSON must never take the app down.
@interface CMUsage : NSObject

@property (nonatomic, copy) NSString *plan;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, assign) double fraction;
@property (nonatomic, assign) CMSeverity severity;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy) NSString *note;
@property (nonatomic, copy) NSString *mood;
@property (nonatomic, assign) BOOL working;
@property (nonatomic, assign) CMActivity activity;
@property (nonatomic, assign) BOOL asking;
@property (nonatomic, assign) BOOL hasTurn;
@property (nonatomic, assign) long long turnId;
@property (nonatomic, copy) NSString *turnText;
@property (nonatomic, assign) NSInteger resetSeconds;
@property (nonatomic, copy) NSString *today;
@property (nonatomic, assign) NSInteger requests;

@property (nonatomic, assign) BOOL hasSecond;
@property (nonatomic, copy) NSString *secondTitle;
@property (nonatomic, copy) NSString *secondValue;
@property (nonatomic, assign) double secondFraction;
@property (nonatomic, assign) CMSeverity secondSeverity;

@property (nonatomic, strong) NSDate *receivedAt;

/// Nil when the bytes were not a JSON object at all.
+ (CMUsage *)usageFromData:(NSData *)data;

/// "2h 14m" and friends, or an empty string when there is nothing to count down to.
- (NSString *)resetText;

@end

@class CMUsageClient;

@protocol CMUsageClientDelegate <NSObject>
- (void)usageClient:(CMUsageClient *)client didReceiveUsage:(CMUsage *)usage;
- (void)usageClientDidFail:(CMUsageClient *)client;
@end

/// Asks the PC for the numbers on a timer. Everything runs off the main thread and
/// only the delegate calls come back to it.
@interface CMUsageClient : NSObject

@property (nonatomic, weak) id<CMUsageClientDelegate> delegate;
@property (nonatomic, assign) NSTimeInterval interval;

- (void)start;
- (void)stop;
- (void)refreshNow;

@end
