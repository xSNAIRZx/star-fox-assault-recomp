// DVD Interface: command execution against the ISO image, incl. audio stream commands.
#include "../runtime.h"
#include "../platform.h"
#include "../disc_mods.h"
#include "../disc_image.h"
#include <cstdlib>

static PlatFile* g_iso;
static disc_image::Reader g_image;
static uint32_t g_disr, g_dicvr, g_cmd[3], g_dimar, g_dilen, g_dicr, g_diimm, g_dicfg;
static bool g_busy;

#include "dtk.h"
#include <vector>

// The image is a plain .iso, or a CISO: a 0x8000-byte header -- "CISO", a little-endian
// block size, then one byte per block saying whether that block is stored -- followed by
// the stored blocks in order. A block that is not stored reads as zero. Dolphin writes
// CISO for the trailing zero space of a disc, which can be most of an image.
static bool image_read_at(void* context, uint64_t offset, void* dst, uint32_t len) {
    return plat_read_at(static_cast<PlatFile*>(context), offset, dst, len);
}

static bool iso_read_base(uint64_t offset, void* dst, uint32_t len) {
    return g_image.read(offset, dst, len);
}

bool iso_read(uint64_t offset, void* dst, uint32_t len) {
    return iso_read_base(offset, dst, len) && disc_mods::apply(offset, dst, len);
}

void di_init(const char* iso_path) {
    g_iso = plat_open_read(iso_path);
    if (!g_iso) fatal("cannot open disc image %s", iso_path);
    std::string image_error;
    if (!g_image.open({g_iso, 0, image_read_at}, image_error))
        fatal("cannot parse disc image %s: %s", iso_path, image_error.c_str());
    if (g_image.format() == disc_image::Format::Ciso)
        LOG(LOG_DVD, "CISO image mounted through shared image reader");

    disc_mods::clear();
    const char* mods_dir = std::getenv("GCN_MODS_DIR");
    if (mods_dir && *mods_dir) {
        uint8_t disc_header[0x440];
        if (!iso_read_base(0, disc_header, sizeof(disc_header))) fatal("cannot read disc header for mods");
        const uint32_t fst_offset = (static_cast<uint32_t>(disc_header[0x424]) << 24) |
                                    (static_cast<uint32_t>(disc_header[0x425]) << 16) |
                                    (static_cast<uint32_t>(disc_header[0x426]) << 8) | disc_header[0x427];
        const uint32_t fst_size = (static_cast<uint32_t>(disc_header[0x428]) << 24) |
                                  (static_cast<uint32_t>(disc_header[0x429]) << 16) |
                                  (static_cast<uint32_t>(disc_header[0x42A]) << 8) | disc_header[0x42B];
        if (!fst_size || fst_size > 64u * 1024u * 1024u) fatal("disc FST size is invalid for mods");
        std::vector<uint8_t> fst(fst_size);
        if (!iso_read_base(fst_offset, fst.data(), fst_size)) fatal("cannot read disc FST for mods");
        std::string error;
        if (!disc_mods::init(mods_dir, fst.data(), fst.size(), error))
            fatal("cannot load disc mods from %s: %s", mods_dir, error.c_str());
        LOG(LOG_DVD, "disc mods loaded: %u replacement file(s) from %s",
            static_cast<unsigned>(disc_mods::count()), mods_dir);
    }
}

static void di_update_irq() {
    bool irq = ((g_disr & 0x10) && (g_disr & 0x08)) || ((g_disr & 0x04) && (g_disr & 0x02)) ||
               ((g_disr & 0x40) && (g_disr & 0x20)) || ((g_dicvr & 0x04) && (g_dicvr & 0x02));
    pi_set_interrupt(INT_DI, irq);
}

static void di_complete() {
    g_busy = false;
    g_dicr &= ~1u;
    g_disr |= 0x10;  // TCINT
    di_update_irq();
}

