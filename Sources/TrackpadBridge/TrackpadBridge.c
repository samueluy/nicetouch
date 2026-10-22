#include "TrackpadBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stddef.h>
#include <math.h>
#include <stdatomic.h>

typedef struct { float x, y; } NTPoint;
typedef struct { NTPoint position, velocity; } NTVector;
// Reverse-engineered ABI. Apple can change this layout without notice.
typedef struct {
    int32_t frame; double time; int32_t path, state, finger, hand;
    NTVector normalized; float quality; int32_t field9; float angle, major, minor;
    NTVector absolute; int32_t field14, field15; float density;
} Touch;
_Static_assert(sizeof(Touch) == 96, "Unexpected touch ABI");
typedef void (*Frame)(void *, Touch *, int, double, int);
typedef void (*Register)(void *, Frame);
typedef int (*Start)(void *, int);
typedef int (*Stop)(void *);
typedef bool (*BuiltIn)(void *);
static void *library;
static CFArrayRef devices;
static Register unregisterFrame;
static Stop stopDevice;
// Capture callbacks run off-main; start/stop must not race the callback pointer.
static _Atomic(NTFrameCallback) receiver;
static void frame(void *device, Touch *touches, int count, double time, int number) {
    (void)number;
    float xs[16], ys[16]; int active = 0;
    if (count < 0 || count > 16 || (count > 0 && !touches)) return;
    for (int i = 0; i < count; i++) {
        if (touches[i].state != 3 && touches[i].state != 4) continue;
        float x = touches[i].normalized.position.x, y = touches[i].normalized.position.y;
        if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) return;
        xs[active] = x; ys[active++] = y;
    }
    NTFrameCallback deliver = atomic_load_explicit(&receiver, memory_order_acquire);
    if (deliver) deliver((uintptr_t)device, xs, ys, active, time);
}
bool NTStart(NTFrameCallback callback) {
    if (devices) return true;
    if (!library) library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LOCAL | RTLD_NOW);
    if (!library) return false;
    CFArrayRef (*create)(void) = dlsym(library, "MTDeviceCreateList");
    Register registerFrame = dlsym(library, "MTRegisterContactFrameCallback");
    unregisterFrame = dlsym(library, "MTUnregisterContactFrameCallback");
    Start start = dlsym(library, "MTDeviceStart");
    stopDevice = dlsym(library, "MTDeviceStop");
    BuiltIn builtIn = dlsym(library, "MTDeviceIsBuiltIn");
    bool (*isRunning)(void *) = dlsym(library, "MTDeviceIsRunning");
    if (!create || !registerFrame || !unregisterFrame || !start || !stopDevice || !builtIn || !isRunning) return false;
    CFArrayRef found = create();
    if (!found) return false;
    CFMutableArrayRef accepted = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    atomic_store_explicit(&receiver, callback, memory_order_release);
    for (CFIndex i = 0; i < CFArrayGetCount(found); i++) {
        void *device = (void *)CFArrayGetValueAtIndex(found, i);
        if (!builtIn(device)) continue;
        registerFrame(device, frame);
        start(device, 0);
        if (!isRunning(device)) { unregisterFrame(device, frame); continue; }
        CFArrayAppendValue(accepted, device);
    }
    CFRelease(found);
    if (!CFArrayGetCount(accepted)) { CFRelease(accepted); atomic_store_explicit(&receiver, NULL, memory_order_release); return false; }
    devices = accepted;
    return true;
}
void NTStop(void) {
    if (!devices) return;
    for (CFIndex i = 0; i < CFArrayGetCount(devices); i++) {
        void *device = (void *)CFArrayGetValueAtIndex(devices, i);
        stopDevice(device);
        unregisterFrame(device, frame);
    }
    CFRelease(devices); devices = NULL;
    // Library and callback remain alive for any in-flight callbacks. Swift gates delivery.
}
