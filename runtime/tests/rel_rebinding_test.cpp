#include "recomp.h"
#include "runtime.h"

#include <array>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>

namespace {

constexpr uint32_t kStringTable = 0x80005000;
constexpr uint32_t kInfoA = 0x815583C0;
constexpr uint32_t kInfoB = 0x81559000;
constexpr uint32_t kSectionA = 0x8155848C;
constexpr uint32_t kSectionB = 0x8155849C;
constexpr uint32_t kSectionOverlap = 0x81570000;
constexpr uint32_t kInfoOverlapA = 0x81560000;
constexpr uint32_t kInfoOverlapB = 0x81561000;
constexpr uint32_t kTableA = 0x81558380;
constexpr uint32_t kTableB = 0x81558FC0;
constexpr uint32_t kTableOverlapA = 0x81560080;
constexpr uint32_t kTableOverlapB = 0x81561080;

constexpr uint32_t kOldCanon = 0x81815420;
constexpr uint32_t kNewCanon = 0x81825420;
constexpr uint32_t kOverlapCanon = 0x81835420;
constexpr uint32_t kSectionSize = 0x200;

std::array<uint8_t, RAM_SIZE> memory{};

[[noreturn]] void fail(const char* message) { throw std::runtime_error(message); }

void put8(uint32_t address, uint8_t value) { memory[address & 0x3FFFFFFFu] = value; }

void put_be32(uint32_t address, uint32_t value) {
    put8(address, static_cast<uint8_t>(value >> 24));
    put8(address + 1, static_cast<uint8_t>(value >> 16));
    put8(address + 2, static_cast<uint8_t>(value >> 8));
    put8(address + 3, static_cast<uint8_t>(value));
}

uint32_t append_string(uint32_t offset, const char* value) {
    const size_t length = std::strlen(value);
    for (size_t i = 0; i < length; i++) put8(kStringTable + offset + static_cast<uint32_t>(i), value[i]);
    put8(kStringTable + offset + static_cast<uint32_t>(length), 0);
    return static_cast<uint32_t>(length);
}

void set_module(uint32_t info, uint32_t table, uint32_t id, const char* name, uint32_t name_offset,
                uint32_t section_base, uint32_t next, uint32_t previous) {
    const uint32_t name_length = append_string(name_offset, name);
    put_be32(info, id);
    put_be32(info + 4, next);
    put_be32(info + 8, previous);
    put_be32(info + 0x0C, 2);
    put_be32(info + 0x10, table);
    put_be32(info + 0x14, name_offset);
    put_be32(info + 0x18, name_length);
    put_be32(table, 0);
    put_be32(table + 4, 0);
    put_be32(table + 8, section_base | 1u);
    put_be32(table + 12, kSectionSize);
}

constexpr uint32_t kInfoRelinkA = 0x81600000;
constexpr uint32_t kInfoRelinkB = 0x81620000;
constexpr uint32_t kTableRelinkA = 0x81600080;
constexpr uint32_t kTableRelinkB = 0x81620080;
constexpr uint32_t kRelinkTextA = 0x81600100;
constexpr uint32_t kRelinkTextB = 0x81620100;
constexpr uint32_t kRelinkDataA = 0x81500000;
constexpr uint32_t kRelinkDataB = 0x81510000;
constexpr uint32_t kRelinkDataC = 0x81520000;
constexpr uint32_t kRelinkCanon = 0x81845420;

// A linked module with code in section 1 and data in section 2 (as a .bss would be).
void set_relinkable(uint32_t info, uint32_t table, uint32_t text, uint32_t data) {
    const uint32_t name_length = append_string(128, "relink.rel");
    put_be32(info, 8);
    put_be32(info + 4, 0);
    put_be32(info + 8, 0);
    put_be32(info + 0x0C, 3);
    put_be32(info + 0x10, table);
    put_be32(info + 0x14, 128);
    put_be32(info + 0x18, name_length);
    put_be32(table, 0);
    put_be32(table + 4, 0);
    put_be32(table + 8, text | 1u);
    put_be32(table + 12, kSectionSize);
    put_be32(table + 16, data);
    put_be32(table + 20, 0x100);
}

void require(bool condition, const char* message) {
    if (!condition) fail(message);
}

}  // namespace

uint8_t* g_mem = memory.data();
bool g_log_enabled[LOG_COUNT]{};

const RecompRel g_recomp_rels[] = {
    {6, "old.rel", 1, {{1, kOldCanon, kSectionSize, 1}}},
    {6, "new.rel", 1, {{1, kNewCanon, kSectionSize, 1}}},
    {7, "overlap.rel", 1, {{1, kOverlapCanon, kSectionSize, 1}}},
    {8, "relink.rel", 2, {{1, kRelinkCanon, kSectionSize, 1}, {2, 0, 0x100, 0}}},
};
const uint32_t g_recomp_rel_count = static_cast<uint32_t>(sizeof(g_recomp_rels) / sizeof(g_recomp_rels[0]));

uint32_t vm_translate(uint32_t address, int) { return address & 0x3FFFFFFFu; }

