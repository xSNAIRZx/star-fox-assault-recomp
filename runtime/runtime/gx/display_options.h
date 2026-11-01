#pragma once
#include <algorithm>
#include <cmath>

namespace gx {
enum class DisplayAspect { Original, Widescreen, Stretch };
struct DisplayViewport { int x, y, w, h; };
inline DisplayViewport display_viewport(int width, int height, DisplayAspect aspect) {
    width = std::max(width, 1);
    height = std::max(height, 1);
    if (aspect == DisplayAspect::Stretch) return {0, 0, width, height};
    const int numerator = aspect == DisplayAspect::Widescreen ? 16 : 4;
    const int denominator = aspect == DisplayAspect::Widescreen ? 9 : 3;
    int w = width, h = std::max(1, width * denominator / numerator);
    if (h > height) { h = height; w = std::max(1, height * numerator / denominator); }
    return {(width - w) / 2, (height - h) / 2, w, h};
}
inline float display_auto_scale(int width, int height, DisplayAspect aspect,
                                int source_width = 640, int source_height = 480) {
    const auto vp = display_viewport(width, height, aspect);
    // Half steps avoid reallocating render targets for every pixel of a window drag.
    const float fit = std::max(vp.w / static_cast<float>(std::max(source_width, 1)),
                               vp.h / static_cast<float>(std::max(source_height, 1)));
    return std::clamp(std::ceil(fit * 2.0f) / 2.0f, 1.0f, 8.0f);
}
inline float display_projection_x(DisplayAspect aspect) {
    return aspect == DisplayAspect::Widescreen ? 0.75f : 1.0f;
}
inline float display_draw_projection_x(DisplayAspect aspect, bool perspective, bool fullscreen,
                                       bool offscreen, bool has_onscreen_perspective) {
    if (aspect != DisplayAspect::Widescreen || offscreen || !has_onscreen_perspective) return 1.0f;
    if (perspective) return display_projection_x(aspect);
    return fullscreen ? 1.0f : display_projection_x(aspect);
}
inline DisplayAspect display_frame_aspect(DisplayAspect requested, bool classified, bool has_onscreen_perspective) {
    return requested == DisplayAspect::Widescreen && classified && !has_onscreen_perspective
        ? DisplayAspect::Original : requested;
}
inline float display_scissor_x(float edge, float viewport_center, float scale) {
    return viewport_center + (edge - viewport_center) * scale;
}
}
