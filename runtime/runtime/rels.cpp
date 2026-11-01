// Relocatable modules: the SDK's .rel files, linked by OSLink wherever the game allocates.
//
// The recompiler compiles each module at a canonical address (recomp/rel.py lays them out
// above RAM) and the game links its own copy wherever it likes, which may differ from run
// to run. Two things tie the two together:
//
//   * Every instruction whose immediate the linker would patch with an address in a module
//     (the HA/HI/LO halves of a lis/addi or lis/lwz pair) is generated as an expression on
//     g_rel_base, the section's current base, so it computes what the linker would have
//     written. Branches between functions need nothing: the canonical link resolved them,
//     and each is a C call. Data the linker relocates is in guest memory as the game
//     linked it.
//   * A code address the game holds -- a callback, a vtable entry, a jump table's target --
//     is where the game linked the module. rels_canon maps it to the canonical address,
//     which the function table and the module's jump tables are keyed by.
//
// The generated code calls rels_linked after every successful OSLink/OSLinkFixed and
// rels_unlinked before every OSUnlink, so both stay exactly as the game's module list.
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "platform.h"
#include "recomp.h"
#include "runtime.h"

uint32_t g_rel_base[REL_MAX_MODULES * REL_MAX_SECTIONS];

namespace {

// The executable sections currently linked: [base, base + size) maps to canon.
struct Live { uint32_t base, size, canon, module, info, section; };
constexpr int MAX_LIVE = 512;
Live g_live[MAX_LIVE];
std::atomic<int> g_live_count{0};

std::string module_name(uint32_t info);
int module_index_for_info(uint32_t info);

bool guest_address(uint32_t a) {
    return a >= 0x80000000u && a < 0x81800000u && !(a & 3u);
}

// A module may be unlinked from the SDK list while callbacks into its resident code are
// still pending. Keep its mapping while the header still identifies the same compiled
// module and executable section. A subsequent link that reuses the range is retired in
// rels_linked, and a relink at this header refreshes the entry there.
bool live_matches(const Live& live) {
    const uint32_t info = live.info;
    if (!guest_address(info)) return false;
    if (live.module >= g_recomp_rel_count || module_index_for_info(info) != (int)live.module) return false;

    const uint32_t count = LD32(info + 0x0C);
    if (live.section >= count || count > REL_MAX_SECTIONS) return false;
    uint32_t table = LD32(info + 0x10);
    if (table < 0x80000000u) table += info;
    // OSUnlink can restore the module header's section table to file-relative offsets
    // before invoking its epilog callback. Validate every section against the compiled
    // module variant, then accept either that raw header or the absolute linked layout.
    // In both cases this Live base remains the address of the resident code being called.
    const RecompRel& module = g_recomp_rels[live.module];
    bool found = false;
    for (uint32_t i = 0; i < module.count; i++) {
        const RecompRelSection& section = module.sections[i];
        if (section.index >= count) return false;
        const uint32_t descriptor = LD32(table + section.index * 8);
        if (((descriptor & 1u) != 0) != (section.exec != 0) ||
            LD32(table + section.index * 8 + 4) != section.size) return false;
        if (section.index != live.section) continue;
        found = true;
        const uint32_t base = descriptor & ~1u;
        if (base >= 0x80000000u && base != live.base) return false;
        if (base < 0x80000000u && (uint64_t)info + base + section.size > 0x81800000u) return false;
    }
    return found;
}

std::string rel_stem(const char* name) {
    std::string stem = name;
    const size_t slash = stem.find_last_of("\\/");
    if (slash != std::string::npos) stem = stem.substr(slash + 1);
    const size_t dot = stem.find_last_of('.');
    if (dot != std::string::npos) stem = stem.substr(0, dot);
    return stem;
}

int module_index(uint32_t id, const std::string* name = nullptr) {
    int only = -1;
    for (uint32_t k = 0; k < g_recomp_rel_count; k++) {
        if (g_recomp_rels[k].id != id) continue;
        if (name) {
            if (rel_stem(g_recomp_rels[k].name) == *name) return (int)k;
        } else {
            if (only >= 0) return -1;  // Reused module ID; an ID alone cannot identify its file.
            only = (int)k;
        }
    }
    return name ? -1 : only;
}

int module_index_for_info(uint32_t info) {
    const std::string name = module_name(info);
    const uint32_t id = LD32(info);
    const int named = module_index(id, &name);
    if (named >= 0) return named;
    const int unique = module_index(id);
    if (unique >= 0) return unique;

    // Some games do not install the OS module string table. When IDs are reused, the
    // linked section sizes still identify the build-time variant if they differ.
    const uint32_t count = LD32(info + 0x0C);
    uint32_t table = LD32(info + 0x10);
    if (!count || count > REL_MAX_SECTIONS) return -1;
    if (table < 0x80000000u) table += info;
    int match = -1;
    for (uint32_t k = 0; k < g_recomp_rel_count; k++) {
        const RecompRel& m = g_recomp_rels[k];
        if (m.id != id) continue;
        bool same = true;
        for (uint32_t s = 0; s < m.count; s++) {
            const RecompRelSection& section = m.sections[s];
            if (section.index >= count || LD32(table + section.index * 8 + 4) != section.size) {
                same = false;
                break;
            }
        }
        if (!same) continue;
        if (match >= 0) return -1;
        match = (int)k;
    }
    return match;
}

void forget(uint32_t info) {
    int n = g_live_count.load(std::memory_order_acquire);
    for (int i = 0; i < n; i++)
        if (g_live[i].info == info) g_live[i].size = 0;
}

// The module's file as it is before the link: header, section table, sections, import
// table and relocations, whichever ends last. Relocation lists end at R_DOLPHIN_END.
uint32_t unlinked_size(uint32_t info) {
    const uint32_t nsec = LD32(info + 0x0C), table = LD32(info + 0x10);
    const uint32_t imp_off = LD32(info + 0x28), imp_size = LD32(info + 0x2C);
    uint32_t end = std::max(table + nsec * 8, imp_off + imp_size);
    for (uint32_t i = 0; i < nsec; i++) {
        const uint32_t off = LD32(info + table + i * 8) & ~1u, size = LD32(info + table + i * 8 + 4);
        if (off) end = std::max(end, off + size);
    }
    for (uint32_t k = 0; k < imp_size / 8; k++) {
        uint32_t p = LD32(info + imp_off + k * 8 + 4);
        for (uint32_t guard = 0; guard < 0x1000000; guard++, p += 8)
            if (LD8(info + p + 2) == 203) { p += 8; break; }  // R_DOLPHIN_END
        end = std::max(end, p);
    }
    return end;
}

// The module's name, from the string table the game gave OSSetStringTable (the OS keeps it
// at 0x800030D0): its last path component without the extension, as the build names the
// module's files.
std::string module_name(uint32_t info) {
    const uint32_t strings = LD32(0x800030D0), off = LD32(info + 0x14), len = LD32(info + 0x18);
    char buf[64];
    snprintf(buf, sizeof buf, "module%u", LD32(info));
    if (!strings || !len || len > 256) return buf;
    std::string path;
    for (uint32_t i = 0; i < len; i++) {
        char ch = (char)LD8(strings + off + i);
        if (!ch) break;
        path += ch;
    }
    size_t slash = path.find_last_of("\\/");
    if (slash != std::string::npos) path = path.substr(slash + 1);
    size_t dot = path.find_last_of('.');
    if (dot != std::string::npos) path = path.substr(0, dot);
    return path.empty() ? std::string(buf) : path;
}

}  // namespace

