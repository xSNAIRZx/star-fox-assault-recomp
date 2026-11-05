// Minimal PNG reader for replacement textures: zlib inflate (RFC 1950/1951) and the PNG
// filters, written out here so that the runtime needs no image library. Reads non-interlaced
// greyscale, RGB, palette, grey+alpha and RGBA images of 8 bits per channel, 16-bit ones
// (keeping the high byte) and palettes of 1, 2 or 4 bits per index; anything else is refused
// with a reason, never guessed at.
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

struct BitReader {
    const uint8_t* p;
    size_t n, pos = 0;
    uint32_t bits = 0;
    int count = 0;
    bool overrun = false;
    uint32_t get(int k) {
        while (count < k) {
            if (pos >= n) { overrun = true; return 0; }
            bits |= static_cast<uint32_t>(p[pos++]) << count;
            count += 8;
        }
        const uint32_t v = bits & ((1u << k) - 1);
        bits >>= k;
        count -= k;
        return v;
    }
    void align() { bits = 0; count = 0; }
};

// Canonical Huffman decoding table, as in zlib's "puff": symbols by code length.
struct Huffman {
    uint16_t count[16];
    uint16_t symbol[320];
    bool build(const uint8_t* lengths, int n) {
        memset(count, 0, sizeof(count));
        for (int i = 0; i < n; i++) count[lengths[i]]++;
        count[0] = 0;
        int left = 1;
        for (int len = 1; len < 16; len++) {
            left <<= 1;
            left -= count[len];
            if (left < 0) return false;  // over-subscribed
        }
        uint16_t offs[16];
        offs[1] = 0;
        for (int len = 1; len < 15; len++) offs[len + 1] = offs[len] + count[len];
        for (int i = 0; i < n; i++)
            if (lengths[i]) symbol[offs[lengths[i]]++] = static_cast<uint16_t>(i);
        return true;
    }
    int decode(BitReader& br) const {
        int code = 0, first = 0, index = 0;
        for (int len = 1; len < 16; len++) {
            code |= static_cast<int>(br.get(1));
            if (br.overrun) return -1;
            const int c = count[len];
            if (code - c < first) return symbol[index + (code - first)];
            index += c;
            first += c;
            first <<= 1;
            code <<= 1;
        }
        return -1;
    }
};

const uint16_t kLenBase[29] = {3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258};
const uint8_t kLenExtra[29] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0};
const uint16_t kDistBase[30] = {1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577};
const uint8_t kDistExtra[30] = {0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13};

bool inflate_block(BitReader& br, std::vector<uint8_t>& out, const Huffman& lit, const Huffman& dist, size_t limit) {
    for (;;) {
        int sym = lit.decode(br);
        if (sym < 0) return false;
        if (sym < 256) {
            if (out.size() >= limit) return false;
            out.push_back(static_cast<uint8_t>(sym));
        } else if (sym == 256) {
            return true;
        } else {
            sym -= 257;
            if (sym >= 29) return false;
            const size_t len = kLenBase[sym] + br.get(kLenExtra[sym]);
            const int ds = dist.decode(br);
            if (ds < 0 || ds >= 30) return false;
            const size_t d = kDistBase[ds] + br.get(kDistExtra[ds]);
            if (br.overrun || d > out.size() || out.size() + len > limit) return false;
            const size_t from = out.size() - d;
            for (size_t i = 0; i < len; i++) out.push_back(out[from + i]);
        }
    }
}

