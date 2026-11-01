#include "../runtime/gx/display_options.h"
#include <cstdio>
int main() {
    using namespace gx;
    int failures = 0;
    auto check = [&](bool value) { if (!value) ++failures; };
    auto vp = display_viewport(1920, 1080, DisplayAspect::Original);
    check(vp.x == 240 && vp.y == 0 && vp.w == 1440 && vp.h == 1080);
    vp = display_viewport(1280, 1024, DisplayAspect::Widescreen);
    check(vp.x == 0 && vp.y == 152 && vp.w == 1280 && vp.h == 720);
    vp = display_viewport(1920, 1080, DisplayAspect::Stretch);
    check(vp.x == 0 && vp.y == 0 && vp.w == 1920 && vp.h == 1080);
    vp = display_viewport(0, 0, DisplayAspect::Original);
    check(vp.w == 1 && vp.h == 1);
    check(display_auto_scale(960, 720, DisplayAspect::Original) == 1.5f);
    check(display_auto_scale(640, 480, DisplayAspect::Original) == 1.0f);
    check(display_auto_scale(1280, 960, DisplayAspect::Original, 640, 448) == 2.5f);
    check(display_auto_scale(1920, 1080, DisplayAspect::Widescreen, 640, 448) == 3.0f);
    check(display_auto_scale(1920, 1080, DisplayAspect::Widescreen) == 3.0f);
    check(display_auto_scale(20000, 20000, DisplayAspect::Stretch) == 8.0f);
    check(display_projection_x(DisplayAspect::Original) == 1.0f);
    check(display_projection_x(DisplayAspect::Widescreen) == 0.75f);
    check(display_projection_x(DisplayAspect::Stretch) == 1.0f);
    check(display_draw_projection_x(DisplayAspect::Widescreen, true, false, false, true) == 0.75f);
    check(display_draw_projection_x(DisplayAspect::Widescreen, true, false, true, true) == 1.0f);
    check(display_draw_projection_x(DisplayAspect::Widescreen, false, false, false, true) == 0.75f);
    check(display_draw_projection_x(DisplayAspect::Widescreen, false, true, false, true) == 1.0f);
    check(display_draw_projection_x(DisplayAspect::Widescreen, false, false, false, false) == 1.0f);
    check(display_draw_projection_x(DisplayAspect::Widescreen, false, false, true, true) == 1.0f);
    check(display_draw_projection_x(DisplayAspect::Original, false, false, false, true) == 1.0f);
    check(display_frame_aspect(DisplayAspect::Widescreen, false, false) == DisplayAspect::Widescreen);
    check(display_frame_aspect(DisplayAspect::Widescreen, true, false) == DisplayAspect::Original);
    check(display_frame_aspect(DisplayAspect::Widescreen, true, true) == DisplayAspect::Widescreen);
    check(display_frame_aspect(DisplayAspect::Stretch, true, false) == DisplayAspect::Stretch);
    check(display_scissor_x(0.0f, 320.0f, 0.75f) == 80.0f);
    check(display_scissor_x(640.0f, 320.0f, 0.75f) == 560.0f);
    std::printf("display_options_test: %d failures\n", failures);
    return failures ? 1 : 0;
}
