#pragma once

#include <cstdint>

namespace gx {

// SU_SSIZE/SU_TSIZE store manual coordinate ranges as size-minus-one. A zero
// register therefore means a one-texel range, which is how the game's glyph
// atlas submits pixel-space UVs. The host sampler still addresses normalized UVs.
constexpr float texcoord_scale(uint32_t su_size) noexcept {
    return static_cast<float>((su_size & 0xFFFFu) + 1u);
}

constexpr float normalized_texcoord(float uv, uint32_t su_size, float image_size) noexcept {
    return uv * texcoord_scale(su_size) / image_size;
}

}  // namespace gx
