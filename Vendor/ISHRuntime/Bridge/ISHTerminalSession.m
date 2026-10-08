#import "ISHTerminalSession.h"
#import "ISHKernel.h"
#import "ISHShellExecutor.h"
#include "kernel/init.h"
#include "FamiliarISHExecutionOwner.h"
#include "kernel/calls.h"
#include "kernel/task.h"
#include "fs/devices.h"
#include "fs/tty.h"
#include <string.h>

@interface ISHTerminalSession () {
    struct tty *_tty;
    dispatch_queue_t _delivery;
    NSUInteger _maximumOutputBytes;
    NSUInteger _outputBytes;
    uint64_t _executionOwner;
    BOOL _completed;
    BOOL _outputLimited;
    NSMutableData *_pendingOutput;
    BOOL _deliveryScheduled;
}
@property(atomic, readwrite) int pid;
@property(nonatomic, copy) void (^output)(NSData *);
@property(nonatomic, copy) void (^exited)(int);
@property(nonatomic, copy) void (^failed)(NSError *);
- (void)attachTTY:(struct tty *)tty;
- (int)deliverBytes:(const void *)bytes length:(size_t)length;
- (void)flushOutput;
@end

static _Thread_local void *startingSession;
static int terminal_init(struct tty *tty) {
    if (!startingSession) return _EINVAL;
    ISHTerminalSession *session = (__bridge ISHTerminalSession *)startingSession;
    tty->data = (void *)CFBridgingRetain(session);
    [session attachTTY:tty];
    return 0;
}
static int terminal_write(struct tty *tty, const void *bytes, size_t length, bool blocking) {
    return [(__bridge ISHTerminalSession *)tty->data deliverBytes:bytes length:length];
}
static void terminal_cleanup(struct tty *tty) {
    ISHTerminalSession *session = CFBridgingRelease(tty->data);
    tty->data = NULL;
    [session attachTTY:NULL];
}
static const struct tty_driver_ops terminal_ops = {
    .init = terminal_init, .write = terminal_write, .cleanup = terminal_cleanup,
};
static struct tty_driver terminal_driver = {.ops = &terminal_ops};

@implementation ISHTerminalSession
- (instancetype)initWithMaximumOutputBytes:(NSUInteger)maximumOutputBytes
                                    output:(void (^)(NSData *))output
                                    exited:(void (^)(int))exited
                                    failed:(void (^)(NSError *))failed {
    if ((self = [super init])) {
        _maximumOutputBytes = MAX(1, maximumOutputBytes);
        _pendingOutput = [NSMutableData data];
        _delivery = dispatch_queue_create("com.familiar.ish.terminal", DISPATCH_QUEUE_SERIAL);
        _output = [output copy]; _exited = [exited copy]; _failed = [failed copy];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processExited:)
            name:ISHProcessExitedNotification object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)attachTTY:(struct tty *)tty { @synchronized(self) { _tty = tty; } }