// Before a link: a module that was not recompiled is one the game assembled in memory.
// GCN_REL_DUMP=<dir> writes it there as <name>.rel, exactly as OSLink is about to see it,
// for the build to recompile (gcn_add_game's REL_RUNTIME); GCN_REL_DUMP_WANT=a,b ends the
// run once those are written.
void rels_linking(uint32_t info) {
    if (module_index_for_info(info) >= 0) return;
    const char* dir = getenv("GCN_REL_DUMP");
    if (!dir) return;
    const std::string name = module_name(info);
    const uint32_t size = unlinked_size(info);
    const std::string path = std::string(dir) + "/" + name + ".rel";
    FILE* f = fopen(path.c_str(), "wb");
    if (!f) fatal("GCN_REL_DUMP: cannot write %s", path.c_str());
    for (uint32_t i = 0; i < size; i++) fputc(LD8(info + i), f);
    fclose(f);
    fprintf(stderr, "[rels] %s (module %u, %u bytes) written to %s\n", name.c_str(), LD32(info), size, path.c_str());
    static std::string done;
    done += "," + name + ",";
    if (const char* want = getenv("GCN_REL_DUMP_WANT")) {
        std::string w = want;
        size_t p = 0;
        bool all = true;
        while (p <= w.size()) {
            size_t q = w.find(',', p);
            if (q == std::string::npos) q = w.size();
            if (q > p && done.find("," + w.substr(p, q - p) + ",") == std::string::npos) all = false;
            p = q + 1;
        }
        if (all) { fflush(stderr); plat_exit_now(0); }
    }
}

