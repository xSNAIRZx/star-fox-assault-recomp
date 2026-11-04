#include "../runtime/gx/render_math.h"
#include <cmath>
#include <cstdio>
#include <limits>

int main() {
    int failures = 0;
    int check_id = 0;
    auto check = [&](bool condition) {
        if (!condition) { ++failures; std::printf("render_math_test: check %d failed\n", check_id); }
        ++check_id;
    };
    const float proj[7] = {1.2f, 0.0f, 1.3f, 0.0f, 0.5f, 1.0f, 0.0f};
    const float viewport[6] = {320.0f, 264.0f, 16777215.0f, 320.0f, 264.0f, 16777215.0f};
    const float vertices[9] = {-1.0f, -1.0f, -2.0f,
                                1.0f, -1.0f, -4.0f,
                               -1.0f,  1.0f, -3.0f};
    float narrow[4], wide[4], stale[4];
    check(gx::zfreeze_plane_from_vertices(proj, viewport, vertices, 0, 0, 640, 528, 2.5f, 1.0f, narrow));
    check(gx::zfreeze_plane_from_vertices(proj, viewport, vertices, 0, 0, 640, 528, 2.5f, 0.75f, wide));
    check(gx::zfreeze_plane_from_vertices(proj, viewport, vertices, 0, 0, 640, 528, 2.5f, 1.0f, stale));

    // Evaluate the fitted depth at an interior barycentric point. The plane must match the
    // projected triangle for each aspect, including the smaller, corrected screen X span.
    auto projected = [&](int i, float aspect, double& x, double& y, double& z) {
        const float* v = vertices + i * 3;
        const double cw = -v[2];
        const double cx = aspect * (proj[0] * v[0] + proj[1] * v[2]);
        const double cy = proj[2] * v[1] + proj[3] * v[2];
        const double cz = proj[4] * v[2] + proj[5];
        const double ndcx = (2.0 * viewport[3] / 640.0 - 1.0) +
                            (2.0 * viewport[0] / 640.0) * cx / cw;
        const double ndcy = (2.0 * viewport[4] / 528.0 - 1.0) + (2.0 * viewport[1] / 528.0) * cy / cw;
        const double ndcz = (2.0 * viewport[5] / 16777215.0 - 1.0) +
                            (2.0 * viewport[2] / 16777215.0) * cz / cw;
        x = (ndcx + 1.0) * 0.5 * 640.0 * 2.5;
        y = (-ndcy + 1.0) * 0.5 * 528.0 * 2.5;
        z = (ndcz + 1.0) * 0.5;
    };
    double x[3], y[3], z[3];
    for (int i = 0; i < 3; i++) projected(i, 1.0f, x[i], y[i], z[i]);
    double tx = 0.2 * x[0] + 0.3 * x[1] + 0.5 * x[2];
    double ty = 0.2 * y[0] + 0.3 * y[1] + 0.5 * y[2];
    double expected = 0.2 * z[0] + 0.3 * z[1] + 0.5 * z[2];
    check(std::fabs(narrow[0] * tx + narrow[1] * ty + narrow[2] - expected) < 1e-6);

    for (int i = 0; i < 3; i++) projected(i, 0.75f, x[i], y[i], z[i]);
    tx = 0.2 * x[0] + 0.3 * x[1] + 0.5 * x[2];
    ty = 0.2 * y[0] + 0.3 * y[1] + 0.5 * y[2];
    expected = 0.2 * z[0] + 0.3 * z[1] + 0.5 * z[2];
    const double reconstructed = wide[0] * tx + wide[1] * ty + wide[2];
    const double stale_reconstructed = stale[0] * tx + stale[1] * ty + stale[2];
    check(std::fabs(reconstructed - expected) < 1e-6);
    check(std::fabs(stale_reconstructed - expected) > 1e-5);
    check(std::fabs(wide[0]) > std::fabs(narrow[0]));
    check(wide[3] == 1.0f && narrow[3] == 1.0f);

    // Ortho z-freeze receives the same X transform as apply_state, while its depth stays fixed.
    const float ortho[7] = {0.003125f, -1.0f, -0.0045f, 1.0f, 0.0f, -1.0f, 1.0f};
    const float ortho_vertices[9] = {0.0f, 0.0f, 0.0f, 320.0f, 0.0f, 0.0f, 0.0f, 224.0f, 0.0f};
    float ortho_plane[4];
    check(gx::zfreeze_plane_from_vertices(ortho, viewport, ortho_vertices, 0, 0, 640, 528, 1.0f, 0.75f, ortho_plane));
    check(ortho_plane[3] == 1.0f);
    const float degenerate[9] = {-1.0f, -1.0f, -2.0f,
                                  1.0f, -1.0f, -4.0f,
                                  1.0f, -1.0f, -4.0f};
    check(!gx::zfreeze_plane_from_vertices(proj, viewport, degenerate, 0, 0, 640, 528, 2.5f, 0.75f, ortho_plane));
    // Invalid input or overflowing projection arithmetic must not replace the
    // previous frame's valid plane with NaNs/Infinities. Exercise every input
    // component, including the projection tag which used to be cast to int.
    auto rejected_unchanged = [&](const float* p, const float* vp, const float* pos,
                                  int width = 640, int height = 528, float scale = 1.0f,
                                  float aspect = 1.0f) {
        float plane[4] = {1.0f, 2.0f, 3.0f, 4.0f};
        check(!gx::zfreeze_plane_from_vertices(p, vp, pos, 0, 0, width, height, scale, aspect, plane));
        check(plane[0] == 1.0f && plane[1] == 2.0f && plane[2] == 3.0f && plane[3] == 4.0f);
    };
    for (float bad : {std::numeric_limits<float>::quiet_NaN(),
                      std::numeric_limits<float>::infinity(),
                      -std::numeric_limits<float>::infinity()}) {
        for (int i = 0; i < 7; i++) {
            float p[7]; std::copy(proj, proj + 7, p); p[i] = bad;
            rejected_unchanged(p, viewport, vertices);
        }
        for (int i = 0; i < 6; i++) {
            float vp[6]; std::copy(viewport, viewport + 6, vp); vp[i] = bad;
            rejected_unchanged(proj, vp, vertices);
        }
        for (int i = 0; i < 9; i++) {
            float pos[9]; std::copy(vertices, vertices + 9, pos); pos[i] = bad;
            rejected_unchanged(proj, viewport, pos);
        }
        rejected_unchanged(proj, viewport, vertices, 640, 528, bad);
        rejected_unchanged(proj, viewport, vertices, 640, 528, 1.0f, bad);
    }
    rejected_unchanged(proj, viewport, vertices, 0);
    rejected_unchanged(proj, viewport, vertices, 640, -1);
    rejected_unchanged(proj, viewport, vertices, 640, 528, 0.0f);
    rejected_unchanged(proj, viewport, vertices, 640, 528, -1.0f);
    float overflowing[9]; std::copy(vertices, vertices + 9, overflowing);
    overflowing[0] = std::numeric_limits<float>::max();
    rejected_unchanged(proj, viewport, overflowing);
    std::printf("render_math_test: %d failures\n", failures);
    return failures ? 1 : 0;
}
