// Whether a word read out of guest memory can be the guest pointer it is meant to be.
//
// Diagnostics only: nothing here changes what the guest sees, and nothing here is a repair.
// It exists because the saved current-thread crash reported one number -- an address of
// 3F0002C8 -- and that number alone says what went wrong: the SDK loaded the current-thread
// pointer from 800000E4 and touched thread+2C8, so the pointer word held 3F000000, which is
// the IEEE-754 encoding of 0.5f. A 32-bit float was stored over a pointer. Naming that at
// the moment the word changes turns the next capture into evidence; guessing a guard around
// the failing access would only hide it.
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

// Main memory as the guest addresses it: 32 MiB from 80000000, word aligned. The mirrors at
// 0, 4 and C are not where a thread structure lives, so they are not pointers here.
inline bool gcn_word_is_guest_pointer(uint32_t v) {
    return v >= 0x80000000u && v < 0x81800000u && (v & 3u) == 0;
}

// The float a word encodes, when it encodes a finite one. Every 32-bit pattern decodes, so
// the caller decides whether the value is meaningful; a pointer word is not.
inline bool gcn_word_as_float(uint32_t v, float* out) {
    const uint32_t exponent = (v >> 23) & 0xFF;
    if (exponent == 0xFF) return false;  // infinity or NaN, not a stored value
    union {
        uint32_t bits;
        float value;
    } decode;
    decode.bits = v;
    *out = decode.value;
    return true;
}

// Why a word cannot be the pointer it should be, written into out. Returns out, or null when
// the word is a plausible guest pointer and there is nothing to say.
inline const char* gcn_word_pointer_note(uint32_t v, char* out, size_t size) {
    if (!out || size == 0) return nullptr;
    if (gcn_word_is_guest_pointer(v)) return nullptr;
    if (v == 0) {
        snprintf(out, size, "00000000 is a null pointer");
        return out;
    }
    float f = 0;
    if (gcn_word_as_float(v, &f)) {
        snprintf(out, size, "%08X is not a guest pointer; it is the float %g", v, (double)f);
        return out;
    }
    snprintf(out, size, "%08X is not a guest pointer", v);
    return out;
}
