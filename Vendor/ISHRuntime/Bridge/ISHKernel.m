#import "ISHKernel.h"

#include <pthread.h>
#include <netdb.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <zlib.h>

#define ISH_INTERNAL 1
#include "kernel/init.h"
#include "kernel/task.h"
#include "kernel/calls.h"
#include "kernel/fs.h"
#include "fs/fake.h"
#include "fs/fd.h"
#include "fs/dev.h"
#include "fs/devices.h"
#include "fs/path.h"
#include "fs/tty.h"
#include "FamiliarISHNetworkPolicy.h"

NSNotificationName const ISHProcessExitedNotification = @"FamiliarISHProcessExited";

extern void (*exit_hook)(struct task *task, int code);
extern const char *sock_tmp_prefix;

static uint64_t FamiliarISHOctal(const char *value, size_t length) {
    uint64_t result = 0;
    for (size_t index = 0; index < length; index++) {
        char character = value[index];
        if (character == '\0' || character == ' ') continue;
        if (character < '0' || character > '7') break;
        result = (result << 3) + (uint64_t)(character - '0');
    }
    return result;
}

static BOOL FamiliarISHSafeArchivePath(NSString *path) {
    if (path.length == 0 || path.isAbsolutePath) return NO;
    for (NSString *component in path.pathComponents) {
        if ([component isEqualToString:@".."] || [component isEqualToString:@"."]) return NO;
    }
    return YES;
}

static void FamiliarISHHandleProcessExit(struct task *task, int code) {
    if (task->parent != NULL && task->parent->parent != NULL) {
        return;
    }
    pid_t pid = task->pid;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:ISHProcessExitedNotification
            object:nil
            userInfo:@{@"pid": @(pid), @"code": @(code)}];
    });
}

@implementation ISHKernel {
    BOOL _isBooted;
}

+ (ISHKernel *)shared {
    static ISHKernel *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ISHKernel alloc] init];
    });
    return instance;
}

- (BOOL)isBooted {
    @synchronized(self) {
        return _isBooted;
    }
}

- (int)bootWithRootPath:(NSString *)rootPath {
    @synchronized(self) {
        if (_isBooted) {
            return 0;
        }

        NSString *dataPath = [rootPath stringByAppendingPathComponent:@"data"];
        int err = mount_root(&fakefs, dataPath.fileSystemRepresentation);
        if (err < 0) {
            return err;
        }

        err = become_first_process();
        if (err < 0) {
            return err;
        }
        current->thread = pthread_self();

        generic_mknodat(AT_PWD, "/dev/null", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_NULL_MINOR));
        generic_mknodat(AT_PWD, "/dev/zero", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_ZERO_MINOR));
        generic_mknodat(AT_PWD, "/dev/full", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_FULL_MINOR));
        generic_mknodat(AT_PWD, "/dev/random", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_RANDOM_MINOR));
        generic_mknodat(AT_PWD, "/dev/urandom", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_URANDOM_MINOR));
        // Bind mounts are represented by symlinks below the fakefs data root.
        // The bundled Alpine minirootfs does not contain /workspace, so create
        // the shared parent before any per-task Files/Outputs/Work/Environment
        // mount is installed.
        generic_mkdirat(AT_PWD, "/workspace", 0755);

        do_mount(&procfs, "proc", "/proc", "", 0);
        do_mount(&devptsfs, "devpts", "/dev/pts", "", 0);

        NSString *socketPrefix = [NSTemporaryDirectory() stringByAppendingString:@"familiar-ishsock"];
        sock_tmp_prefix = strdup(socketPrefix.fileSystemRepresentation);
        exit_hook = FamiliarISHHandleProcessExit;
        _isBooted = YES;
        [self configureDNS];
        return 0;
    }
}

