#include "../runtime/desktop_input.h"
#include <climits>
#include <cstdio>

int main() {
    int failures = 0, index = 0;
    auto check = [&](bool ok) { if (!ok) { ++failures; std::printf("desktop_input check %d failed\n", index); } ++index; };
    using namespace desktop_input;
    MouseState mouse;
    check(!mouse.captured && mouse.mode == MouseMode::Aim);
    PadState fired;
    apply_mouse_buttons(fired, true, false, false, mouse);
    check(fired.buttons == PAD_A && fired.trig_r == 0);
    mouse.captured = true; fired = {};
    apply_mouse_buttons(fired, true, false, false, mouse);
    check(fired.buttons == PAD_R && fired.trig_r == 255);
    fired = {}; mouse.mode = MouseMode::Flight;
    apply_mouse_buttons(fired, true, false, false, mouse);
    check(fired.buttons == PAD_A && fired.trig_r == 0);
    fired = {};
    apply_mouse_buttons(fired, false, true, true, mouse);
    check(fired.buttons == (PAD_B | PAD_X) && fired.trig_r == 0);
    fired = {};
    apply_mouse_buttons(fired, false, false, false, mouse);
    check(fired.buttons == 0 && fired.trig_r == 0);
    mouse = {};
    Keyboard keys;
    PadState pad;
    apply(pad, keys, mouse, INT_MAX, INT_MIN);
    check(pad.stick_x == 128 && pad.stick_y == 128 && pad.cstick_x == 128 && pad.cstick_y == 128);

    // The same movement channel used by WASD/arrow aliases never sends action buttons.
    keys.up = true;
    apply(pad, keys, mouse, 100, 100);
    check(pad.stick_x == 128 && pad.stick_y == 228 && pad.buttons == 0);
    keys = {}; keys.left = true; pad = {};
    apply(pad, keys, mouse, 0, 0);
    check(pad.stick_x == 28 && pad.stick_y == 128 && pad.buttons == 0);
    keys = {}; keys.down = true; keys.right = true; pad = {};
    apply(pad, keys, mouse, 0, 0);
    check(pad.stick_x == 228 && pad.stick_y == 28 && pad.buttons == 0);
    keys.left = true; keys.up = true; pad = {};
    apply(pad, keys, mouse, 0, 0);
    check(pad.stick_x == 128 && pad.stick_y == 128);

    // Walking and aiming stay independent. Mouse right/up means C-stick right/up.
    mouse.captured = true;
    keys = {}; keys.up = true; keys.left = true; pad = {};
    pad.buttons = PAD_A; pad.trig_l = 42;
    apply(pad, keys, mouse, 4, -5);
    check(pad.stick_x == 28 && pad.stick_y == 228);
    check(pad.cstick_x == 140 && pad.cstick_y == 143);
    check(pad.buttons == PAD_A && pad.trig_l == 42);
    keys = {}; pad = {};
    apply(pad, keys, mouse, INT_MIN, INT_MAX);
    check(pad.cstick_x == 28 && pad.cstick_y == 28 && pad.stick_x == 128 && pad.stick_y == 128);

    // A stationary mouse does not overwrite another input source's stick values.
    pad = {}; pad.cstick_x = 155; pad.cstick_y = 166;
    apply(pad, keys, mouse, 0, 0);
    check(pad.cstick_x == 155 && pad.cstick_y == 166);

    // Flight is an explicit mode toggle, not automatic guessed game-state detection.
    mouse.toggle_mode();
    check(mouse.mode == MouseMode::Flight && mouse.captured);
    keys.right = true; pad = {}; pad.cstick_x = 155; pad.cstick_y = 166;
    apply(pad, keys, mouse, -10, -8);
    check(pad.stick_x == 198 && pad.stick_y == 152);
    check(pad.cstick_x == 155 && pad.cstick_y == 166);
    keys = {}; pad = {};
    apply(pad, keys, mouse, INT_MAX, INT_MIN);
    check(pad.stick_x == 228 && pad.stick_y == 228);
    mouse.focus_lost();
    check(!mouse.captured && mouse.mode == MouseMode::Flight);
    pad = {}; keys.down = true;
    apply(pad, keys, mouse, INT_MAX, INT_MIN);
    check(pad.stick_x == 128 && pad.stick_y == 28 && pad.cstick_x == 128 && pad.cstick_y == 128);
    mouse.toggle_mode();
    check(!mouse.captured && mouse.mode == MouseMode::Aim);
    std::printf("desktop_input_test: %d checks, %d failures\n", index, failures);
    return failures ? 1 : 0;
}
