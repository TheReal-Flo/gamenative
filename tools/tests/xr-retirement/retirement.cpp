// Host test: actual transport code with reference-counted Android buffer doubles.
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#define private public
#include "../../../app/src/main/cpp/xrimmersive/xr_windows_transport.h"
#undef private
#include <cassert>
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>
#include <cstdio>
using namespace xrimmersive::windowsvr;
int liveBuffers = 0;
static AHardwareBuffer* buffer() { ++liveBuffers; return new AHardwareBuffer{1}; }
static void drain(WindowsFrameTransport& t) {
    for (const auto& entry : t.takeRetired()) t.finishRetirement(entry);
}
int main() {
    WindowsFrameTransport t;
    int sockets[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    for (int cycle = 0; cycle < 100; ++cycle) {
        t.storeEyeBuffer(0, buffer(), 32, 32, 0, false);
        t.storeEyeBuffer(1, buffer(), 32, 32, 0, false);
        t.latest_[0] = t.buffers_[0][0];
        t.latest_[1] = t.buffers_[1][0];
        const auto old = t.pollEye(0);
        assert(t.hasStereoContent());
        assert(t.handleUnregisterLine(sockets[0], "UNREGISTER first=0 count=4"));
        char reply[64];
        assert(read(sockets[1], reply, sizeof(reply)) > 0);
        assert(!t.hasStereoContent());
        auto retired = t.takeRetired();
        assert(retired.size() == 2);
        assert(liveBuffers == 2); // Unregister cannot release the backing prematurely.
        t.storeEyeBuffer(0, buffer(), 32, 32, 0, false);
        const auto replacement = t.buffers_[0][0].registrationSerial;
        assert(replacement != old.registrationSerial);
        t.releasePending_[0][0] = true;
        int fence = dup(sockets[0]);
        t.publishReleaseFence(0, 0, old.registrationSerial, fence);
        assert(fcntl(fence, F_GETFD) == -1);
        assert(t.releasePending_[0][0]);
        t.discardFrame(0, 0, old.serial, old.registrationSerial);
        assert(t.releasePending_[0][0]);
        for (const auto& entry : retired) t.finishRetirement(entry);
        assert(liveBuffers == 1);
        assert(t.buffers_[0][0].registrationSerial == replacement);
        t.releaseEye(0); // Disconnect retires every slot, including unused ones.
        t.releaseEye(1);
        drain(t);
        assert(liveBuffers == 0);
        assert(t.takeRetired().empty());
    }
    // FD-backed registrations also retain ownership until retirement completes.
    EyeFrame dma;
    dma.kind = BufferKind::DmaBuf;
    dma.imageIndex = 7;
    dma.planeCount = 1;
    dma.dmabufFds[0] = dup(sockets[0]);
    int ownedFd = dma.dmabufFds[0];
    t.storeEyeDmabuf(0, dma);
    t.releaseEye(0);
    assert(fcntl(ownedFd, F_GETFD) >= 0);
    drain(t);
    assert(fcntl(ownedFd, F_GETFD) == -1);
    // Invalid ranges must not mutate the registry.
    t.storeEyeBuffer(0, buffer(), 32, 32, 127, false);
    assert(t.handleUnregisterLine(sockets[0], "UNREGISTER first=127 count=2"));
    char reply[64];
    assert(read(sockets[1], reply, sizeof(reply)) > 0);
    assert(t.buffers_[0][127].kind == BufferKind::HardwareBuffer);
    t.stop();
    drain(t);
    assert(liveBuffers == 0);
    close(sockets[0]);
    close(sockets[1]);
    puts("Retirement lifecycle tests passed");
}
