// memset_pattern16 shim.
//
// Clang lowers 16-byte-pattern fills (aggregate init / pattern memset) inside
// the vendored FFmpeg static libs to a call to _memset_pattern16. That symbol
// lives in iOS libSystem, but the Theos iPhoneOS9.3 `.tbd` stubs used at link
// time do not export it, so the armv7 link fails with:
//   Undefined symbols: "_memset_pattern16" (libavformat/libavcodec/libswscale)
//
// Define it here so the symbol is satisfied by our own object file. Semantics
// match Apple's: fill [target, target+size) by repeating the 16-byte pattern.
// FFmpeg only hits this on small control structs, not per-frame paths, so the
// scalar loop is fine.

#include <stdint.h>
#include <string.h>

// size is in bytes, filled by repeating the pattern of 4/8/16 bytes.
// Signature matches the <string.h> declaration so the definitions below are
// not "conflicting types" against the SDK header.
static inline void oe_memset_pattern(void *target, const void *patternBuffer,
                                     size_t size, int patLen)
{
    uint8_t *dst = (uint8_t *)target;
    const uint8_t *pat = (const uint8_t *)patternBuffer;
    size_t i = 0;
    for (; i + (size_t)patLen <= size; i += (size_t)patLen)
        memcpy(dst + i, pat, (size_t)patLen);
    if (i < size)
        memcpy(dst + i, pat, size - i);
}

void memset_pattern16(void *target, const void *patternBuffer, size_t size)
{
    oe_memset_pattern(target, patternBuffer, size, 16);
}

void memset_pattern8(void *target, const void *patternBuffer, size_t size)
{
    oe_memset_pattern(target, patternBuffer, size, 8);
}

void memset_pattern4(void *target, const void *patternBuffer, size_t size)
{
    oe_memset_pattern(target, patternBuffer, size, 4);
}