uint32_t mmio_read32(uint32_t) { return 0; }
uint8_t mmio_read8(uint32_t) { return 0; }

void log_msg(LogCat, const char*, ...) {}

[[noreturn]] void fatal(const char*, ...) { std::abort(); }

[[noreturn]] void plat_exit_now(int code) { std::exit(code); }

uint32_t gx_frames_submitted() { return 0; }

int main() {
    try {
        put_be32(0x800030D0, kStringTable);

        // Bind the old variant. The call target equals the crash callback address from
        // the old .text@0xCC + prolog@0x104 layout.
        const uint32_t callback = 0x81558590;
        put_be32(0x800030C8, kInfoA);
        set_module(kInfoA, kTableA, 6, "old.rel", 0, kSectionA, 0, 0);
        rels_linked(kInfoA);
        require(rels_canon(callback) == kOldCanon + (callback - kSectionA),
                "old variant did not bind to its canonical section");

        // The same SDK header and text range are reused by a different variant whose
        // .text starts 16 bytes later. A stale mapping must be rejected before a still
        // valid old canonical function slot can dispatch.
        set_module(kInfoA, kTableA, 6, "new.rel", 32, kSectionB, 0, 0);
        require(rels_canon(callback) == callback,
                "reused module header retained the old canonical mapping");
        require(rels_bind(callback) != 0, "current variant was not discovered by the module list");
        require(rels_canon(callback) == kNewCanon + (callback - kSectionB),
                "callback did not rebind to the current variant's canonical offset");

        // OSUnlink can restore a resident module header to file-relative section offsets
        // before dispatching its epilog callback. The mapping must remain valid through
        // that callback, then be retired by the post-OSUnlink hook.
        put_be32(0x800030C8, 0);
        put_be32(kInfoA + 4, 0);
        put_be32(kInfoA + 8, 0);
        put_be32(kTableA + 8, 0xD5);  // .text file offset 0xD4, executable flag set
        require(rels_canon(callback) == kNewCanon + (callback - kSectionB),
                "resident callback was rejected after its header became unlinked/raw");
        rels_unlinked(kInfoA);
        require(rels_canon(callback) == callback,
                "completed OSUnlink did not retire its resident mapping");

        // A custom linker may reuse an executable range while old and new module-info
        // records are both still listed. Registering the new module must retire the
        // overlapping range globally, even though the old header has a different address.
        put_be32(0x800030C8, kInfoOverlapA);
        set_module(kInfoOverlapA, kTableOverlapA, 6, "old.rel", 64, kSectionOverlap, kInfoOverlapB, 0);
        set_module(kInfoOverlapB, kTableOverlapB, 7, "overlap.rel", 96, kSectionOverlap, 0, kInfoOverlapA);
        rels_linked(kInfoOverlapA);
        const uint32_t overlap_target = kSectionOverlap + 0x40;
        require(rels_canon(overlap_target) == kOldCanon + 0x40,
                "initial overlapping module did not bind");
        rels_linked(kInfoOverlapB);
        require(rels_canon(overlap_target) == kOverlapCanon + 0x40,
                "new overlapping module did not replace the old range");

        // A linker the runtime cannot hook links a module, links a second copy elsewhere,
        // unlinks that, and links the module again at the first copy's header with its data
        // section somewhere new. The first call into the new link resolves through the first
        // copy's mapping, which still matches; the section bases the code uses must follow
        // the header to the new data section, not stay on the second copy's freed one.
        put_be32(0x800030C8, 0);
        set_relinkable(kInfoRelinkA, kTableRelinkA, kRelinkTextA, kRelinkDataA);
        rels_linked(kInfoRelinkA);
        set_relinkable(kInfoRelinkB, kTableRelinkB, kRelinkTextB, kRelinkDataB);
        rels_linked(kInfoRelinkB);
        require(rels_section_address(8, 2) == kRelinkDataB, "second copy's data section not in use");
        put_be32(kTableRelinkB + 8, 0xD5);  // second copy unlinked: file offsets again
        put_be32(kTableRelinkB + 16, 0x200);
        set_relinkable(kInfoRelinkA, kTableRelinkA, kRelinkTextA, kRelinkDataC);  // relinked, new data
        const uint32_t relink_target = kRelinkTextA + 0x20;
        require(rels_canon(relink_target) == kRelinkCanon + 0x20, "relinked copy did not resolve");
        require(rels_section_address(8, 2) == kRelinkDataC,
                "relinked copy kept the previous copy's data section");

        // While the header is restored to file offsets for unlinking, the bases in use stay.
        put_be32(kTableRelinkA + 8, 0xD5);
        put_be32(kTableRelinkA + 16, 0x200);
        require(rels_canon(relink_target) == kRelinkCanon + 0x20, "unlinking copy rejected during its epilog");
        require(rels_section_address(8, 2) == kRelinkDataC, "unlinking header changed the bases in use");
    } catch (const std::exception& error) {
        std::fprintf(stderr, "rel_rebinding_test: %s\n", error.what());
        return 1;
    }
    return 0;
}
