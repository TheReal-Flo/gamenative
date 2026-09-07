/* Exercise actual runtime locks and snapshot helpers on Windows. */
#include "../../app/src/main/windows/openxr_runtime/gamenative_openxr_runtime.c"
GN_IMPORT void* GN_STDCALL CreateThread(void*, gn_size, gn_ulong (GN_STDCALL *)(void*), void*, gn_ulong, gn_ulong*);
GN_IMPORT gn_ulong GN_STDCALL WaitForSingleObject(void*, gn_ulong);
GN_IMPORT void GN_STDCALL ExitProcess(unsigned int code);
/* The real Wine dispatcher is unavailable on native Windows. These tests never
 * call the transport; satisfy its import slot without pretending to emulate it. */
#ifdef _WIN64
void* test_unused_dispatcher __asm__("__imp___wine_unix_call_dispatcher") = 0;
#else
void* test_unused_dispatcher __asm__("__imp____wine_unix_call_dispatcher") = 0;
#endif
static struct gn_frame_snapshot sample;
static char output[1024];
static gn_ulong GN_STDCALL read_cached(void* unused) {
    (void)unused;
    if (!gn_cached_line("views", 0, output, sizeof(output)) || output[0] != 'A') ExitProcess(10);
    return 0;
}
static gn_ulong GN_STDCALL contend(void* unused) {
    (void)unused;
    gn_lock_acquire();
    gn_lock_release();
    return 0;
}
static gn_ulong GN_STDCALL publish_many(void* unused) {
    (void)unused;
    for (int i = 0; i < 10000; ++i) {
        memset(sample.views, (i & 1) ? 'A' : 'B', sizeof(sample.views) - 1);
        gn_publish_snapshot(&sample);
    }
    return 0;
}
void test_main(void) {
    sample.valid = 1;
    memset(sample.views, 'A', sizeof(sample.views) - 1);
    gn_publish_snapshot(&sample);
    /* Cached reads finish even while a transport transaction owns its lock. */
    gn_lock_acquire();
    void* reader = CreateThread(0, 0, read_cached, 0, 0, 0);
    if (!reader || WaitForSingleObject(reader, 5000) != 0) ExitProcess(11);
    CloseHandle(reader);
    void* waiter = CreateThread(0, 0, contend, 0, 0, 0);
    if (!waiter || WaitForSingleObject(waiter, 100) != 258) ExitProcess(12);
    gn_lock_release();
    if (WaitForSingleObject(waiter, 5000) != 0) ExitProcess(13);
    CloseHandle(waiter);
    /* Concurrent publication cannot tear a copied line. */
    void* writer = CreateThread(0, 0, publish_many, 0, 0, 0);
    if (!writer) ExitProcess(14);
    for (int i = 0; i < 10000; ++i) {
        if (!gn_cached_line("views", 0, output, sizeof(output))) ExitProcess(15);
        for (int j = 1; j < 1023; ++j)
            if (output[j] != output[0]) ExitProcess(16);
        if (output[1023] != 0) ExitProcess(17);
    }
    if (WaitForSingleObject(writer, 5000) != 0) ExitProcess(18);
    CloseHandle(writer);
    gn_invalidate_snapshot();
    if (gn_cached_line("views", 0, output, sizeof(output))) ExitProcess(19);
    sample.valid = 0;
    gn_publish_snapshot(&sample);
    if (gn_cached_line("input", 1, output, sizeof(output))) ExitProcess(20);
    ExitProcess(0);
}
