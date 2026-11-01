#include "../runtime/gx/texcoord.h"
#include <cmath>
#include <cstdio>

static bool near(float a, float b) {
    return std::fabs(a - b) < 0.000001f;
}

int main() {
    if (gx::texcoord_scale(0x000FFFFFu) != 65536.0f) {
        std::fprintf(stderr, "SU scale lost high size bits or included offset/wrap flags\n");
        return 1;
    }
    // The Assault font atlas uses texel-space vertex UVs with SU/TS size 1
    // (encoded as zero) on a 512x512 image.
    if (!near(gx::normalized_texcoord(288.0f, 0, 512.0f), 0.5625f) ||
        !near(gx::normalized_texcoord(24.0f, 0, 512.0f), 0.046875f)) {
        std::fprintf(stderr, "manual glyph coordinates did not normalize by image dimensions\n");
        return 1;
    }

    // Automatic scaling stores image size minus one; it must preserve ordinary
    // normalized coordinates, including a map/coordinate pair with other sizes.
    if (!near(gx::normalized_texcoord(0.5625f, 511, 512.0f), 0.5625f) ||
        !near(gx::normalized_texcoord(0.25f, 63, 64.0f), 0.25f)) {
        std::fprintf(stderr, "automatic texture coordinate scale changed normalized UVs\n");
        return 1;
    }

    return 0;
}