// zlib stream to bytes; `limit` bounds the output so a hostile file cannot exhaust memory.
bool inflate_zlib(const uint8_t* data, size_t n, size_t limit, std::vector<uint8_t>& out, std::string& why) {
    if (n < 2 || (data[0] & 0x0F) != 8 || ((data[0] << 8) | data[1]) % 31 != 0 || (data[1] & 0x20)) {
        why = "not a zlib stream"; return false;
    }
    BitReader br{data + 2, n - 2};
    // Built once, thread-safely (a function-local static), and only read after that.
    struct Fixed {
        Huffman lit, dist;
        Fixed() {
            uint8_t l[288];
            for (int i = 0; i < 144; i++) l[i] = 8;
            for (int i = 144; i < 256; i++) l[i] = 9;
            for (int i = 256; i < 280; i++) l[i] = 7;
            for (int i = 280; i < 288; i++) l[i] = 8;
            lit.build(l, 288);
            uint8_t d[30];
            for (int i = 0; i < 30; i++) d[i] = 5;
            dist.build(d, 30);
        }
    };
    static const Fixed fixed;
    const Huffman& fixed_lit = fixed.lit;
    const Huffman& fixed_dist = fixed.dist;
    for (bool last = false; !last;) {
        last = br.get(1) != 0;
        const uint32_t type = br.get(2);
        if (br.overrun) { why = "truncated deflate data"; return false; }
        if (type == 0) {
            br.align();
            if (br.pos + 4 > br.n) { why = "truncated stored block"; return false; }
            const uint32_t len = br.p[br.pos] | (br.p[br.pos + 1] << 8);
            const uint32_t nlen = br.p[br.pos + 2] | (br.p[br.pos + 3] << 8);
            br.pos += 4;
            if ((len ^ 0xFFFF) != nlen || br.pos + len > br.n || out.size() + len > limit) { why = "bad stored block"; return false; }
            out.insert(out.end(), br.p + br.pos, br.p + br.pos + len);
            br.pos += len;
        } else if (type == 1) {
            if (!inflate_block(br, out, fixed_lit, fixed_dist, limit)) { why = "bad compressed block"; return false; }
        } else if (type == 2) {
            const int hlit = static_cast<int>(br.get(5)) + 257, hdist = static_cast<int>(br.get(5)) + 1, hclen = static_cast<int>(br.get(4)) + 4;
            static const uint8_t order[19] = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};
            uint8_t cl[19] = {};
            for (int i = 0; i < hclen; i++) cl[order[i]] = static_cast<uint8_t>(br.get(3));
            Huffman clh;
            if (br.overrun || hlit > 286 || hdist > 30 || !clh.build(cl, 19)) { why = "bad dynamic header"; return false; }
            uint8_t lengths[320] = {};
            for (int i = 0; i < hlit + hdist;) {
                const int sym = clh.decode(br);
                if (sym < 0) { why = "bad code lengths"; return false; }
                if (sym < 16) { lengths[i++] = static_cast<uint8_t>(sym); continue; }
                int rep = 0;
                uint8_t val = 0;
                if (sym == 16) { if (!i) { why = "bad repeat"; return false; } val = lengths[i - 1]; rep = 3 + static_cast<int>(br.get(2)); }
                else if (sym == 17) rep = 3 + static_cast<int>(br.get(3));
                else rep = 11 + static_cast<int>(br.get(7));
                if (i + rep > hlit + hdist) { why = "code lengths overrun"; return false; }
                while (rep--) lengths[i++] = val;
            }
            Huffman lit, dist;
            if (!lit.build(lengths, hlit) || !dist.build(lengths + hlit, hdist)) { why = "bad Huffman tables"; return false; }
            if (!inflate_block(br, out, lit, dist, limit)) { why = "bad compressed block"; return false; }
        } else {
            why = "reserved block type"; return false;
        }
    }
    return true;
}

uint32_t be32(const uint8_t* p) { return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | p[3]; }

}  // namespace

