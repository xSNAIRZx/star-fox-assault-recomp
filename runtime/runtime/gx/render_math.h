#pragma once

#include <algorithm>
#include <cmath>

namespace gx {

// Fit the GX z-freeze plane to the last triangle in the same window coordinates used by
// gl_FragCoord. `positions` is three consecutive view-space XYZ positions.
inline bool zfreeze_plane_from_vertices(const float* p, const float* vp, const float* positions,
                                        int xoff, int yoff, int width, int height,
                                        float internal_scale, float aspect_x, float out[4]) {
    // A non-finite triangle cannot define a depth plane. Keep the caller's last
    // valid plane intact, just as for a degenerate triangle, instead of poisoning
    // every later z-freeze draw. In particular, do not cast an unchecked NaN
    // projection tag to int (undefined behavior in C++).
    if (width <= 0 || height <= 0 || !std::isfinite(internal_scale) || internal_scale <= 0.0f ||
        !std::isfinite(aspect_x)) return false;
    for (int i = 0; i < 7; i++) if (!std::isfinite(p[i])) return false;
    for (int i = 0; i < 6; i++) if (!std::isfinite(vp[i])) return false;
    for (int i = 0; i < 9; i++) if (!std::isfinite(positions[i])) return false;
    const bool perspective = p[6] == 0.0f;
    const float vpa[4] = {2.0f * (vp[3] - xoff) / width - 1.0f, 2.0f * vp[0] / width,
                          2.0f * (vp[4] - yoff) / height - 1.0f, 2.0f * vp[1] / height};
    const float far = std::min(vp[5], 16777215.0f);
    const float vpb[2] = {2.0f * far / 16777215.0f - 1.0f, 2.0f * vp[2] / 16777215.0f};
    double X[3], Y[3], Z[3];
    for (int i = 0; i < 3; i++) {
        const float* v = positions + i * 3;
        const float cx = perspective ? aspect_x * (p[0] * v[0] + p[1] * v[2])
                                     : aspect_x * (p[0] * v[0] + p[1]);
        const float cy = perspective ? p[2] * v[1] + p[3] * v[2] : p[2] * v[1] + p[3];
        const float cw = perspective ? -v[2] : 1.0f;
        const float cz = p[4] * v[2] + p[5];
        if (cw <= 0.0f) return false;
        const float px = vpa[0] * cw + vpa[1] * cx;
        const float py = vpa[2] * cw + vpa[3] * cy;
        const float pz = vpb[0] * cw + vpb[1] * cz;
        X[i] = (px / cw + 1.0) * 0.5 * width * internal_scale;
        Y[i] = (-py / cw + 1.0) * 0.5 * height * internal_scale;
        Z[i] = (pz / cw + 1.0) * 0.5;
        if (!std::isfinite(X[i]) || !std::isfinite(Y[i]) || !std::isfinite(Z[i])) return false;
    }
    const double ux = X[1] - X[0], uy = Y[1] - Y[0], uz = Z[1] - Z[0];
    const double wx = X[2] - X[0], wy = Y[2] - Y[0], wz = Z[2] - Z[0];
    const double det = ux * wy - uy * wx;
    if (std::fabs(det) < 1e-9) return false;
    const double a = (uz * wy - uy * wz) / det, b = (ux * wz - uz * wx) / det;
    const float plane[4] = {(float)a, (float)b, (float)(Z[0] - a * X[0] - b * Y[0]), 1.0f};
    for (int i = 0; i < 3; i++) if (!std::isfinite(plane[i])) return false;
    std::copy(plane, plane + 4, out);
    return true;
}

}  // namespace gx