void rels_linked(uint32_t info) {
    const uint32_t id = LD32(info);
    const int k = module_index_for_info(info);
    if (k < 0) {
        LOG(LOG_OS, "OSLink: module %u at %08X was not recompiled\n", id, info);
        return;
    }
    if (k >= REL_MAX_MODULES) fatal("rels: too many modules");
    forget(info);
    // After a link the header's section table pointer and each section's offset are
    // absolute; the low bit of an offset marks an executable section.
    uint32_t table = LD32(info + 0x10);
    if (table < 0x80000000u) table += info;
    const RecompRel& m = g_recomp_rels[k];
    for (uint32_t i = 0; i < m.count; i++) {
        const RecompRelSection& s = m.sections[i];
        const uint32_t base = LD32(table + s.index * 8) & ~1u;
        g_rel_base[k * REL_MAX_SECTIONS + s.index] = base;
        if (!s.exec) continue;
        // Game-specific linkers can reuse an executable section address without
        // reaching the SDK OSUnlink hook. Retire any older mapping that overlaps
        // the section being registered, even if its OSModuleInfo lived elsewhere.
        const uint64_t end = (uint64_t)base + s.size;
        int n = g_live_count.load(std::memory_order_relaxed);
        for (int j = 0; j < n; j++) {
            const Live& live = g_live[j];
            if (live.size && (uint64_t)base < (uint64_t)live.base + live.size &&
                             (uint64_t)live.base < end) {
                g_live[j].size = 0;
            }
        }
        int slot = -1;
        for (int j = 0; j < n; j++)
            if (!g_live[j].size) { slot = j; break; }
        if (slot < 0) {
            if (n == MAX_LIVE) fatal("rels: too many linked sections");
            slot = n;
        }
        g_live[slot] = {base, s.size, s.canon, (uint32_t)k, info, s.index};
        if (slot == n) g_live_count.store(n + 1, std::memory_order_release);
    }
    if (g_log_enabled[LOG_OS]) {
        char secs[REL_MAX_SECTIONS * 16] = "";
        size_t n = 0;
        for (uint32_t i = 0; i < m.count && n < sizeof secs - 16; i++)
            n += snprintf(secs + n, sizeof secs - n, " %u:%08X", m.sections[i].index,
                          g_rel_base[k * REL_MAX_SECTIONS + m.sections[i].index]);
        LOG(LOG_OS, "OSLink: %s (module %u) at %08X, sections%s\n", m.name, id, info, secs);
    }
}

void rels_unlinked(uint32_t info) {
    const int k = module_index_for_info(info);
    forget(info);
    if (k >= 0) {
        for (uint32_t s = 0; s < REL_MAX_SECTIONS; s++) g_rel_base[k * REL_MAX_SECTIONS + s] = 0;
        LOG(LOG_OS, "OSUnlink: %s at %08X\n", g_recomp_rels[k].name, info);
    }
}

uint32_t rels_section_address(uint32_t module_id, uint32_t section) {
    if (section >= REL_MAX_SECTIONS) return 0;
    for (uint32_t k = 0; k < g_recomp_rel_count; k++) {
        if (g_recomp_rels[k].id != module_id) continue;
        const uint32_t base = g_rel_base[k * REL_MAX_SECTIONS + section];
        if (base) return base;
    }
    return 0;
}

uint32_t rels_canon(uint32_t a) {
    int n = g_live_count.load(std::memory_order_acquire);
    for (int i = 0; i < n; i++) {
        const Live& l = g_live[i];
        if (a - l.base < l.size) {
            if (live_matches(l)) return l.canon + (a - l.base);
            g_live[i].size = 0;
        }
    }
    return a;
}

// A game can install its own linker or leave OSLink anonymous in the DOL, so the
// generated name-based hooks cannot always observe a successful link. On the first
// indirect call into an unmapped address, inspect the SDK's live module list and register
// the matching compiled module. This keeps the fast path unchanged for already-bound RELs.
uint32_t rels_bind(uint32_t addr) {
    uint32_t info = LD32(0x800030C8);
    for (uint32_t guard = 0; info && guard < 512; guard++) {
        if ((info & 0xC0000000u) != 0x80000000u || (info & 3u)) return false;
        const int k = module_index_for_info(info);
        if (k >= 0) {
            const uint32_t count = LD32(info + 0x0C);
            uint32_t table = LD32(info + 0x10);
            if (count && count <= REL_MAX_SECTIONS) {
                if (table < 0x80000000u) table += info;
                const RecompRel& m = g_recomp_rels[k];
                for (uint32_t i = 0; i < m.count; i++) {
                    const RecompRelSection& section = m.sections[i];
                    if (!section.exec || section.index >= count) continue;
                    const uint32_t descriptor = LD32(table + section.index * 8);
                    const uint32_t base = descriptor & ~1u;
                    const uint32_t size = LD32(table + section.index * 8 + 4);
                    if ((descriptor & 1u) && addr - base < size) {
                        rels_linked(info);
                        return true;
                    }
                }
            }
        }
        info = LD32(info + 4);
    }
    return false;
}
