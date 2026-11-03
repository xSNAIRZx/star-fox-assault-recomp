// The guest's own call chain, read out of guest memory.
//
// The PowerPC ABI keeps the caller's frame pointer at [sp] and its return address at
// [sp+4], so a saved r1 walks the chain with nothing but guest reads -- no instrumentation
// in the recompiled code at all. Both diagnostics that watch a word need it: a guard or
// store line says only where in the *runtime* the change was noticed, and the chain says
// which game code was live at that point, which is what narrows a search for a writer.
//
// Diagnostics only. Nothing here writes, and nothing here changes guest behavior.
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

// A word read from guest memory. False when the address cannot be read.
using GcnWordReader = bool (*)(void* ctx, uint32_t ea, uint32_t* out);

// Where a frame pointer can be: main memory, as the guest addresses it. The mirrors at 0, 4
// and C hold the same bytes but are not where a stack lives.
inline bool gcn_guest_ram_holds(uint32_t ea) { return ea >= 0x80000000u && ea < 0x81800000u; }

// Fills frames with up to max return addresses, innermost first, and returns how many were
// stored. The walk stops at the first thing that is not a frame: a pointer outside main
// memory, a pointer that does not move up the stack (which also ends a cycle), or an
// unreadable word. Depth is bounded by the caller's limit, defaulting to the 24 the
// sampler uses.
inline size_t gcn_walk_guest_stack(uint32_t sp, GcnWordReader read, void* ctx, uint32_t* frames, size_t max,
                                   size_t depth_limit = 24) {
    size_t stored = 0;
    if (!read || !frames || max == 0) return 0;
    for (size_t d = 0; d < depth_limit && gcn_guest_ram_holds(sp); d++) {
        uint32_t prev = 0;
        if (!read(ctx, sp, &prev)) break;
        if (!gcn_guest_ram_holds(prev) || prev <= sp) break;
        uint32_t ret = 0;
        if (!read(ctx, prev + 4, &ret)) break;
        if (stored < max) frames[stored++] = ret;
        sp = prev;
    }
    return stored;
}

// The chain as one line of addresses, for the guard and store lines. Returns out, or null
// when there is nothing to print.
inline const char* gcn_stack_text(const uint32_t* frames, size_t count, char* out, size_t size) {
    if (!out || size == 0) return nullptr;
    size_t used = 0;
    out[0] = '\0';
    for (size_t i = 0; i < count; i++) {
        const int n = snprintf(out + used, size - used, "%s%08X", i ? " " : "", frames[i]);
        if (n < 0 || (size_t)n >= size - used) break;
        used += (size_t)n;
    }
    return used ? out : nullptr;
}