static void di_execute() {
    uint32_t cmd = g_cmd[0] >> 24;
    uint64_t delay = TB_FREQ / 10000;  // 100us base latency
    switch (cmd) {
    case 0xA8: {
        uint32_t sub = (g_cmd[0] >> 16) & 0xFF;
        uint64_t offset = sub == 0x40 ? 0 : (uint64_t)g_cmd[1] << 2;
        uint32_t len = g_dilen;
        LOG(LOG_DVD, "read off=%09llX len=%X -> %08X", (unsigned long long)offset, len, g_dimar);
        const uint32_t fit = dma_fit("DVD", g_dimar, len);
        debug_guest_check("before DVD read");
        if (fit && !iso_read(offset, phys_ptr(g_dimar), fit))
            LOG(LOG_DVD, "read past end of image");
        debug_guard_dma("DVD read", g_dimar, len);
        debug_guest_check("after DVD read");
        g_dimar += len;
        g_dilen = 0;
        delay += (uint64_t)len * TB_FREQ / (64 << 20);  // ~64MB/s
        break;
    }
    case 0x12: {  // inquiry
        static const uint8_t inq[0x20] = {0x00, 0x00, 0x00, 0x02, 0x20, 0x06, 0x05, 0x26, 0x41};
        memcpy(phys_ptr(g_dimar), inq, dma_fit("DVD inquiry", g_dimar, sizeof(inq)));
        g_dimar += 0x20;
        g_dilen = 0;
        break;
    }
    case 0xAB: break;  // seek
    case 0xE0: g_diimm = 0; break;  // request error: none
    case 0xE1: {  // audio stream
        std::lock_guard<std::mutex> lk(g_dtk_mutex);
        uint32_t sub = (g_cmd[0] >> 16) & 0xFF;
        if (sub == 0x00) {
            uint64_t off = (uint64_t)g_cmd[1] << 2;
            uint32_t len = g_cmd[2];
            LOG(LOG_DVD, "stream queue off=%llX len=%X", (unsigned long long)off, len);
            if (len == 0) g_dtk.stop_at_end = true;
            else if (!g_dtk.playing || g_dtk.len == 0) {
                g_dtk.start = g_dtk.cur = off; g_dtk.len = len; g_dtk.playing = true;
                memset(g_dtk.hist, 0, sizeof(g_dtk.hist));
                g_dtk.next_start = off; g_dtk.next_len = len; g_dtk.stop_at_end = false;
            } else {
                g_dtk.next_start = off; g_dtk.next_len = len; g_dtk.stop_at_end = false;
            }
        } else if (sub == 0x01) {
            LOG(LOG_DVD, "stream cancel");
            g_dtk.playing = false; g_dtk.len = 0;
        }
        break;
    }
    case 0xE2: {  // stream status
        std::lock_guard<std::mutex> lk(g_dtk_mutex);
        uint32_t sub = (g_cmd[0] >> 16) & 0xFF;
        switch (sub) {
        case 0x00: g_diimm = g_dtk.playing ? 1 : 0; break;
        case 0x01: g_diimm = (uint32_t)((g_dtk.cur & ~0x7FFFull) >> 2); break;
        case 0x02: g_diimm = (uint32_t)(g_dtk.start >> 2); break;
        case 0x03: g_diimm = (uint32_t)g_dtk.len; break;
        }
        break;
    }
    case 0xE3: break;  // stop motor
    case 0xE4: LOG(LOG_DVD, "audio buffer config %08X", g_cmd[0]); break;
    default:
        LOG(LOG_DVD, "unknown DI command %08X %08X %08X", g_cmd[0], g_cmd[1], g_cmd[2]);
        break;
    }
    g_busy = true;
    event_schedule_in(delay, di_complete);
}

uint32_t di_read32(uint32_t off) {
    switch (off) {
    case 0x00: return g_disr;
    case 0x04: return g_dicvr;
    case 0x08: return g_cmd[0];
    case 0x0C: return g_cmd[1];
    case 0x10: return g_cmd[2];
    case 0x14: return g_dimar;
    case 0x18: return g_dilen;
    case 0x1C: return g_dicr;
    case 0x20: return g_diimm;
    case 0x24: return g_dicfg;
    }
    return 0;
}

void di_write32(uint32_t off, uint32_t v) {
    switch (off) {
    case 0x00:
        g_disr = (g_disr & ~0x2Au) | (v & 0x2A);           // masks
        g_disr &= ~(v & 0x54);                             // write-1-to-clear ints
        if (v & 1) g_disr |= 0x40;                         // break request -> BRKINT
        di_update_irq();
        break;
    case 0x04:
        g_dicvr = (g_dicvr & ~0x2u) | (v & 0x2);
        g_dicvr &= ~(v & 0x4);
        di_update_irq();
        break;
    case 0x08: g_cmd[0] = v; break;
    case 0x0C: g_cmd[1] = v; break;
    case 0x10: g_cmd[2] = v; break;
    case 0x14: g_dimar = v & 0x03FFFFE0; break;
    case 0x18: g_dilen = v & ~0x1Fu; break;
    case 0x1C:
        g_dicr = v & 7;
        if ((v & 1) && !g_busy) di_execute();
        break;
    case 0x20: g_diimm = v; break;
    case 0x24: g_dicfg = v; break;
    }
}
