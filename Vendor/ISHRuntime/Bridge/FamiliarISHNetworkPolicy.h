#include <stdbool.h>
#include <stdint.h>
#include <sys/socket.h>

typedef struct FamiliarISHNetworkCounters {
    uint64_t openedConnections;
    uint64_t activeConnections;
    uint64_t peakConcurrentConnections;
    uint64_t bytesReceived;
    uint64_t bytesSent;
} FamiliarISHNetworkCounters;

extern void familiar_ish_network_configure(
    bool enabled,
    uint64_t maximumConcurrentConnections,
    uint64_t maximumTotalConnections,
    uint64_t maximumBytesReceived,
    uint64_t maximumBytesSent
);
extern bool familiar_ish_network_allow_socket(int guestDomain);
extern bool familiar_ish_network_allow_connect(const struct sockaddr *address, socklen_t length);
extern bool familiar_ish_network_allow_listen(int guestDomain);
extern void familiar_ish_network_socket_opened(int guestDomain);
extern void familiar_ish_network_socket_closed(int guestDomain);
extern bool familiar_ish_network_record_receive(uint64_t count);
extern bool familiar_ish_network_record_send(uint64_t count);
extern FamiliarISHNetworkCounters familiar_ish_network_counters(void);

#ifdef __OBJC__
#import <Foundation/Foundation.h>
@interface FamiliarISHNetworkController : NSObject
+ (void)configureEnabled:(BOOL)enabled
    maximumConcurrentConnections:(NSUInteger)maximumConcurrentConnections
         maximumTotalConnections:(NSUInteger)maximumTotalConnections
          maximumBytesReceived:(uint64_t)maximumBytesReceived
              maximumBytesSent:(uint64_t)maximumBytesSent;
+ (FamiliarISHNetworkCounters)counters;
@end
#endif
