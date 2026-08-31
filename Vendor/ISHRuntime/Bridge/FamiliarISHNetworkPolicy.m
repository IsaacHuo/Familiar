#import "FamiliarISHNetworkPolicy.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netdb.h>
#include <os/lock.h>
#include <resolv.h>
#include <stdatomic.h>

static atomic_bool gEnabled;
static atomic_ullong gMaximumConcurrent;
static atomic_ullong gMaximumTotal;
static atomic_ullong gMaximumReceived;
static atomic_ullong gMaximumSent;
static atomic_ullong gOpened;
static atomic_ullong gActive;
static atomic_ullong gPeak;
static atomic_ullong gReceived;
static atomic_ullong gSent;
static os_unfair_lock gDNSLock = OS_UNFAIR_LOCK_INIT;
static struct sockaddr_storage gDNSServers[8];
static size_t gDNSServerCount;

void familiar_ish_network_refresh_dns_servers(void) {
    struct __res_state resolver;
    struct sockaddr_storage values[8] = {0};
    size_t count = 0;
    if (res_ninit(&resolver) == EXIT_SUCCESS) {
        union res_sockaddr_union servers[8];
        int found = res_getservers(&resolver, servers, 8);
        for (int index = 0; index < found && count < 8; index++) {
            struct sockaddr *address = (struct sockaddr *)&servers[index].sin;
            socklen_t length = address->sa_len;
            if (length == 0 || length > sizeof(struct sockaddr_storage)) continue;
            memcpy(&values[count], address, length);
            count += 1;
        }
        res_nclose(&resolver);
    }
    os_unfair_lock_lock(&gDNSLock);
    memcpy(gDNSServers, values, sizeof(values));
    gDNSServerCount = count;
    os_unfair_lock_unlock(&gDNSLock);
}

size_t familiar_ish_network_copy_dns_servers(
    struct sockaddr_storage *servers,
    size_t capacity
) {
    os_unfair_lock_lock(&gDNSLock);
    size_t count = MIN(gDNSServerCount, capacity);
    if (servers != NULL && count > 0) {
        memcpy(servers, gDNSServers, count * sizeof(struct sockaddr_storage));
    }
    os_unfair_lock_unlock(&gDNSLock);
    return count;
}

static bool FamiliarISHIsAllowedDNS(const struct sockaddr *address, socklen_t length) {
    if (address == NULL) return false;
    uint16_t port = 0;
    if (address->sa_family == AF_INET && length >= sizeof(struct sockaddr_in)) {
        port = ntohs(((const struct sockaddr_in *)address)->sin_port);
    } else if (address->sa_family == AF_INET6 && length >= sizeof(struct sockaddr_in6)) {
        port = ntohs(((const struct sockaddr_in6 *)address)->sin6_port);
    }
    if (port != 53) return false;

    bool matches = false;
    os_unfair_lock_lock(&gDNSLock);
    for (size_t index = 0; index < gDNSServerCount && !matches; index++) {
        const struct sockaddr *candidate = (const struct sockaddr *)&gDNSServers[index];
        if (candidate->sa_family != address->sa_family) continue;
        if (address->sa_family == AF_INET) {
            matches = ((const struct sockaddr_in *)candidate)->sin_addr.s_addr
                == ((const struct sockaddr_in *)address)->sin_addr.s_addr;
        } else if (address->sa_family == AF_INET6) {
            matches = memcmp(
                &((const struct sockaddr_in6 *)candidate)->sin6_addr,
                &((const struct sockaddr_in6 *)address)->sin6_addr,
                sizeof(struct in6_addr)
            ) == 0;
        }
    }
    os_unfair_lock_unlock(&gDNSLock);
    return matches;
}

static bool FamiliarISHIsPrivateIPv4(uint32_t networkAddress) {
    uint32_t value = ntohl(networkAddress);
    return (value >> 24) == 10
        || (value >> 24) == 127
        || (value >> 16) == 0xA9FE
        || (value >> 20) == 0xAC1
        || (value >> 16) == 0xC0A8
        || (value >> 28) == 0xE
        || value == 0;
}

static bool FamiliarISHIsPrivateIPv6(const struct in6_addr *address) {
    const uint8_t *bytes = address->s6_addr;
    static const uint8_t unspecified[16] = {0};
    static const uint8_t loopback[16] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1};
    if (memcmp(bytes, unspecified, sizeof(unspecified)) == 0
        || memcmp(bytes, loopback, sizeof(loopback)) == 0
        || (bytes[0] & 0xFE) == 0xFC
        || (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80)
        || bytes[0] == 0xFF) {
        return true;
    }
    if (IN6_IS_ADDR_V4MAPPED(address)) {
        uint32_t mappedAddress;
        memcpy(&mappedAddress, bytes + 12, sizeof(mappedAddress));
        return FamiliarISHIsPrivateIPv4(mappedAddress);
    }
    return false;
}

