// See texture_pack.h.
#include "texture_pack.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <filesystem>
#include <string>
#include <system_error>
#include <unordered_map>
#include <unordered_set>

#include "render.h"

bool write_png(const char* path, const uint8_t* rgba, int w, int h);
bool read_png(const char* path, uint32_t max_edge, std::vector<uint32_t>& rgba, uint32_t& w, uint32_t& h, std::string& why);

namespace gx {
namespace {

std::unordered_map<uint64_t, std::filesystem::path> g_pack;  // hash -> replacement file
std::filesystem::path g_dump_dir;
std::unordered_set<uint64_t> g_dumped;
// Decoded replacements still in use, so a texture the game drops and decodes again does not
// read and scale its image again. Entries expire with the last texture holding them.
std::unordered_map<uint64_t, std::weak_ptr<const TexHd>> g_loaded;
std::unordered_set<uint64_t> g_refused;  // logged once each

constexpr uint32_t kMaxEdge = 8192;

bool parse_hash_name(const std::filesystem::path& p, uint64_t& hash) {
    std::string ext = p.extension().string();
    for (char& c : ext) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
    const std::string stem = p.stem().string();
    if (ext != ".png" || stem.size() != 16) return false;
    for (char c : stem)
        if (!isxdigit(static_cast<unsigned char>(c))) return false;
    hash = std::stoull(stem, nullptr, 16);
    return true;
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

std::shared_ptr<const TexHd> load(uint64_t hash, const std::filesystem::path& file, const TexData& t) {
    auto refuse = [&](const std::string& why) {
        if (g_refused.insert(hash).second)
            fprintf(stderr, "[texture pack] %s refused: %s\n", file.filename().string().c_str(), why.c_str());
        return std::shared_ptr<const TexHd>();
    };
    auto hd = std::make_shared<TexHd>();
    std::vector<uint32_t> top;
    std::string why;
    if (!read_png(file.string().c_str(), kMaxEdge, top, hd->width, hd->height, why)) return refuse(why);
    if (hd->width % t.width || hd->height % t.height || hd->width / t.width != hd->height / t.height)
        return refuse("is " + std::to_string(hd->width) + "x" + std::to_string(hd->height) + ", not the " +
                      std::to_string(t.width) + "x" + std::to_string(t.height) + " original's shape at a whole scale");
    const uint32_t scale = hd->width / t.width;
    if (scale != 2 && scale != 4 && scale != 8)
        return refuse("is " + std::to_string(scale) + " times the original's size; use 2, 4 or 8");
    hd->shift = scale == 2 ? 1 : scale == 4 ? 2 : 3;
    // As many levels as reach the original's smallest: the extra top ones, then one for each
    // of the game's own.
    const size_t want = hd->shift + std::max<size_t>(1, t.levels.size());
    uint32_t w = hd->width, h = hd->height;
    hd->levels.push_back(std::move(top));
    while (hd->levels.size() < want) {
        uint32_t nw, nh;
        hd->levels.push_back(half(hd->levels.back(), w, h, nw, nh));
        w = nw; h = nh;
    }
    fprintf(stderr, "[texture pack] %016llx: %ux%u replaced at %ux%u\n", static_cast<unsigned long long>(hash),
            t.width, t.height, hd->width, hd->height);
    return hd;
}

}  // namespace

void texture_pack_set_dir(const char* dir) {
    g_pack.clear();
    if (!dir || !*dir) return;
    std::error_code ec;
    size_t files = 0;
    for (auto it = std::filesystem::recursive_directory_iterator(dir, ec);
         !ec && it != std::filesystem::recursive_directory_iterator(); it.increment(ec)) {
        uint64_t hash;
        if (it->is_regular_file(ec) && parse_hash_name(it->path(), hash)) {
            g_pack[hash] = it->path();
            files++;
        }
    }
    if (ec) fprintf(stderr, "[texture pack] could not read %s: %s\n", dir, ec.message().c_str());
    fprintf(stderr, "[texture pack] %zu replacement(s) in %s\n", files, dir);
}

void texture_pack_set_dump_dir(const char* dir) {
    g_dump_dir.clear();
    if (!dir || !*dir) return;
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    if (ec) { fprintf(stderr, "[texture dump] could not create %s: %s\n", dir, ec.message().c_str()); return; }
    g_dump_dir = dir;
    fprintf(stderr, "[texture dump] writing textures to %s\n", dir);
}

void texture_pack_apply(TexData& t, bool streamed) {
    if (t.levels.empty() || !t.width || !t.height) return;
    if (!g_dump_dir.empty() && !streamed && g_dumped.insert(t.hash).second) {
        char name[32];
        snprintf(name, sizeof(name), "%016llx.png", static_cast<unsigned long long>(t.hash));
        write_png((g_dump_dir / name).string().c_str(), reinterpret_cast<const uint8_t*>(t.levels[0].data()),
                  static_cast<int>(t.width), static_cast<int>(t.height));
    }
    if (g_pack.empty()) return;
    auto found = g_pack.find(t.hash);
    if (found == g_pack.end() || g_refused.count(t.hash)) return;
    if (auto alive = g_loaded[t.hash].lock()) { t.hd = alive; return; }
    t.hd = load(t.hash, found->second, t);
    g_loaded[t.hash] = t.hd;
}

}  // namespace gx