- (BOOL)configureDNS {
    if (!self.isBooted) return NO;
    familiar_ish_network_refresh_dns_servers();
    struct sockaddr_storage servers[8] = {0};
    size_t count = familiar_ish_network_copy_dns_servers(servers, 8);
    NSMutableString *configuration = [NSMutableString string];
    char address[NI_MAXHOST];
    for (size_t index = 0; index < count; index++) {
        struct sockaddr *server = (struct sockaddr *)&servers[index];
        socklen_t length = server->sa_len;
        if (length == 0) continue;
        if (getnameinfo(
                server,
                length,
                address,
                sizeof(address),
                NULL,
                0,
                NI_NUMERICHOST
            ) == 0) {
            [configuration appendFormat:@"nameserver %s\n", address];
        }
    }
    if (configuration.length == 0) return NO;

    struct task *savedCurrent = current;
    current = pid_get_task(1);
    struct fd *fd = generic_open(
        "/etc/resolv.conf",
        O_WRONLY_ | O_CREAT_ | O_TRUNC_,
        0666
    );
    BOOL succeeded = NO;
    if (!IS_ERR(fd)) {
        size_t length = [configuration lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        succeeded = fd->ops->write(fd, configuration.UTF8String, length) == (ssize_t)length;
        fd_close(fd);
    }
    current = savedCurrent;
    return succeeded;
}

- (BOOL)installRootfsArchive:(NSString *)archivePath
               destination:(NSString *)destinationPath
                     error:(NSError **)error {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (![fileManager createDirectoryAtPath:destinationPath
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:error]) {
        return NO;
    }
    gzFile archive = gzopen(archivePath.fileSystemRepresentation, "rb");
    if (archive == NULL) {
        if (error) *error = [NSError errorWithDomain:@"FamiliarISHRuntime" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Unable to open the bundled rootfs archive."}];
        return NO;
    }
    BOOL succeeded = YES;
    uint8_t header[512];
    while (gzread(archive, header, sizeof(header)) == sizeof(header)) {
        BOOL empty = YES;
        for (size_t index = 0; index < sizeof(header); index++) {
            if (header[index] != 0) { empty = NO; break; }
        }
        if (empty) break;

        char nameBuffer[256] = {0};
        memcpy(nameBuffer, header, 100);
        char prefixBuffer[156] = {0};
        memcpy(prefixBuffer, header + 345, 155);
        NSString *name = [NSString stringWithUTF8String:nameBuffer] ?: @"";
        NSString *prefix = [NSString stringWithUTF8String:prefixBuffer] ?: @"";
        NSString *relative = prefix.length > 0 ? [prefix stringByAppendingPathComponent:name] : name;
        while ([relative hasPrefix:@"./"]) relative = [relative substringFromIndex:2];
        uint64_t size = FamiliarISHOctal((const char *)header + 124, 12);
        char type = ((const char *)header)[156];
        char linkBuffer[101] = {0};
        memcpy(linkBuffer, header + 157, 100);
        NSString *linkTarget = [NSString stringWithUTF8String:linkBuffer] ?: @"";

        // `tar -C <root> .` emits a leading `./` directory entry. After the
        // normalization above that entry is the empty string: it represents
        // the already-created destination root and has no payload. Accept only
        // that exact zero-length directory entry; every other empty path stays
        // rejected by FamiliarISHSafeArchivePath.
        if (relative.length == 0 && type == '5' && size == 0) {
            continue;
        }

        if (!FamiliarISHSafeArchivePath(relative)) {
            succeeded = NO;
            if (error) *error = [NSError errorWithDomain:@"FamiliarISHRuntime" code:2 userInfo:@{NSLocalizedDescriptionKey: @"The rootfs archive contains an unsafe path."}];
            break;
        }
        NSString *destination = [destinationPath stringByAppendingPathComponent:relative];
        NSString *parent = destination.stringByDeletingLastPathComponent;
        [fileManager createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];

        if (type == '5') {
            [fileManager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:nil];
        } else if (type == '2') {
            [fileManager removeItemAtPath:destination error:nil];
            if (symlink(linkTarget.fileSystemRepresentation, destination.fileSystemRepresentation) != 0) {
                succeeded = NO;
            }
        } else if (type == '1') {
            NSString *source = [destinationPath stringByAppendingPathComponent:linkTarget];
            [fileManager removeItemAtPath:destination error:nil];
            if (link(source.fileSystemRepresentation, destination.fileSystemRepresentation) != 0) {
                succeeded = NO;
            }
        } else if (type == '0' || type == '\0') {
            [fileManager removeItemAtPath:destination error:nil];
            if (![fileManager createFileAtPath:destination contents:nil attributes:nil]) {
                succeeded = NO;
                break;
            }
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:destination];
            uint64_t remaining = size;
            uint8_t buffer[32768];
            while (remaining > 0) {
                unsigned int requested = (unsigned int)MIN((uint64_t)sizeof(buffer), remaining);
                int count = gzread(archive, buffer, requested);
                if (count <= 0) { succeeded = NO; break; }
                [handle writeData:[NSData dataWithBytes:buffer length:(NSUInteger)count]];
                remaining -= (uint64_t)count;
            }
            [handle closeFile];
            uint64_t padding = (512 - (size % 512)) % 512;
            while (padding > 0) {
                unsigned int requested = (unsigned int)MIN((uint64_t)sizeof(buffer), padding);
                int count = gzread(archive, buffer, requested);
                if (count <= 0) { succeeded = NO; break; }
                padding -= (uint64_t)count;
            }
            continue;
        }

        uint64_t padded = ((size + 511) / 512) * 512;
        uint8_t discard[32768];
        while (padded > 0) {
            unsigned int requested = (unsigned int)MIN((uint64_t)sizeof(discard), padded);
            int count = gzread(archive, discard, requested);
            if (count <= 0) { succeeded = NO; break; }
            padded -= (uint64_t)count;
        }
        if (!succeeded) break;
    }
    gzclose(archive);
    if (!succeeded && error && *error == nil) {
        *error = [NSError errorWithDomain:@"FamiliarISHRuntime" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Unable to extract the bundled rootfs archive."}];
    }
    return succeeded;
}

- (int)bindMountPath:(NSString *)linuxPath
          toHostPath:(NSString *)hostPath
             readOnly:(BOOL)readOnly {
    if (!self.isBooted) {
        return -1;
    }
    return fakefs_bind_mount(
        linuxPath.fileSystemRepresentation,
        hostPath.fileSystemRepresentation,
        readOnly ? true : false
    );
}

- (int)bindUnmountPath:(NSString *)linuxPath {
    if (!self.isBooted) {
        return -1;
    }
    return fakefs_bind_unmount(linuxPath.fileSystemRepresentation);
}

@end
