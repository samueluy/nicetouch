#ifndef NICETOUCH_TRACKPAD_BRIDGE_H
#define NICETOUCH_TRACKPAD_BRIDGE_H
#include <stdint.h>
#include <stdbool.h>
typedef void (*NTFrameCallback)(uintptr_t device, const float *xs, const float *ys, int count, double time);
// Experimental, private API. Only built-in trackpads are accepted.
bool NTStart(NTFrameCallback callback);
void NTStop(void);
#endif
