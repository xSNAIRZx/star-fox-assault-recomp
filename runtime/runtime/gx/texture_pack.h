#pragma once
#include <cstdint>
#include <memory>
#include <vector>

namespace gx {
struct TexData;

// Higher-resolution replacements for the textures a game decodes from its own memory, and the
// dump that makes them possible. A texture is named by its content hash (TexData::hash), the
// same in every run: `<16 hex digits>.png`, anywhere under the pack directory.
//
// A replacement must have the original's shape at 2, 4 or 8 times its size a side; anything
// else is refused and logged. The game and its shaders keep working in the original's size
// (texture coordinates are divided by it), so only the sampled detail changes. The renderer
// uploads the replacement's own mip chain, which reaches down to the original's smallest
// level: far away a surface looks as it did, close up it is sharper (render_gl.cpp,
// get_sampler). Copies of the framebuffer the game makes into a texture are never replaced.

// A replacement's mip chain, top level first, RGBA8 as TexData's levels. `shift` is how many
// levels it has above the original's top one: log2 of the scale.
struct TexHd {
    uint32_t width = 0, height = 0;
    uint32_t shift = 0;
    std::vector<std::vector<uint32_t>> levels;
};

// Before the game starts. Reads the directory's file names once; the images themselves are
// read when a texture that has one is first decoded.
void texture_pack_set_dir(const char* dir);
// Before the game starts. Writes each texture decoded from guest memory, once per hash, as
// <dir>/<hash>.png (its top level, with alpha), for making a pack.
void texture_pack_set_dump_dir(const char* dir);
// For a texture just decoded from guest memory: dumps it, and attaches its replacement if the
// pack has one. `streamed`: its memory keeps being rewritten (a movie frame, say), so it is
// not dumped -- each frame would be a new file. Front-end thread only.
void texture_pack_apply(TexData& t, bool streamed = false);
}  // namespace gx
