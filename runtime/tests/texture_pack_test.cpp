// Texture packs: XXH64 against published values, Dolphin's texture names, and a replacement
// read from a PNG and attached to a decoded texture (gx/texture_pack.h, png_read.cpp).
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

#include "../runtime/xxhash64.h"
#include "../runtime/gx/render.h"
#include "../runtime/gx/texture_pack.h"

bool write_png(const char* path, const uint8_t* rgba, int w, int h);
bool read_png(const char* path, uint32_t max_edge, std::vector<uint32_t>& rgba, uint32_t& w, uint32_t& h, std::string& why);

static int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); g_failures++; } } while (0)

int main() {
    // The xxHash specification's empty input, and python-xxhash's documented examples.
    CHECK(xxh64("", 0, 0) == 0xEF46DB3751D8E999ull);
    const char* spam = "Nobody inspects the spammish repetition";  // 39 bytes: stripes, 8-, 4- and 1-byte tails
    CHECK(xxh64(spam, strlen(spam), 0) == 0xFBCEA83C8A378BF1ull);
    CHECK(xxh64("xxhash", 6, 0) == 0x32DD38952C4BC720ull);

    // Dolphin's names. An 8x4 I8 texture (format 1): no palette.
    std::vector<uint8_t> texels(32);
    for (size_t i = 0; i < texels.size(); i++) texels[i] = static_cast<uint8_t>(i * 7);
    gx::TexSource src;
    src.texels = texels.data(); src.base_bytes = 32; src.fmt = 1; src.width = 8; src.height = 4;
    char expect[96];
    snprintf(expect, sizeof(expect), "tex1_8x4_%016llx_1", static_cast<unsigned long long>(xxh64(texels.data(), 32, 0)));
    CHECK(gx::dolphin_texture_name(src, false) == expect);
    snprintf(expect, sizeof(expect), "tex1_8x4_m_%016llx_1", static_cast<unsigned long long>(xxh64(texels.data(), 32, 0)));
    CHECK(gx::dolphin_texture_name(src, true) == expect);
    CHECK(gx::dolphin_texture_name(src, false, 2) == "tex1_8x4_$_1");

    // CI4 (format 8): indices 3..9 used, so the palette hash covers entries 3 to 9.
    std::vector<uint8_t> ci4(32, 0x33);
    ci4[5] = 0x93;  // index 9 high, 3 low
    std::vector<uint8_t> tlut(32);
    for (size_t i = 0; i < tlut.size(); i++) tlut[i] = static_cast<uint8_t>(0xA0 + i);
    gx::TexSource pal = src;
    pal.texels = ci4.data(); pal.fmt = 8; pal.tlut = tlut.data(); pal.tlut_bytes = 32;
    snprintf(expect, sizeof(expect), "tex1_8x4_%016llx_%016llx_8", static_cast<unsigned long long>(xxh64(ci4.data(), 32, 0)),
             static_cast<unsigned long long>(xxh64(tlut.data() + 6, 14, 0)));
    CHECK(gx::dolphin_texture_name(pal, false) == expect);
    snprintf(expect, sizeof(expect), "tex1_8x4_%016llx_$_8", static_cast<unsigned long long>(xxh64(ci4.data(), 32, 0)));
    CHECK(gx::dolphin_texture_name(pal, false, 1) == expect);

    // A replacement found by Dolphin's name, at 3x (not a power of two), and one by our hash.
    const std::filesystem::path dir = std::filesystem::temp_directory_path() / "gcn_texture_pack_test";
    std::filesystem::remove_all(dir);
    std::filesystem::create_directories(dir / "sub");
    gx::TexData t;
    t.id = 1; t.width = 8; t.height = 4; t.hash = 0x0123456789ABCDEFull;
    t.levels.push_back(std::vector<uint32_t>(32, 0xFF0000FFu));
    t.levels.push_back(std::vector<uint32_t>(8, 0xFF0000FFu));
    std::vector<uint32_t> big(24 * 12, 0xFF00FF00u);
    const std::string dolphin_file = gx::dolphin_texture_name(src, true) + ".png";
    CHECK(write_png((dir / "sub" / dolphin_file).string().c_str(), reinterpret_cast<const uint8_t*>(big.data()), 24, 12));
    std::vector<uint32_t> back; uint32_t bw = 0, bh = 0; std::string why;
    CHECK(read_png((dir / "sub" / dolphin_file).string().c_str(), 8192, back, bw, bh, why) && bw == 24 && bh == 12 && back == big);
    gx::texture_pack_set_dir(dir.string().c_str());
    gx::texture_pack_apply(t, false, &src);
    CHECK(t.hd != nullptr);
    if (t.hd) {
        CHECK(t.hd->width == 24 && t.hd->height == 12);
        CHECK(t.hd->shift > 1.5f && t.hd->shift < 1.6f);  // log2(3)
        CHECK(t.hd->levels.size() == 4);                   // 24x12, 12x6, 6x3, 3x1: two extra, then the game's two
        CHECK(t.hd->levels[0][0] == 0xFF00FF00u);
    }
    // A wrong shape is refused, and the texture keeps its own texels.
    gx::TexData other = t; other.hd.reset(); other.hash = 0x1111111111111111ull;
    std::vector<uint32_t> odd(20 * 4, 0xFFFFFFFFu);
    CHECK(write_png((dir / "1111111111111111.png").string().c_str(), reinterpret_cast<const uint8_t*>(odd.data()), 20, 4));
    gx::texture_pack_set_dir(dir.string().c_str());
    gx::texture_pack_apply(other, false, nullptr);
    CHECK(other.hd == nullptr);
    // DDS: a BC1 (DXT1) 8x8 with two mip levels (4 blocks, then 1), a DX10-header BC7 4x4, and
    // an uncompressed one, which is refused.
    auto write_dds = [&](const std::filesystem::path& path, uint32_t w, uint32_t h, uint32_t mips, uint32_t fourcc,
                         uint32_t dxgi, uint32_t data_bytes, uint32_t pf_flags) {
        std::vector<uint8_t> f(128 + (fourcc == 0x30315844 ? 20 : 0) + data_bytes, 0);
        auto put = [&](size_t o, uint32_t v) { for (int i = 0; i < 4; i++) f[o + i] = static_cast<uint8_t>(v >> (8 * i)); };
        memcpy(f.data(), "DDS ", 4);
        put(4, 124); put(12, h); put(16, w); put(28, mips); put(80, pf_flags); put(84, fourcc);
        if (fourcc == 0x30315844) put(128, dxgi);
        for (size_t i = f.size() - data_bytes; i < f.size(); i++) f[i] = static_cast<uint8_t>(i);
        FILE* o = fopen(path.string().c_str(), "wb");
        fwrite(f.data(), 1, f.size(), o);
        fclose(o);
    };
    std::filesystem::create_directories(dir);
    write_dds(dir / "a.dds", 8, 8, 2, 0x31545844, 0, 4 * 8 + 8, 0x4);
    uint32_t dw = 0, dh = 0, fmt = 0; std::vector<std::vector<uint8_t>> lv; std::string dwhy;
    CHECK(gx::read_dds((dir / "a.dds").string().c_str(), dw, dh, fmt, lv, dwhy));
    CHECK(dw == 8 && dh == 8 && fmt == gx::kTexBlockBC1 && lv.size() == 2 && lv[0].size() == 32 && lv[1].size() == 8);
    write_dds(dir / "b.dds", 4, 4, 1, 0x30315844, 98, 16, 0x4);
    CHECK(gx::read_dds((dir / "b.dds").string().c_str(), dw, dh, fmt, lv, dwhy));
    CHECK(fmt == gx::kTexBlockBC7 && lv.size() == 1 && lv[0].size() == 16);
    write_dds(dir / "c.dds", 4, 4, 1, 0, 0, 64, 0x41);
    CHECK(!gx::read_dds((dir / "c.dds").string().c_str(), dw, dh, fmt, lv, dwhy));
    // A DDS replacement by Dolphin's name: blocks kept as they are, its own levels.
    std::filesystem::remove_all(dir / "sub");
    std::filesystem::create_directories(dir / "sub");
    write_dds(dir / "sub" / (gx::dolphin_texture_name(src, true) + ".dds"), 32, 16, 2, 0x35545844, 0, 8 * 4 * 16 + 4 * 2 * 16, 0x4);
    std::filesystem::remove(dir / "1111111111111111.png");
    gx::texture_pack_set_dir(dir.string().c_str());
    gx::TexData d = t; d.hd.reset(); d.hash = 0x2222222222222222ull;
    gx::texture_pack_apply(d, false, &src);
    CHECK(d.hd && d.hd->block_format == gx::kTexBlockBC3 && d.hd->blocks.size() == 2 && d.hd->levels.empty());
    CHECK(d.hd && d.hd->shift > 1.99f && d.hd->shift < 2.01f);
    std::filesystem::remove_all(dir);

    if (g_failures) { fprintf(stderr, "%d failure(s)\n", g_failures); return 1; }
    printf("texture_pack_test: all passed\n");
    return 0;
}
