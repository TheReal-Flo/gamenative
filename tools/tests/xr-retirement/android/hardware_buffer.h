#pragma once
#include <cstdint>
struct AHardwareBuffer { int refs; };
extern int liveBuffers;
inline void AHardwareBuffer_acquire(AHardwareBuffer* b) { ++b->refs; }
inline void AHardwareBuffer_release(AHardwareBuffer* b) {
    if (--b->refs == 0) { --liveBuffers; delete b; }
}
inline int AHardwareBuffer_recvHandleFromUnixSocket(int, AHardwareBuffer**) { return -1; }