// rgba: top-down rows of RGBA8 (red in the low byte, as the texture decoder writes them).
bool read_png(const char* path, uint32_t max_edge, std::vector<uint32_t>& rgba, uint32_t& w, uint32_t& h, std::string& why) {
    FILE* f = fopen(path, "rb");
    if (!f) { why = "cannot open"; return false; }
    std::vector<uint8_t> file;
    uint8_t buf[65536];
    for (size_t got; (got = fread(buf, 1, sizeof(buf), f)) > 0;) {
        file.insert(file.end(), buf, buf + got);
        if (file.size() > (256u << 20)) { fclose(f); why = "file too large"; return false; }
    }
    fclose(f);
    static const uint8_t sig[8] = {137, 80, 78, 71, 13, 10, 26, 10};
    if (file.size() < 8 || memcmp(file.data(), sig, 8) != 0) { why = "not a PNG"; return false; }
    uint32_t depth = 0, ctype = 0;
    bool have_header = false;
    std::vector<uint8_t> idat, palette, trns;
    for (size_t pos = 8; pos + 12 <= file.size();) {
        const uint32_t len = be32(&file[pos]);
        if (len > file.size() - pos - 12) { why = "truncated chunk"; return false; }
        const uint8_t* type = &file[pos + 4];
        const uint8_t* body = &file[pos + 8];
        if (!memcmp(type, "IHDR", 4) && len >= 13) {
            w = be32(body); h = be32(body + 4); depth = body[8]; ctype = body[9];
            if (body[10] != 0 || body[11] != 0) { why = "unknown compression or filter method"; return false; }
            if (body[12] != 0) { why = "interlaced PNGs are not supported"; return false; }
            have_header = true;
        } else if (!memcmp(type, "PLTE", 4)) {
            palette.assign(body, body + len);
        } else if (!memcmp(type, "tRNS", 4)) {
            trns.assign(body, body + len);
        } else if (!memcmp(type, "IDAT", 4)) {
            idat.insert(idat.end(), body, body + len);
        } else if (!memcmp(type, "IEND", 4)) {
            break;
        }
        pos += 12 + len;
    }
    if (!have_header || !w || !h) { why = "no image header"; return false; }
    if (w > max_edge || h > max_edge) { why = "larger than " + std::to_string(max_edge) + " pixels a side"; return false; }
    int channels = 0;
    switch (ctype) {
    case 0: channels = 1; break;
    case 2: channels = 3; break;
    case 3: channels = 1; break;
    case 4: channels = 2; break;
    case 6: channels = 4; break;
    default: why = "unknown colour type"; return false;
    }
    const bool depth_ok = ctype == 3 ? (depth == 1 || depth == 2 || depth == 4 || depth == 8) : (depth == 8 || depth == 16);
    if (!depth_ok) { why = "unsupported bit depth " + std::to_string(depth); return false; }
    if (ctype == 3 && (palette.empty() || palette.size() % 3)) { why = "palette image without a palette"; return false; }
    const size_t bits_per_pixel = static_cast<size_t>(channels) * depth;
    const size_t stride = (static_cast<size_t>(w) * bits_per_pixel + 7) / 8;
    const size_t bpp = (bits_per_pixel + 7) / 8;  // filter distance in bytes
    std::vector<uint8_t> raw;
    raw.reserve((stride + 1) * h);
    if (!inflate_zlib(idat.data(), idat.size(), (stride + 1) * h, raw, why)) return false;
    if (raw.size() != (stride + 1) * h) { why = "image data is the wrong size"; return false; }
    std::vector<uint8_t> prev(stride, 0), line(stride);
    rgba.resize(static_cast<size_t>(w) * h);
    for (uint32_t y = 0; y < h; y++) {
        const uint8_t* src = &raw[y * (stride + 1)];
        const uint8_t filter = src[0];
        for (size_t x = 0; x < stride; x++) {
            const int a = x >= bpp ? line[x - bpp] : 0, b = prev[x], c = x >= bpp ? prev[x - bpp] : 0;
            int v = src[1 + x];
            switch (filter) {
            case 0: break;
            case 1: v += a; break;
            case 2: v += b; break;
            case 3: v += (a + b) / 2; break;
            case 4: {
                const int p = a + b - c, pa = p > a ? p - a : a - p, pb = p > b ? p - b : b - p, pc = p > c ? p - c : c - p;
                v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
                break;
            }
            default: why = "unknown row filter"; return false;
            }
            line[x] = static_cast<uint8_t>(v);
        }
        for (uint32_t x = 0; x < w; x++) {
            uint8_t r, g, b, al = 255;
            if (ctype == 3) {
                const size_t bit = static_cast<size_t>(x) * depth;
                const uint32_t idx = (line[bit / 8] >> (8 - depth - bit % 8)) & ((1u << depth) - 1);
                if (idx * 3 + 2 >= palette.size()) { why = "palette index out of range"; return false; }
                r = palette[idx * 3]; g = palette[idx * 3 + 1]; b = palette[idx * 3 + 2];
                if (idx < trns.size()) al = trns[idx];
            } else {
                const size_t step = depth / 8;  // 1 or 2: the high byte of a 16-bit sample
                const uint8_t* px = &line[static_cast<size_t>(x) * channels * step];
                const uint8_t c0 = px[0], c1 = channels > 1 ? px[step] : 0, c2 = channels > 2 ? px[2 * step] : 0, c3 = channels > 3 ? px[3 * step] : 0;
                if (ctype == 0) { r = g = b = c0; }
                else if (ctype == 4) { r = g = b = c0; al = c1; }
                else { r = c0; g = c1; b = c2; if (ctype == 6) al = c3; }
                if (ctype == 2 && trns.size() >= 6 && depth == 8 && trns[1] == r && trns[3] == g && trns[5] == b) al = 0;
                if (ctype == 0 && trns.size() >= 2 && depth == 8 && trns[1] == r) al = 0;
            }
            rgba[static_cast<size_t>(y) * w + x] = r | (uint32_t(g) << 8) | (uint32_t(b) << 16) | (uint32_t(al) << 24);
        }
        std::swap(prev, line);
    }
    return true;
}
