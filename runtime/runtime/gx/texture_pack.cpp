// See texture_pack.h.
#include "texture_pack.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <string>
#include <system_error>
#include <unordered_map>
#include <unordered_set>

#include "../xxhash64.h"
#include "render.h"

bool write_png(const char* path, const uint8_t* rgba, int w, int h);
bool read_png(const char* path, uint32_t max_edge, std::vector<uint32_t>& rgba, uint32_t& w, uint32_t& h, std::string& why);

namespace gx {
namespace {

std::unordered_map<uint64_t, std::filesystem::path> g_pack;        // our hash -> replacement
std::unordered_map<std::string, std::filesystem::path> g_dolphin;  // Dolphin's name -> replacement
std::filesystem::path g_dump_dir;
FILE* g_dump_names = nullptr;  // <dump>/dolphin-names.txt: our name, then Dolphin's
std::unordered_set<uint64_t> g_dumped;
// Decoded replacements still in use, so a texture the game drops and decodes again does not
// read and scale its image again. Entries expire with the last texture holding them.
std::unordered_map<std::string, std::weak_ptr<const TexHd>> g_loaded;
std::unordered_set<std::string> g_refused;  // logged once each

constexpr uint32_t kMaxEdge = 8192;

std::string lower(std::string s) {
    for (char& c : s) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
    return s;
}

bool parse_hash_name(const std::string& stem, uint64_t& hash) {
    if (stem.size() != 16) return false;
    for (char c : stem)
        if (!isxdigit(static_cast<unsigned char>(c))) return false;
    hash = std::stoull(stem, nullptr, 16);
    return true;
}

// Dolphin's file names: tex1_..., with "_arb" (mip levels drawn by hand, which are not read
// here: the chain is made from the top level) dropped; its own extra mip files ("_mipN") are
// skipped, as the chain is made here.
bool parse_dolphin_name(std::string stem, std::string& name) {
    stem = lower(stem);
    if (stem.rfind("tex1_", 0) != 0) return false;
    const size_t mip = stem.rfind("_mip");
    if (mip != std::string::npos && mip + 4 < stem.size() &&
        std::all_of(stem.begin() + static_cast<long>(mip) + 4, stem.end(), [](char c) { return isdigit(static_cast<unsigned char>(c)); }))
        return false;
    const size_t arb = stem.rfind("_arb");
    if (arb != std::string::npos) stem.erase(arb, 4);
    name = stem;
    return true;
}

std::string hex16(uint64_t v) {
    char b[17];
    snprintf(b, sizeof(b), "%016llx", static_cast<unsigned long long>(v));
    return b;
}

// Box-filters a level to half size, weighting colour by alpha so that the colour of a fully
// transparent texel (often black) does not bleed into the edges of what is visible.
std::vector<uint32_t> half(const std::vector<uint32_t>& src, uint32_t w, uint32_t h, uint32_t& nw, uint32_t& nh) {
    nw = w > 1 ? w / 2 : 1;
    nh = h > 1 ? h / 2 : 1;
    std::vector<uint32_t> out(static_cast<size_t>(nw) * nh);
    for (uint32_t y = 0; y < nh; y++)
        for (uint32_t x = 0; x < nw; x++) {
            uint32_t sum[4] = {}, alpha = 0, n = 0;
            for (uint32_t dy = 0; dy < 2; dy++)
                for (uint32_t dx = 0; dx < 2; dx++) {
                    const uint32_t sx = std::min(w - 1, x * 2 + dx), sy = std::min(h - 1, y * 2 + dy);
                    const uint32_t p = src[static_cast<size_t>(sy) * w + sx];
                    const uint32_t a = p >> 24;
                    for (int c = 0; c < 3; c++) sum[c] += ((p >> (8 * c)) & 0xFF) * (a + 1);
                    alpha += a + 1;
                    sum[3] += a;
                    n++;
                }
            uint32_t px = ((sum[3] + n / 2) / n) << 24;
            for (int c = 0; c < 3; c++) px |= ((sum[c] + alpha / 2) / alpha) << (8 * c);
            out[static_cast<size_t>(y) * nw + x] = px;
        }
    return out;
}

std::shared_ptr<const TexHd> load(const std::string& key, const std::filesystem::path& file, const TexData& t) {
    auto refuse = [&](const std::string& why) {
        if (g_refused.insert(key).second)
            fprintf(stderr, "[texture pack] %s refused: %s\n", file.filename().string().c_str(), why.c_str());
        return std::shared_ptr<const TexHd>();
    };
    auto hd = std::make_shared<TexHd>();
    std::vector<uint32_t> top;
    std::string why;
    if (!read_png(file.string().c_str(), kMaxEdge, top, hd->width, hd->height, why)) return refuse(why);
    const double sx = static_cast<double>(hd->width) / t.width, sy = static_cast<double>(hd->height) / t.height;
    const std::string shape = std::to_string(hd->width) + "x" + std::to_string(hd->height);
    if (sx < 1.5 || sy < 1.5)
        return refuse("is " + shape + ", not larger than the " + std::to_string(t.width) + "x" + std::to_string(t.height) + " original");
    if (std::fabs(sx - sy) > 0.02 * std::max(sx, sy))
        return refuse("is " + shape + ", not the " + std::to_string(t.width) + "x" + std::to_string(t.height) + " original's shape");
    hd->shift = static_cast<float>(std::log2(std::min(sx, sy)));
    // Levels down to about the original's smallest: the extra top ones, then one for each of
    // the game's own.
    const size_t want = static_cast<size_t>(std::ceil(hd->shift - 0.01f)) + std::max<size_t>(1, t.levels.size());
    uint32_t w = hd->width, h = hd->height;
    hd->levels.push_back(std::move(top));
    while (hd->levels.size() < want && (w > 1 || h > 1)) {
        uint32_t nw, nh;
        hd->levels.push_back(half(hd->levels.back(), w, h, nw, nh));
        w = nw; h = nh;
    }
    fprintf(stderr, "[texture pack] %s: %ux%u replaced at %ux%u\n", key.c_str(), t.width, t.height, hd->width, hd->height);
    return hd;
}

// The replacement for a texture, if the pack has one, and the name it was found by.
const std::filesystem::path* find_replacement(const TexData& t, const TexSource* src, std::string& key) {
    if (auto it = g_pack.find(t.hash); it != g_pack.end()) { key = hex16(t.hash); return &it->second; }
    if (g_dolphin.empty() || !src) return nullptr;
    // Whether the game samples the texture with mips is not known here (it is a sampler
    // setting, and the decode is shared), so both of Dolphin's spellings are tried, the more
    // likely first.
    const bool likely_mips = t.levels.size() > 1;
    for (bool mips : {likely_mips, !likely_mips})
        for (int wildcard = 0; wildcard < 3; wildcard++) {
            std::string name = dolphin_texture_name(*src, mips, wildcard);
            if (auto it = g_dolphin.find(name); it != g_dolphin.end()) { key = std::move(name); return &it->second; }
        }
    return nullptr;
}

}  // namespace

std::string dolphin_texture_name(const TexSource& s, bool mipmapped, int wildcard) {
    const uint64_t tex = xxh64(s.texels, s.base_bytes, 0);
    std::string tlut_name;
    if (s.tlut && s.tlut_bytes) {
        // The palette entries between the lowest and highest index the top level uses.
        uint32_t lo = 0xFFFF, hi = 0;
        if (s.fmt == 8) {          // CI4: two indices a byte
            for (uint32_t i = 0; i < s.base_bytes; i++) {
                const uint32_t a = s.texels[i] & 0xF, b = s.texels[i] >> 4;
                lo = std::min({lo, a, b}); hi = std::max({hi, a, b});
            }
        } else if (s.fmt == 9) {   // CI8
            for (uint32_t i = 0; i < s.base_bytes; i++) { lo = std::min<uint32_t>(lo, s.texels[i]); hi = std::max<uint32_t>(hi, s.texels[i]); }
        } else if (s.fmt == 10) {  // CI14X2. Dolphin byte-swaps the first byte of each pair on
                                   // its own, so its index is that byte's low six bits times 256;
                                   // matched as it is, or its packs would not be found.
            for (uint32_t i = 0; i + 1 < s.base_bytes; i += 2) {
                const uint32_t v = (static_cast<uint32_t>(s.texels[i]) << 8) & 0x3FFF;
                lo = std::min(lo, v); hi = std::max(hi, v);
            }
        }
        if (hi >= lo && 2u * (hi + 1) <= s.tlut_bytes)
            tlut_name = "_" + hex16(xxh64(s.tlut + 2u * lo, 2u * (hi + 1 - lo), 0));
    }
    std::string name = "tex1_" + std::to_string(s.width) + "x" + std::to_string(s.height) + (mipmapped ? "_m" : "");
    if (wildcard == 1) name += "_" + hex16(tex) + "_$";
    else if (wildcard == 2) name += "_$" + tlut_name;
    else name += "_" + hex16(tex) + tlut_name;
    return name + "_" + std::to_string(s.fmt);
}

void texture_pack_set_dir(const char* dir) {
    g_pack.clear();
    g_dolphin.clear();
    if (!dir || !*dir) return;
    std::error_code ec;
    size_t ours = 0, dolphin = 0, dds = 0;
    for (auto it = std::filesystem::recursive_directory_iterator(dir, ec);
         !ec && it != std::filesystem::recursive_directory_iterator(); it.increment(ec)) {
        if (!it->is_regular_file(ec)) continue;
        const std::string ext = lower(it->path().extension().string());
        const std::string stem = it->path().stem().string();
        uint64_t hash;
        std::string name;
        if (ext == ".dds") { if (lower(stem).rfind("tex1_", 0) == 0) dds++; continue; }
        if (ext != ".png") continue;
        if (parse_hash_name(stem, hash)) { g_pack[hash] = it->path(); ours++; }
        else if (parse_dolphin_name(stem, name)) { g_dolphin.emplace(name, it->path()); dolphin++; }
    }
    if (ec) fprintf(stderr, "[texture pack] could not read %s: %s\n", dir, ec.message().c_str());
    fprintf(stderr, "[texture pack] %zu replacement(s) by hash and %zu by Dolphin name in %s\n", ours, dolphin, dir);
    if (dds) fprintf(stderr, "[texture pack] %zu DDS file(s) skipped: only PNG replacements are read so far\n", dds);
}

void texture_pack_set_dump_dir(const char* dir) {
    g_dump_dir.clear();
    if (g_dump_names) { fclose(g_dump_names); g_dump_names = nullptr; }
    if (!dir || !*dir) return;
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    if (ec) { fprintf(stderr, "[texture dump] could not create %s: %s\n", dir, ec.message().c_str()); return; }
    g_dump_dir = dir;
    g_dump_names = fopen((g_dump_dir / "dolphin-names.txt").string().c_str(), "a");
    fprintf(stderr, "[texture dump] writing textures to %s\n", dir);
}

void texture_pack_apply(TexData& t, bool streamed, const TexSource* src) {
    if (t.levels.empty() || !t.width || !t.height) return;
    if (!g_dump_dir.empty() && !streamed && g_dumped.insert(t.hash).second) {
        const std::string name = hex16(t.hash);
        write_png((g_dump_dir / (name + ".png")).string().c_str(), reinterpret_cast<const uint8_t*>(t.levels[0].data()),
                  static_cast<int>(t.width), static_cast<int>(t.height));
        // Which Dolphin name the same texture has, so a pack can be made in either naming.
        if (g_dump_names && src) {
            fprintf(g_dump_names, "%s %s\n", name.c_str(), dolphin_texture_name(*src, t.levels.size() > 1).c_str());
            fflush(g_dump_names);
        }
    }
    if (g_pack.empty() && g_dolphin.empty()) return;
    std::string key;
    const std::filesystem::path* file = find_replacement(t, src, key);
    if (!file || g_refused.count(key)) return;
    if (auto alive = g_loaded[key].lock()) { t.hd = alive; return; }
    t.hd = load(key, *file, t);
    g_loaded[key] = t.hd;
}

}  // namespace gx
