#import <UIKit/UIKit.h>

@class CMScanner;

@protocol CMScannerDelegate <NSObject>
- (void)scanner:(CMScanner *)scanner didFindAddress:(NSString *)address key:(NSString *)key;
- (void)scannerDidCancel:(CMScanner *)scanner;
- (void)scannerWantsTyping:(CMScanner *)scanner;
@end

/// Full screen camera that reads the code Clawdmeter shows on the computer.
@interface CMScanner : UIViewController

@property (nonatomic, weak) id<CMScannerDelegate> delegate;

/// Reads "http://host:port/?k=key". Anything else is not ours and gives NO.
+ (BOOL)parseCode:(NSString *)text address:(NSString **)address key:(NSString **)key;

@end
