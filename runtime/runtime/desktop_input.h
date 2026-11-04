#pragma once
#include "hw/pad.h"
#include <algorithm>
#include <cstdint>

// Desktop input expressed as ordinary GC pad controls. Mouse Aim drives the C-stick;
// the game's selected control type still decides what that stick does. Flight drives
// the main stick instead. Neither mode patches the guest camera or movement code.
namespace desktop_input {
enum class MouseMode { Aim, Flight };
struct MouseState {
    bool captured = false;
    MouseMode mode = MouseMode::Aim;
    void toggle_mode() { mode = mode == MouseMode::Aim ? MouseMode::Flight : MouseMode::Aim; }
    void focus_lost() { captured = false; }
};
struct Keyboard {
    bool left = false, right = false, up = false, down = false;
};
inline int limited_axis(int64_t value) {
    return static_cast<int>(std::clamp<int64_t>(value, -100, 100));
}
inline void apply_mouse_buttons(PadState& pad, bool left, bool right, bool middle, const MouseState& mouse) {
    // Dual-stick on-foot/Landmaster controls fire with R; Arwing fires with A.
    // Captured Aim therefore uses R. Free mouse/Flight use A so menus still work.
    if (left) {
        if (mouse.captured && mouse.mode == MouseMode::Aim) { pad.buttons |= PAD_R; pad.trig_r = 255; }
        else pad.buttons |= PAD_A;
    }
    if (right) pad.buttons |= PAD_B;
    if (middle) pad.buttons |= PAD_X;
}
inline void apply(PadState& pad, const Keyboard& keyboard, const MouseState& mouse, int dx, int dy) {
    int sx = 100 * (static_cast<int>(keyboard.right) - static_cast<int>(keyboard.left));
    int sy = 100 * (static_cast<int>(keyboard.up) - static_cast<int>(keyboard.down));
    // Widen before multiplication: an extreme host delta cannot wrap or overflow.
    const int64_t mx = mouse.captured ? int64_t(dx) * 3 : 0;
    const int64_t my = mouse.captured ? -int64_t(dy) * 3 : 0;
    if (mouse.mode == MouseMode::Flight) {
        sx = limited_axis(int64_t(sx) + mx);
        sy = limited_axis(int64_t(sy) + my);
    } else if (mx || my) {
        pad.cstick_x = static_cast<uint8_t>(128 + limited_axis(mx));
        pad.cstick_y = static_cast<uint8_t>(128 + limited_axis(my));
    }
    if (sx || sy) {
        pad.stick_x = static_cast<uint8_t>(128 + sx);
        pad.stick_y = static_cast<uint8_t>(128 + sy);
    }
}
} // namespace desktop_input
