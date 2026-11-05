#pragma once
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace gx {
struct TexData;

// Higher-resolution replacements for the textures a game decodes from its own memory, and the
// dump that makes them possible. A texture is named by its content hash (TexData::hash), the
// same in every run: `<16 hex digits>.png`, anywhere under the pack directory. Dolphin's names
// (dolphin_texture_name) are matched too, so its texture packs load as they are, PNG or DDS
// (BC1, BC2, BC3 or BC7, uploaded compressed with the file's own mip levels).
//
// A replacement must have the original's shape at a larger size (a whole scale, 2x, 3x, 4x
// and so on); anything else is refused and logged. The game and its shaders keep working in the original's size
// (texture coordinates are divided by it), so only the sampled detail changes. The renderer
// uploads the replacement's own mip chain, which reaches down to the original's smallest
// level: far away a surface looks as it did, close up it is sharper (render_gl.cpp,
// get_sampler). Copies of the framebuffer the game makes into a texture are never replaced.

// A replacement's mip chain, top level first, RGBA8 as TexData's levels. `shift` is how many
// levels it has above the original's top one: log2 of the scale.
struct TexHd {
    uint32_t width = 0, height = 0;
    float shift = 0.0f;  // log2 of the scale; whole for 2x, 4x, 8x
    std::vector<std::vector<uint32_t>> levels;
    // A DDS replacement instead: block-compressed levels as the file holds them, uploaded as
    // they are (`levels` is then empty). `block_format` is the GL internal format (S3TC/BPTC);
    // a GL without it keeps the game's own texels.
    uint32_t block_format = 0;
    std::vector<std::vector<uint8_t>> blocks;
};
// The block-compressed formats a DDS replacement may use (GL enums).
enum : uint32_t {
    kTexBlockBC1 = 0x83F1,  // COMPRESSED_RGBA_S3TC_DXT1_EXT
    kTexBlockBC2 = 0x83F2,  // COMPRESSED_RGBA_S3TC_DXT3_EXT
    kTexBlockBC3 = 0x83F3,  // COMPRESSED_RGBA_S3TC_DXT5_EXT
    kTexBlockBC7 = 0x8E8C,  // COMPRESSED_RGBA_BPTC_UNORM
};
// Reads a DDS file of BC1, BC2, BC3 or BC7 blocks (DXT1/3/5 FourCC or a DX10 header): its
// size and every mip level it carries. Exposed for tests.
bool read_dds(const char* path, uint32_t& width, uint32_t& height, uint32_t& block_format,
              std::vector<std::vector<uint8_t>>& levels, std::string& why);

// A texture as it lies in guest memory, for Dolphin's names: its top level's bytes (whole
// format blocks), its GX format and size, and for an indexed format the palette in TMEM.
struct TexSource {
    const uint8_t* texels = nullptr;
    uint32_t base_bytes = 0;
    uint32_t fmt = 0, width = 0, height = 0;
    const uint8_t* tlut = nullptr;
    uint32_t tlut_bytes = 0;  // what the format can index: 32, 512 or 32768 bytes (or less, at TMEM's end)
};
// The name Dolphin gives a texture's custom replacement, without ".png":
// tex1_<w>x<h>[_m]_<texels hash>[_<palette hash>]_<format>, the hashes XXH64 (seed 0) of the
// top level's bytes and of the palette entries between the lowest and highest index the top
// level uses. `wildcard` 1 puts "$" for the palette hash and 2 for the texels hash: the two
// forms a pack may use to match every palette, or every texture with a palette.
std::string dolphin_texture_name(const TexSource& s, bool mipmapped, int wildcard = 0);

// Before the game starts. Reads the directory's file names once; the images themselves are
// read when a texture that has one is first decoded.
void texture_pack_set_dir(const char* dir);
// Before the game starts. Writes each texture decoded from guest memory, once per hash, as
// <dir>/<hash>.png (its top level, with alpha), for making a pack.
void texture_pack_set_dump_dir(const char* dir);
// For a texture just decoded from guest memory: dumps it, and attaches its replacement if the
// pack has one. `streamed`: its memory keeps being rewritten (a movie frame, say), so it is
// not dumped -- each frame would be a new file. Front-end thread only.
void texture_pack_apply(TexData& t, bool streamed = false, const TexSource* src = nullptr);
}  // namespace gx
