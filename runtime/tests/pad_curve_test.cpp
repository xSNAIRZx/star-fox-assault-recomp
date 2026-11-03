#include "../runtime/pad_curve.h"
#include <cmath>
#include <cstdio>

// The built-in controller path's deadzone, without a controller: the maths a stick goes
// through between the SDL axis and the pad's byte (pad_curve.h).
int main() {
    int failures = 0;
    auto check = [&](bool value) { if (!value) ++failures; };
    auto near = [&](double a, double b) { return std::fabs(a - b) < 1e-4; };

    // Percent to fraction, and clamping outside the accepted range.
    check(near(padc::deadzone_fraction(0), 0.0));
    check(near(padc::deadzone_fraction(10), 0.1));
    check(near(padc::deadzone_fraction(40), 0.4));
    check(near(padc::deadzone_fraction(60), 0.4));
    check(near(padc::deadzone_fraction(-5), 0.0));

    // A stick at rest, inside the circle, stays where it is: the caller leaves the pad
    // alone so the keyboard can still drive it.
    auto p = padc::apply_radial_deadzone(0.0, 0.0, 0.1f);
    check(p.x == 0.0 && p.y == 0.0);
    p = padc::apply_radial_deadzone(0.05, 0.05, 0.1f);  // length 0.0707
    check(p.x == 0.0 && p.y == 0.0);
    p = padc::apply_radial_deadzone(0.1, 0.0, 0.1f);  // exactly on the edge
    check(p.x == 0.0 && p.y == 0.0);

    // With no deadzone the position passes through unchanged.
    p = padc::apply_radial_deadzone(0.5, -0.25, 0.0f);
    check(near(p.x, 0.5) && near(p.y, -0.25));

    // Past the circle the remaining travel is spread over the full range.
    p = padc::apply_radial_deadzone(0.2, 0.0, 0.1f);
    check(near(p.x, 1.0 / 9.0) && near(p.y, 0.0));

    // A diagonal push and a straight one of the same length now answer the same, which the
    // per-axis threshold did not do.
    auto straight = padc::apply_radial_deadzone(0.2, 0.0, 0.1f);
    auto diagonal = padc::apply_radial_deadzone(0.2 / std::sqrt(2.0), 0.2 / std::sqrt(2.0), 0.1f);
    check(near(std::hypot(straight.x, straight.y), std::hypot(diagonal.x, diagonal.y)));

    // Leaving the circle is a small step, not a jump.
    p = padc::apply_radial_deadzone(0.1001, 0.0, 0.1f);
    check(std::hypot(p.x, p.y) < 0.01);

    // The direction holds at every distance, and full deflection still reads as full.
    p = padc::apply_radial_deadzone(0.3, 0.4, 0.1f);  // length 0.5, direction 3:4
    check(near(std::hypot(p.x, p.y), (0.5 - 0.1) / 0.9));
    check(near(p.y / p.x, 0.4 / 0.3));
    p = padc::apply_radial_deadzone(1.0, 0.0, 0.1f);
    check(near(std::hypot(p.x, p.y), 1.0) && p.x > 0.0);

    // A square-cornered pair (both axes at full) is held at 1 instead of overflowing.
    p = padc::apply_radial_deadzone(1.0, 1.0, 0.0f);
    check(near(std::hypot(p.x, p.y), 1.0));
    check(near(p.y / p.x, 1.0));

    // Up is positive before this conversion, so a pushed-up axis stays up in the byte.
    check(padc::axis_to_byte(0.0) == 128);
    check(padc::axis_to_byte(1.0) == 228);
    check(padc::axis_to_byte(-1.0) == 28);
    check(padc::axis_to_byte(0.5) == 178);
    check(padc::axis_to_byte(2.0) == 255);
    check(padc::axis_to_byte(-2.0) == 0);
    check(padc::axis_to_byte(std::nan("")) == 128);

    std::printf("pad_curve_test: %d failures\n", failures);
    return failures ? 1 : 0;
}
