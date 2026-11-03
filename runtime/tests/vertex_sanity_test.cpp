#include "../runtime/vertex_sanity.h"

#include <string.h>

// A 3-float position followed by a filler float, so the stride is exercised rather than
// assumed to be one vertex after another.
struct FakeVertex {
    float pos[3];
    float aux;
};

int main() {
    if (!gcn_float_is_finite(0.0f)) return 1;
    if (!gcn_float_is_finite(-1234.5f)) return 2;
    if (gcn_float_is_finite(0.0f / 0.0f)) return 3;              // NaN
    if (gcn_float_is_finite(1.0f / 0.0f)) return 4;              // +inf
    if (gcn_float_is_finite(-1.0f / 0.0f)) return 5;             // -inf
    // A denormal and the largest finite value are still positions.
    if (!gcn_float_is_finite(1e-45f)) return 6;
    if (!gcn_float_is_finite(3.4028234e38f)) return 7;

    FakeVertex v[4] = {};
    v[0].pos[0] = 1; v[0].pos[1] = 2; v[0].pos[2] = 3;
    v[1].pos[0] = 1; v[1].pos[1] = 2; v[1].pos[2] = 3;
    v[2].pos[0] = 1; v[2].pos[1] = 2; v[2].pos[2] = 3;
    v[3].pos[0] = 1; v[3].pos[1] = 2; v[3].pos[2] = 3;

    const size_t stride = sizeof(FakeVertex) / sizeof(float);
    if (stride != 4) return 8;
    if (gcn_count_non_finite_positions(&v[0].pos[0], stride, 4) != 0) return 9;

    // One bad component in one vertex, in each of the three positions.
    v[1].pos[1] = 0.0f / 0.0f;
    if (gcn_count_non_finite_positions(&v[0].pos[0], stride, 4) != 1) return 10;
    v[1].pos[1] = 1;
    v[2].pos[2] = 1.0f / 0.0f;
    if (gcn_count_non_finite_positions(&v[0].pos[0], stride, 4) != 1) return 11;
    v[2].pos[2] = 2;
    v[3].pos[0] = -1.0f / 0.0f;
    if (gcn_count_non_finite_positions(&v[0].pos[0], stride, 4) != 1) return 12;
    v[3].pos[0] = 3;

    // A guard on the arguments: no base, or a stride that is not a vertex.
    if (gcn_count_non_finite_positions(nullptr, stride, 4) != 0) return 13;
    if (gcn_count_non_finite_positions(&v[0].pos[0], 2, 4) != 0) return 14;

    // The matrix that produced them.
    float m[12] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0};
    if (gcn_matrix_has_non_finite(m, 12)) return 15;
    m[7] = 0.0f / 0.0f;
    if (!gcn_matrix_has_non_finite(m, 12)) return 16;
    m[7] = 0;
    if (gcn_matrix_has_non_finite(nullptr, 12)) return 17;

    char note[192];
    if (gcn_vertex_check_note(30, 0, false, note, sizeof note)) return 18;   // nothing wrong
    if (!gcn_vertex_check_note(30, 12, false, note, sizeof note)) return 19;
    if (!strstr(note, "12 of 30")) return 20;
    if (!strstr(note, "matrix is finite")) return 21;
    if (!gcn_vertex_check_note(30, 30, true, note, sizeof note)) return 22;
    if (!strstr(note, "all 30")) return 23;
    if (!strstr(note, "matrix is not finite")) return 24;
    if (gcn_vertex_check_note(30, 12, false, nullptr, 0)) return 25;
    return 0;
}
