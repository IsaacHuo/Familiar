#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Byte-oriented pseudo-terminal using the vendored guest's own terminal driver.
/// The caller must hold exclusive guest/mount ownership until close succeeds.
@interface ISHTerminalSession : NSObject
@property(atomic, readonly) int pid;
- (instancetype)initWithMaximumOutputBytes:(NSUInteger)maximumOutputBytes
                                    output:(void (^)(NSData *))output
                                    exited:(void (^)(int))exited
                                    failed:(void (^)(NSError *))failed
    NS_SWIFT_NAME(init(maximumOutputBytes:output:exited:failed:));
- (int)startShellCommand:(NSString *)command columns:(NSUInteger)columns rows:(NSUInteger)rows
    NS_SWIFT_NAME(start(command:columns:rows:));
/// Returns accepted byte count or a negative guest errno. Does not decode text.
- (NSInteger)sendInput:(NSData *)data;
- (BOOL)resizeColumns:(NSUInteger)columns rows:(NSUInteger)rows;
- (void)interrupt;
/// Stops the complete process tree before its caller may release mounts.
- (BOOL)close;
@end

NS_ASSUME_NONNULL_END
