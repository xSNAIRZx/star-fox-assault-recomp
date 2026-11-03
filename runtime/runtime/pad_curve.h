#pragma once
#include <cmath>
#include <cstdint>

// Radial stick shaping for the first game controller (main.cpp). A controls.txt binding
// carries its own deadzone (input_map.h), but a pad no binding names has no file entry to
// hold one, so its deadzone comes from --deadzone=<percent> instead. Before that option
// existed the built-in path compared each axis against a fixed threshold (4000/32767 on
// the stick, 1000 on the C stick) and then passed the raw axis through, which made a
// diagonal push need more travel than a straight one and made the first movement past the
// threshold a jump the size of the threshold rather than a step.
namespace padc {

// A stick position in -1 to 1 per axis, y up.
struct Position {
    double x = 0.0, y = 0.0;
};

// `percent` (0 to 40) as the fraction of travel that reads as nothing. Out of range values
// are clamped here; main.cpp decides what to accept from the command line.
inline float deadzone_fraction(int percent) {
    if (percent <= 0) return 0.0f;
    if (percent > 40) percent = 40;
    return (float)percent / 100.0f;
}

// The position with a radial deadzone applied: anything inside a circle of radius `dz` is
// at rest, and the travel that is left is spread over the full range, so the first movement
// past the circle is small and full deflection still reaches 1. A push past the circle's
// edge keeps its direction, and one beyond the unit circle (a square-cornered axis pair)
// is held at 1 rather than overflowing the pad's byte.
inline Position apply_radial_deadzone(double x, double y, float dz) {
    const double m = std::sqrt(x * x + y * y);
    if (!(m > 0.0)) return {};  // rest, and a NaN axis, both leave the stick where it was
    const double capped = m > 1.0 ? 1.0 : m;
    if (dz >= 1.0f || capped <= dz) return {};
    const double travel = (capped - dz) / (1.0 - dz);
    const double scale = travel / m;  // by the true length, so the direction is kept
    return {x * scale, y * scale};
}

// -1 to 1 onto the pad's byte: 128 at rest and 100 of travel to either side, which is how
// the runtime has always written this axis.
inline uint8_t axis_to_byte(double v) {
    if (!(v == v)) return 128;  // NaN: rest, not an undefined cast
    const int r = 128 + static_cast<int>(v * 100.0);
    return static_cast<uint8_t>(r < 0 ? 0 : r > 255 ? 255 : r);
}

}  // namespace padc
