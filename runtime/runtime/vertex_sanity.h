// Whether a transformed vertex is a position the hardware could draw.
//
// Diagnostics only: nothing here changes what the guest sees. It exists because a vertex
// whose position is not finite is not a slightly wrong vertex. No clamp or projection
// recovers it, the primitive it belongs to is discarded, and a draw made of them collapses
// to nothing on screen -- which is one shape the reported first-boss disappearance can take
// and is invisible in a log that only counts vertices. Counting them turns "the boss was
// not there" into the frame and draw that lost it, and separates a bad position matrix
// (the transform's input) from a good matrix and bad vertices (the data or the arithmetic).
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// A finite 32-bit float. Every bit pattern decodes to something, but an exponent of all
// ones is an infinity or a NaN, and neither is a position.
inline bool gcn_float_is_finite(float f) {
    uint32_t bits = 0;
    static_assert(sizeof(bits) == sizeof(f), "float is not 32 bits");
    memcpy(&bits, &f, sizeof bits);
    return ((bits >> 23) & 0xFFu) != 0xFFu;
}

// How many of a draw's positions are not finite. base points at the first vertex's x,
// stride_floats is the distance to the next vertex in floats.
inline uint32_t gcn_count_non_finite_positions(const float* base, size_t stride_floats, size_t count) {
    uint32_t bad = 0;
    if (!base || stride_floats < 3) return 0;
    for (size_t i = 0; i < count; i++) {
        const float* p = base + i * stride_floats;
        if (!gcn_float_is_finite(p[0]) || !gcn_float_is_finite(p[1]) || !gcn_float_is_finite(p[2])) bad++;
    }
    return bad;
}

// Whether the matrix that produced those positions was already unusable.
inline bool gcn_matrix_has_non_finite(const float* m, size_t count) {
    if (!m) return false;
    for (size_t i = 0; i < count; i++)
        if (!gcn_float_is_finite(m[i])) return true;
    return false;
}

// The line a capture needs. Returns out, or null when the draw is entirely finite and
// there is nothing to say.
inline const char* gcn_vertex_check_note(uint32_t verts, uint32_t bad, bool matrix_bad, char* out, size_t size) {
    if (!out || size == 0 || bad == 0) return nullptr;
    const char* cause = matrix_bad
        ? "its position matrix is not finite, so the transform's own input was already bad"
        : "its position matrix is finite, so the vertices or the arithmetic produced them";
    if (bad >= verts)
        snprintf(out, size, "all %u positions are not finite; %s", verts, cause);
    else
        snprintf(out, size, "%u of %u positions are not finite; %s", bad, verts, cause);
    return out;
}
