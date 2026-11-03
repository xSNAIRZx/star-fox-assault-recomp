#include "../runtime/guest_stack.h"

#include <string.h>

// A small fake of main memory: words addressed as the guest addresses them, over a window
// that starts at the guest's RAM base.
struct FakeRam {
    static const uint32_t kBase = 0x80000000u;
    static const size_t kWords = 1024;   // 4 KiB, enough for the chains below
    uint32_t w[kWords];
};

static bool fake_read(void* ctx, uint32_t ea, uint32_t* out) {
    FakeRam* ram = static_cast<FakeRam*>(ctx);
    if (ea < FakeRam::kBase || (ea & 3u)) return false;
    const size_t i = (ea - FakeRam::kBase) / 4;
    if (i >= FakeRam::kWords) return false;
    *out = ram->w[i];
    return true;
}

int main() {
    FakeRam ram = {};
    uint32_t frames[8] = {};

    // An empty chain: the frame pointer is in RAM but its word is zero.
    if (gcn_walk_guest_stack(FakeRam::kBase + 0x100, fake_read, &ram, frames, 8) != 0) return 1;

    // Two frames: sp -> prev = sp+0x20 (ret sp+0x24) -> prev = sp+0x40 (ret sp+0x44).
    const uint32_t sp = FakeRam::kBase + 0x100;
    ram.w[(sp - FakeRam::kBase) / 4] = sp + 0x20;
    ram.w[(sp + 0x20 + 4 - FakeRam::kBase) / 4] = 0x80136C60u;
    ram.w[(sp + 0x20 - FakeRam::kBase) / 4] = sp + 0x40;
    ram.w[(sp + 0x40 + 4 - FakeRam::kBase) / 4] = 0x801A2B10u;
    ram.w[(sp + 0x40 - FakeRam::kBase) / 4] = 0;   // end of chain

    if (gcn_walk_guest_stack(sp, fake_read, &ram, frames, 8) != 2) return 2;
    if (frames[0] != 0x80136C60u) return 3;
    if (frames[1] != 0x801A2B10u) return 4;

    char text[96];
    if (!gcn_stack_text(frames, 2, text, sizeof text)) return 5;
    if (strcmp(text, "80136C60 801A2B10")) return 6;
    if (gcn_stack_text(frames, 0, text, sizeof text)) return 7;

    // A frame pointer that does not move up the stack ends the walk instead of spinning.
    ram.w[(sp - FakeRam::kBase) / 4] = sp;
    if (gcn_walk_guest_stack(sp, fake_read, &ram, frames, 8) != 0) return 8;
    ram.w[(sp - FakeRam::kBase) / 4] = sp - 4;
    if (gcn_walk_guest_stack(sp, fake_read, &ram, frames, 8) != 0) return 9;

    // A pointer outside main memory ends it too, and so does one in the locked cache window.
    ram.w[(sp - FakeRam::kBase) / 4] = 0xE0002000u;
    if (gcn_walk_guest_stack(sp, fake_read, &ram, frames, 8) != 0) return 10;
    ram.w[(sp - FakeRam::kBase) / 4] = 0x81800000u;
    if (gcn_walk_guest_stack(sp, fake_read, &ram, frames, 8) != 0) return 11;

    // A stack pointer that is not in main memory is never walked.
    if (gcn_walk_guest_stack(0x1000u, fake_read, &ram, frames, 8) != 0) return 12;

    // Depth and capacity are respected: a chain longer than max stores only max and stops.
    ram = {};
    uint32_t cur = sp;
    for (size_t i = 0; i < FakeRam::kWords - 2; i++) {
        const uint32_t next = cur + 8;
        if (next + 8 >= FakeRam::kBase + FakeRam::kWords * 4) break;
        ram.w[(cur - FakeRam::kBase) / 4] = next;
        ram.w[(next + 4 - FakeRam::kBase) / 4] = (uint32_t)(0x80100000u + (uint32_t)i * 4u);
        cur = next;
    }
    if (gcn_walk_guest_stack(sp, fake_read, &ram, frames, 3) != 3) return 13;
    if (gcn_walk_guest_stack(sp, fake_read, &ram, frames, 3, 1) != 1) return 14;

    if (gcn_walk_guest_stack(sp, nullptr, &ram, frames, 3) != 0) return 15;
    if (gcn_walk_guest_stack(sp, fake_read, &ram, nullptr, 3) != 0) return 16;
    if (!gcn_guest_ram_holds(0x80000000u)) return 17;
    if (gcn_guest_ram_holds(0x817FFFFCu + 4)) return 18;
    return 0;
}
