#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const ISHProcessExitedNotification;

@interface ISHKernel : NSObject

@property(class, nonatomic, readonly) ISHKernel *shared;
@property(atomic, readonly) BOOL isBooted;

- (int)bootWithRootPath:(NSString *)rootPath;
- (BOOL)installRootfsArchive:(NSString *)archivePath
               destination:(NSString *)destinationPath
                     error:(NSError * _Nullable * _Nullable)error;
- (int)bindMountPath:(NSString *)linuxPath
          toHostPath:(NSString *)hostPath
             readOnly:(BOOL)readOnly;
- (int)bindUnmountPath:(NSString *)linuxPath;

@end

NS_ASSUME_NONNULL_END