- (int)deliverBytes:(const void *)bytes length:(size_t)length {
    @synchronized(self) {
        if (_completed || _outputLimited) return (int)length;
        NSUInteger accepted = MIN(length, _maximumOutputBytes - _outputBytes);
        _outputBytes += accepted;
        if (accepted) {
            [_pendingOutput appendBytes:bytes length:accepted];
            if (!_deliveryScheduled) {
                _deliveryScheduled = YES;
                dispatch_async(_delivery, ^{ [self flushOutput]; });
            }
        }
        if (accepted < length) {
            _outputLimited = YES;
            dispatch_async(_delivery, ^{
                self.failed([NSError errorWithDomain:@"FamiliarISHTerminal" code:1
                    userInfo:@{NSLocalizedDescriptionKey: @"Terminal output exceeded its session limit."}]);
            });
        }
    }
    return (int)length;
}
- (void)flushOutput {
    NSData *data;
    @synchronized(self) {
        data = [_pendingOutput copy];
        [_pendingOutput setLength:0];
        _deliveryScheduled = NO;
    }
    if (data.length) self.output(data);
}
- (void)processExited:(NSNotification *)notification {
    if ([notification.userInfo[@"pid"] intValue] != self.pid || self.pid <= 1) return;
    @synchronized(self) {
        if (_completed) return;
        _completed = YES;
        // A queued quota failure owns the terminal result; its later process
        // exit must never race it into a false successful completion.
        if (_outputLimited) return;
        int code = [notification.userInfo[@"code"] intValue];
        dispatch_async(_delivery, ^{ self.exited(code); });
    }
}
- (int)startShellCommand:(NSString *)command columns:(NSUInteger)columns rows:(NSUInteger)rows {
    if (!ISHKernel.shared.isBooted || self.pid != 0 || command.length == 0) return -1;
    NSData *commandData = [command dataUsingEncoding:NSUTF8StringEncoding];
    if (!commandData || commandData.length > 16 * 1024 || memchr(commandData.bytes, 0, commandData.length)) return -1;
    struct task *saved = current;
    int error = become_new_init_child();
    if (error < 0) { current = saved; return error; }
    struct task *task = current;
    _executionOwner = familiar_ish_assign_execution_owner(task);
    self.pid = task->pid;
    startingSession = (__bridge void *)self;
    struct tty *tty = pty_open_fake(&terminal_driver);
    startingSession = NULL;
    if (IS_ERR(tty)) { current = saved; familiar_ish_discard_unstarted_task(task); return (int)PTR_ERR(tty); }
    NSString *path = [NSString stringWithFormat:@"/dev/pts/%d", tty->num];
    error = create_stdio(path.fileSystemRepresentation, TTY_PSEUDO_SLAVE_MAJOR, tty->num);
    lock(&ttys_lock); tty_release(tty); unlock(&ttys_lock);
    if (error < 0) { current = saved; familiar_ish_discard_unstarted_task(task); return error; }
    [self resizeColumns:columns rows:rows];
    NSMutableData *argv = [NSMutableData dataWithBytes:"/bin/sh\0-c\0" length:11];
    [argv appendData:commandData];
    [argv appendBytes:"\0\0" length:2];
    const char *environment = "TERM=xterm-256color\0LANG=C.UTF-8\0HOME=/root\0TMPDIR=/tmp\0"
        "PATH=/workspace/env/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\0"
        "PYTHONPATH=/workspace/env/site-packages\0PYTHONDONTWRITEBYTECODE=1\0\0";
    error = do_execve("/bin/sh", 3, argv.bytes, environment);
    if (error < 0) { current = saved; familiar_ish_discard_unstarted_task(task); return error; }
    task_start(task);
    current = saved;
    return self.pid;
}
- (struct tty *)retainedTTY {
    lock(&ttys_lock);
    struct tty *tty;
    @synchronized(self) { tty = _tty; }
    if (tty) { lock(&tty->lock); tty->refcount++; unlock(&tty->lock); }
    unlock(&ttys_lock);
    return tty;
}
- (NSInteger)sendInput:(NSData *)data {
    struct tty *tty = [self retainedTTY];
    if (!tty) return -1;
    ssize_t accepted = tty_input(tty, data.bytes, data.length, false);
    lock(&ttys_lock); tty_release(tty); unlock(&ttys_lock);
    return accepted;
}
- (BOOL)resizeColumns:(NSUInteger)columns rows:(NSUInteger)rows {
    if (columns < 2 || columns > 500 || rows < 2 || rows > 300) return NO;
    struct tty *tty = [self retainedTTY];
    if (!tty) return NO;
    lock(&tty->lock);
    tty_set_winsize(tty, (struct winsize_){.col = (unsigned short)columns, .row = (unsigned short)rows});
    unlock(&tty->lock);
    lock(&ttys_lock); tty_release(tty); unlock(&ttys_lock);
    return YES;
}
- (void)interrupt { [self sendInput:[NSData dataWithBytes:"\003" length:1]]; }
- (BOOL)close {
    int pid = self.pid;
    if (pid <= 1) return YES;
    return [ISHShellExecutor terminateExecutionOwner:_executionOwner timeout:5];
}
@end
