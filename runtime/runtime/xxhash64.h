#pragma once
// XXH64, written from the published xxHash specification (doc/xxhash_spec.md in the xxHash
// project): the hash Dolphin names custom textures by, so that its texture packs can be
// matched (gx/texture_pack.cpp). Little-endian reads, as the specification defines them.
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace xxh64_detail {
constexpr uint64_t kP1 = 0x9E3779B185EBCA87ull, kP2 = 0xC2B2AE3D27D4EB4Full, kP3 = 0x165667B19E3779F9ull,
                   kP4 = 0x85EBCA77C2B2AE63ull, kP5 = 0x27D4EB2F165667C5ull;
inline uint64_t rotl(uint64_t x, int r) { return (x << r) | (x >> (64 - r)); }
inline uint64_t read64(const uint8_t* p) {
    uint64_t v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | p[i];
    return v;
}
inline uint32_t read32(const uint8_t* p) {
    return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
}
inline uint64_t round(uint64_t acc, uint64_t lane) { acc += lane * kP2; acc = rotl(acc, 31); return acc * kP1; }
inline uint64_t merge(uint64_t acc, uint64_t v) { acc ^= round(0, v); return acc * kP1 + kP4; }
}  // namespace xxh64_detail

inline uint64_t xxh64(const void* data, size_t len, uint64_t seed) {
    using namespace xxh64_detail;
    const uint8_t* p = static_cast<const uint8_t*>(data);
    const uint8_t* end = p + len;
    uint64_t h;
    if (len >= 32) {
        uint64_t v1 = seed + kP1 + kP2, v2 = seed + kP2, v3 = seed, v4 = seed - kP1;
        do {
            v1 = round(v1, read64(p)); v2 = round(v2, read64(p + 8));
            v3 = round(v3, read64(p + 16)); v4 = round(v4, read64(p + 24));
            p += 32;
        } while (p + 32 <= end);
        h = rotl(v1, 1) + rotl(v2, 7) + rotl(v3, 12) + rotl(v4, 18);
        h = merge(h, v1); h = merge(h, v2); h = merge(h, v3); h = merge(h, v4);
    } else {
        h = seed + kP5;
    }
    h += static_cast<uint64_t>(len);
    for (; p + 8 <= end; p += 8) { h ^= round(0, read64(p)); h = rotl(h, 27) * kP1 + kP4; }
    if (p + 4 <= end) { h ^= static_cast<uint64_t>(read32(p)) * kP1; h = rotl(h, 23) * kP2 + kP3; p += 4; }
    for (; p < end; p++) { h ^= static_cast<uint64_t>(*p) * kP5; h = rotl(h, 11) * kP1; }
    h ^= h >> 33; h *= kP2; h ^= h >> 29; h *= kP3; h ^= h >> 32;
    return h;
}