void familiar_ish_network_configure(
    bool enabled,
    uint64_t maximumConcurrentConnections,
    uint64_t maximumTotalConnections,
    uint64_t maximumBytesReceived,
    uint64_t maximumBytesSent
) {
    familiar_ish_network_refresh_dns_servers();
    atomic_store(&gEnabled, enabled);
    atomic_store(&gMaximumConcurrent, maximumConcurrentConnections);
    atomic_store(&gMaximumTotal, maximumTotalConnections);
    atomic_store(&gMaximumReceived, maximumBytesReceived);
    atomic_store(&gMaximumSent, maximumBytesSent);
    atomic_store(&gOpened, 0);
    atomic_store(&gActive, 0);
    atomic_store(&gPeak, 0);
    atomic_store(&gReceived, 0);
    atomic_store(&gSent, 0);
}

bool familiar_ish_network_allow_socket(int guestDomain) {
    if (guestDomain != 2 && guestDomain != 10) {
        return true;
    }
    if (!atomic_load(&gEnabled)) {
        return false;
    }
    return atomic_load(&gOpened) < atomic_load(&gMaximumTotal)
        && atomic_load(&gActive) < atomic_load(&gMaximumConcurrent);
}

bool familiar_ish_network_allow_connect(const struct sockaddr *address, socklen_t length) {
    if (address == NULL) {
        return false;
    }
    if (address->sa_family == AF_UNIX) {
        return true;
    }
    if (!atomic_load(&gEnabled)) {
        return false;
    }
    if (FamiliarISHIsAllowedDNS(address, length)) {
        return true;
    }
    if (address->sa_family == AF_INET && length >= sizeof(struct sockaddr_in)) {
        return !FamiliarISHIsPrivateIPv4(((const struct sockaddr_in *)address)->sin_addr.s_addr);
    }
    if (address->sa_family == AF_INET6 && length >= sizeof(struct sockaddr_in6)) {
        return !FamiliarISHIsPrivateIPv6(&((const struct sockaddr_in6 *)address)->sin6_addr);
    }
    return false;
}

bool familiar_ish_network_allow_listen(int guestDomain) {
    return guestDomain != 2 && guestDomain != 10;
}

void familiar_ish_network_socket_opened(int guestDomain) {
    if (guestDomain != 2 && guestDomain != 10) {
        return;
    }
    uint64_t opened = atomic_fetch_add(&gOpened, 1) + 1;
    (void)opened;
    uint64_t active = atomic_fetch_add(&gActive, 1) + 1;
    uint64_t peak = atomic_load(&gPeak);
    while (active > peak && !atomic_compare_exchange_weak(&gPeak, &peak, active)) {}
}

void familiar_ish_network_socket_closed(int guestDomain) {
    if (guestDomain == 2 || guestDomain == 10) {
        uint64_t current = atomic_load(&gActive);
        while (current > 0 && !atomic_compare_exchange_weak(&gActive, &current, current - 1)) {}
    }
}

bool familiar_ish_network_record_receive(uint64_t count) {
    return atomic_fetch_add(&gReceived, count) + count <= atomic_load(&gMaximumReceived);
}

bool familiar_ish_network_record_send(uint64_t count) {
    return atomic_fetch_add(&gSent, count) + count <= atomic_load(&gMaximumSent);
}

FamiliarISHNetworkCounters familiar_ish_network_counters(void) {
    return (FamiliarISHNetworkCounters) {
        .openedConnections = atomic_load(&gOpened),
        .activeConnections = atomic_load(&gActive),
        .peakConcurrentConnections = atomic_load(&gPeak),
        .bytesReceived = atomic_load(&gReceived),
        .bytesSent = atomic_load(&gSent),
    };
}

@implementation FamiliarISHNetworkController
+ (void)configureEnabled:(BOOL)enabled
    maximumConcurrentConnections:(NSUInteger)maximumConcurrentConnections
         maximumTotalConnections:(NSUInteger)maximumTotalConnections
          maximumBytesReceived:(uint64_t)maximumBytesReceived
              maximumBytesSent:(uint64_t)maximumBytesSent {
    familiar_ish_network_configure(
        enabled,
        maximumConcurrentConnections,
        maximumTotalConnections,
        maximumBytesReceived,
        maximumBytesSent
    );
}

+ (FamiliarISHNetworkCounters)counters {
    return familiar_ish_network_counters();
}
@end
