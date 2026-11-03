// Entry point and SDL frontend: window, input, audio. The main thread executes GX
// batches produced by the guest thread.
#include "runtime.h"
#include "platform.h"
#include "input_script.h"
#include "input_log.h"
#include "input_map.h"
#include "gx/render_gl.h"
#include "gx/gl.h"
#include "hw/pad.h"
#include "vr_game.h"
#include "telemetry.h"
#include "record.h"
#ifdef GCN_OPENXR
#include "xr_desktop.h"
#endif
#ifdef _WIN32
// Console app: keep our own main() rather than SDL2main's WinMain shim.
#define SDL_MAIN_HANDLED
#endif
#include <SDL.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <ctime>
#include <string>
#include <thread>
#include <vector>
#include "pad_curve.h"

uint32_t boot_load(const char* iso_path);
void debug_dump_threads();
void debug_sampler_start();
bool write_png(const char* path, const uint8_t* rgba, int w, int h);

// ---------------------------------------------------------------------------
// --eye renders through the stereo path into an offscreen target and shows that in the
// window instead of the flat frame: the eye sits where the game's camera is, looking
// straight ahead with a 90 degree field, so a VR change can be looked at here before it
// goes anywhere near a headset. --first-person puts the eye wherever the game project's
// eye hook says (render_set_first_person), on the player's vehicle for a racing game.
// --dump-dir/--dump-every write the eye's frames as PNGs.
// ---------------------------------------------------------------------------
static bool g_eye_mode = false;
static bool g_toggle_display_aspect = false;
static GLuint g_eye_fbo, g_eye_tex, g_eye_depth;
static const int kEyeW = 960, kEyeH = 720;
// The game's VR settings (eye_init), for the eye's planes and the HUD frame's placement.
static VrConfig g_eye_cfg;

static void eye_init() {
    glGenTextures(1, &g_eye_tex);
    glBindTexture(GL_TEXTURE_2D, g_eye_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, kEyeW, kEyeH, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glGenRenderbuffers(1, &g_eye_depth);
    glBindRenderbuffer(GL_RENDERBUFFER, g_eye_depth);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, kEyeW, kEyeH);
    glGenFramebuffers(1, &g_eye_fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, g_eye_fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_eye_tex, 0);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, g_eye_depth);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) fatal("eye fbo incomplete");
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    // The game's VR settings as a headset would have them -- its defaults, then ./vr.txt --
    // so the preview shows what the game's hooks do: its world pitch, its depth layers and
    // what its eye filter leaves out.
    const VrConfig& c = g_eye_cfg = vr::load_config(".");
    gx::render_set_world_pitch(c.world_pitch_deg * 3.14159265f / 180.0f);
    gx::render_set_depth_layers(c.background_band, c.foreground_band, c.foreground_scale, c.hud_band, c.hud_band_scale);
    gx::render_set_hud_push(c.hud_push_below, c.hud_push_to);
    gx::render_set_view_space_world(c.view_space_world);
    gx::render_set_eye_filter(vr::game_hooks().eye_filter);
    gx::render_set_vr_morph(1.0f, nullptr);
}

// Column-major, as glUniformMatrix4fv takes them. The view is the identity: the eye is
// wherever the renderer's world transform puts it.
static void eye_matrices(float* proj, float* view, float* hud) {
    const float fov = 1.0f;   // tan(45 deg): a 90 degree vertical field
    const float aspect = (float)kEyeW / (float)kEyeH;
    const float u = g_eye_cfg.units_per_metre;
    const float n = g_eye_cfg.near_m * u, f = g_eye_cfg.far_m * u;
    memset(proj, 0, 16 * sizeof(float));
    proj[0] = 1.0f / (fov * aspect);
    proj[5] = 1.0f / fov;
    proj[10] = -(f + n) / (f - n);
    proj[11] = -1.0f;
    proj[14] = -(2.0f * f * n) / (f - n);
    memset(view, 0, 16 * sizeof(float));
    view[0] = view[5] = view[10] = view[15] = 1.0f;
    gx::render_hud_frame(g_eye_cfg.hud_distance_m * u, fov, g_eye_cfg.hud_scale, g_eye_cfg.hud_height_m * u,
                         g_eye_cfg.hud_pitch_deg * 3.14159265f / 180.0f, hud);
}

static void eye_dump(uint32_t n) {
    std::vector<uint8_t> px((size_t)kEyeW * kEyeH * 4), fl(px.size());
    glBindFramebuffer(GL_READ_FRAMEBUFFER, g_eye_fbo);
    glReadPixels(0, 0, kEyeW, kEyeH, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
    const size_t stride = (size_t)kEyeW * 4;
    for (int y = 0; y < kEyeH; y++) memcpy(&fl[y * stride], &px[(size_t)(kEyeH - 1 - y) * stride], stride);
    for (size_t i = 3; i < fl.size(); i += 4) fl[i] = 255;
    char path[512];
    snprintf(path, sizeof(path), "%s/eye_%05u.png", gx::g_dump_dir, n);
    write_png(path, fl.data(), kEyeW, kEyeH);
}

// Stringify, to quote the required GL version in a message without a format argument.
#define GCN_STR_(x) #x
#define GCN_STR(x) GCN_STR_(x)

static void on_interrupt() {
    // GCN_RAM_DUMP=<path>: the guest RAM at the interrupt, for reading the game's state offline.
    if (const char* path = getenv("GCN_RAM_DUMP")) {
        FILE* f = fopen(path, "wb");
        if (!f) perror("GCN_RAM_DUMP");
        else { fwrite(g_mem, 1, RAM_SIZE, f); fclose(f); fprintf(stderr, "RAM written to %s\n", path); }
    }
    plat_watchdog(2, 2);  // never hang in here (stdio locks may be held by other threads)
    input_log_end();
    input_map_shutdown();  // a wheel left pushing is a wheel pushing at nobody
    debug_dump_threads();
    plat_exit_now(1);
}

static void on_fault(const void* fault_addr, int code) {
    if (const char* path = getenv("GCN_RAM_DUMP")) {
        if (FILE* f = fopen(path, "wb")) { fwrite(g_mem, 1, RAM_SIZE, f); fclose(f); fprintf(stderr, "RAM written to %s\n", path); }
    }
    uintptr_t a = (uintptr_t)fault_addr;
    if (a >= (uintptr_t)g_mem && a < (uintptr_t)g_mem + 0x40000000)
        fprintf(stderr, "\nFAULT: guest memory access at (addr & 0x3FFFFFFF) = %08lX\n", (unsigned long)(a - (uintptr_t)g_mem));
    else
        fprintf(stderr, "\nFAULT: host address %p (code %d)\n", fault_addr, code);
    plat_watchdog(2, 2);
    input_log_end();
    input_map_shutdown();
    plat_backtrace_print();
    debug_dump_threads();
    plat_exit_now(1);
}

bool audio_open();
void audio_set_master_volume(unsigned percent);

// ---------------------------------------------------------------------------
// Input: keyboard + first game controller -> GC pad 1, and controls.txt (input_map.h)
// ---------------------------------------------------------------------------
static SDL_GameController* g_ctrl;
static bool g_script_only;
// --deadzone=<percent>, -1 until given. Only the built-in controller path uses it: a pad a
// controls.txt binding names keeps that binding's own deadzone (input_map.h).
static int g_deadzone_percent = -1;

static uint8_t axis_to_u8(int v, bool invert) {
    float f = v / 32767.0f;
    if (invert) f = -f;
    int r = 128 + (int)(f * 100.0f);
    return (uint8_t)std::clamp(r, 0, 255);
}

// The keyboard, the first game controller and controls.txt, merged into `p`: buttons are
// added, and a stick or trigger is taken over only while it is pushed, so that they can
// share the pad with a headset's controllers (xr_desktop.cpp).
static void merge_desktop_pad(PadState& p) {
    const uint8_t* k = SDL_GetKeyboardState(nullptr);
    if (k[SDL_SCANCODE_RETURN] && !k[SDL_SCANCODE_LALT] && !k[SDL_SCANCODE_RALT]) p.buttons |= PAD_START;
    if (k[SDL_SCANCODE_X]) p.buttons |= PAD_A;
    if (k[SDL_SCANCODE_Z]) p.buttons |= PAD_B;
    if (k[SDL_SCANCODE_C]) p.buttons |= PAD_X;
    if (k[SDL_SCANCODE_S]) p.buttons |= PAD_Y;
    if (k[SDL_SCANCODE_D]) p.buttons |= PAD_Z;
    if (k[SDL_SCANCODE_Q]) { p.buttons |= PAD_L; p.trig_l = 255; }
    if (k[SDL_SCANCODE_W]) { p.buttons |= PAD_R; p.trig_r = 255; }
    if (k[SDL_SCANCODE_I]) p.buttons |= PAD_UP;
    if (k[SDL_SCANCODE_K]) p.buttons |= PAD_DOWN;
    if (k[SDL_SCANCODE_J]) p.buttons |= PAD_LEFT;
    if (k[SDL_SCANCODE_L]) p.buttons |= PAD_RIGHT;
    int sx = 0, sy = 0;
    if (k[SDL_SCANCODE_LEFT]) sx -= 100;
    if (k[SDL_SCANCODE_RIGHT]) sx += 100;
    if (k[SDL_SCANCODE_UP]) sy += 100;
    if (k[SDL_SCANCODE_DOWN]) sy -= 100;
    if (sx || sy) {
        p.stick_x = (uint8_t)(128 + sx);
        p.stick_y = (uint8_t)(128 + sy);
    }
    if (g_ctrl) {
        auto b = [&](SDL_GameControllerButton btn) { return SDL_GameControllerGetButton(g_ctrl, btn); };
        if (b(SDL_CONTROLLER_BUTTON_A)) p.buttons |= PAD_A;
        if (b(SDL_CONTROLLER_BUTTON_X)) p.buttons |= PAD_B;
        if (b(SDL_CONTROLLER_BUTTON_B)) p.buttons |= PAD_X;
        if (b(SDL_CONTROLLER_BUTTON_Y)) p.buttons |= PAD_Y;
        if (b(SDL_CONTROLLER_BUTTON_START)) p.buttons |= PAD_START;
        if (b(SDL_CONTROLLER_BUTTON_RIGHTSHOULDER)) p.buttons |= PAD_Z;
        if (b(SDL_CONTROLLER_BUTTON_DPAD_UP)) p.buttons |= PAD_UP;
        if (b(SDL_CONTROLLER_BUTTON_DPAD_DOWN)) p.buttons |= PAD_DOWN;
        if (b(SDL_CONTROLLER_BUTTON_DPAD_LEFT)) p.buttons |= PAD_LEFT;
        if (b(SDL_CONTROLLER_BUTTON_DPAD_RIGHT)) p.buttons |= PAD_RIGHT;
        const int lx = SDL_GameControllerGetAxis(g_ctrl, SDL_CONTROLLER_AXIS_LEFTX);
        const int ly = SDL_GameControllerGetAxis(g_ctrl, SDL_CONTROLLER_AXIS_LEFTY);
        const int rx = SDL_GameControllerGetAxis(g_ctrl, SDL_CONTROLLER_AXIS_RIGHTX);
        const int ry = SDL_GameControllerGetAxis(g_ctrl, SDL_CONTROLLER_AXIS_RIGHTY);
        if (g_deadzone_percent >= 0) {
            // One circle for both sticks (pad_curve.h): a diagonal push no longer needs
            // more travel than a straight one, and the travel past the circle is spread
            // over the full range. A stick inside the circle is left alone, as any stick
            // at rest is, so the keyboard and the mappings still drive it.
            const float dz = padc::deadzone_fraction(g_deadzone_percent);
            const padc::Position l = padc::apply_radial_deadzone(lx / 32767.0, -ly / 32767.0, dz);
            const padc::Position r = padc::apply_radial_deadzone(rx / 32767.0, -ry / 32767.0, dz);
            if (l.x != 0.0 || l.y != 0.0) { p.stick_x = padc::axis_to_byte(l.x); p.stick_y = padc::axis_to_byte(l.y); }
            if (r.x != 0.0 || r.y != 0.0) { p.cstick_x = padc::axis_to_byte(r.x); p.cstick_y = padc::axis_to_byte(r.y); }
        } else {
            // No option: the fixed per-axis thresholds this path has always used.
            if (abs(lx) > 4000 || abs(ly) > 4000) { p.stick_x = axis_to_u8(lx, false); p.stick_y = axis_to_u8(ly, true); }
            if (abs(rx) > 1000 || abs(ry) > 1000) { p.cstick_x = axis_to_u8(rx, false); p.cstick_y = axis_to_u8(ry, true); }
        }
        int lt = SDL_GameControllerGetAxis(g_ctrl, SDL_CONTROLLER_AXIS_TRIGGERLEFT);
        int rt = SDL_GameControllerGetAxis(g_ctrl, SDL_CONTROLLER_AXIS_TRIGGERRIGHT);
        if (lt > 1000) { p.trig_l = std::max(p.trig_l, (uint8_t)(lt * 255 / 32767)); if (lt > 30000) p.buttons |= PAD_L; }
        if (rt > 1000) { p.trig_r = std::max(p.trig_r, (uint8_t)(rt * 255 / 32767)); if (rt > 30000) p.buttons |= PAD_R; }
    }
    input_map_apply(p);
    // The pad's rumble motor on the gamepad, renewed while it runs.
    static bool rumbling = false;
    const bool motor = pad_motor(0);
    if (g_ctrl && (motor || rumbling)) SDL_GameControllerRumble(g_ctrl, motor ? 0x6000 : 0, motor ? 0xA000 : 0, motor ? 200 : 0);
    rumbling = motor;
}

static void update_pad() {
    PadState p;
    p.connected = true;
    if (!g_script_only) merge_desktop_pad(p);
    input_script_apply(p);
    pad_set_state(0, p);
}

// The window's events. False once the user has asked to quit.
static bool pump_events() {
    SDL_Event e;
    bool running = true;
    while (SDL_PollEvent(&e)) {
        input_map_event(e);
        if (e.type == SDL_KEYDOWN && getenv("GCN_LOG_HOST_KEYS"))
            fprintf(stderr, "host-key: sym=%d scan=%d repeat=%d\n", e.key.keysym.sym, e.key.keysym.scancode, e.key.repeat);
        if (e.type == SDL_QUIT) running = false;
        else if (e.type == SDL_KEYDOWN &&
                 (e.key.keysym.sym == SDLK_F8 || e.key.keysym.scancode == SDL_SCANCODE_F8) && !e.key.repeat)
            g_toggle_display_aspect = true;
        else if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_RETURN &&
                 (e.key.keysym.mod & KMOD_ALT) && !e.key.repeat) {
            SDL_Window* window = SDL_GetWindowFromID(e.key.windowID);
            if (window) {
                const bool full = (SDL_GetWindowFlags(window) & SDL_WINDOW_FULLSCREEN) != 0;
                if (SDL_SetWindowFullscreen(window, full ? 0 : SDL_WINDOW_FULLSCREEN_DESKTOP) != 0)
                    fprintf(stderr, "fullscreen: %s\n", SDL_GetError());
            }
        }
        // A device controls.txt binds is the file's alone.
        else if (e.type == SDL_CONTROLLERDEVICEADDED && !g_ctrl && !input_map_binds_index(e.cdevice.which))
            g_ctrl = SDL_GameControllerOpen(e.cdevice.which);
        else if (e.type == SDL_KEYDOWN && e.key.keysym.scancode == SDL_SCANCODE_ESCAPE) running = false;
    }
    return running;
}

// ---------------------------------------------------------------------------
static bool parse_integer_option(const char* text, int low, int high, int& value) {
    char* end = nullptr;
    const long parsed = std::strtol(text, &end, 10);
    if (!*text || *end || parsed < low || parsed > high) return false;
    value = static_cast<int>(parsed);
    return true;
}

static void apply_display_toggle(gx::DisplayAspect& aspect, bool fxaa, bool sharp) {
    if (!g_toggle_display_aspect) return;
    g_toggle_display_aspect = false;
    aspect = aspect == gx::DisplayAspect::Widescreen ? gx::DisplayAspect::Original : gx::DisplayAspect::Widescreen;
    gx::render_set_display_options(aspect, fxaa, sharp);
    fprintf(stderr, "graphics: F8 aspect=%s\n", aspect == gx::DisplayAspect::Widescreen ? "widescreen" : "original");
}

int main(int argc, char** argv) {
    // The game resetting the console starts it again in a fresh process, as a power cycle
    // would -- except in a replay, which would only replay itself from the start again.
    static char** s_argv = argv;
    set_reset_handler([](uint32_t, uint32_t) {
        if (input_replay_active()) return;
        plat_relaunch(s_argv);
    });
    // Default: the image the build was configured with, else the first image in ./rom
    std::string iso_default = GCN_DEFAULT_ISO;
    if (!plat_readable(iso_default.c_str())) iso_default = plat_find_file("rom", ".iso");
    if (iso_default.empty()) iso_default = plat_find_file("rom", ".ciso");
    const char* iso = iso_default.c_str();
    bool headless = false, hidden = false, input_log = true, first_person = false, fast = false, vr = false;
    std::string input_log_dir, replay_dir;
    // --record=<file>[ --record-size=WxH]: a movie of the window with the game's audio (record.h).
    const char* record_to = nullptr;
    int record_w = 2560, record_h = 1440;
    const char* controls = "controls.txt";
    bool test_ffb = false;
    // --telemetry[=host:port]: the game's motion to a motion platform (telemetry.h).
    const char* telemetry_to = getenv("GCN_TELEMETRY");
    float scale = 2.0f;
    gx::DisplayAspect aspect = gx::DisplayAspect::Original;
    const char* aspect_name = "original";
    bool fxaa = false, test_graphics = false, sharp = true;
    int vsync = 0, volume = 100;
    bool fullscreen = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--log-all")) for (auto& e : g_log_enabled) e = true;
        else if (!strncmp(argv[i], "--log=", 6)) {
            if (!log_enable_list(argv[i] + 6)) { fprintf(stderr, "--log: unknown category in %s (cpu,os,hw,dvd,gx,vi,si,exi,dsp,ai,thr)\n", argv[i] + 6); return 1; }
        }
        else if (!strcmp(argv[i], "--eye")) g_eye_mode = true;
        else if (!strcmp(argv[i], "--vr")) vr = true;
        else if (!strcmp(argv[i], "--list-controls")) return input_map_probe();
        else if (!strcmp(argv[i], "--test-ffb")) test_ffb = true;
        else if (!strncmp(argv[i], "--controls=", 11)) controls = argv[i] + 11;
        else if (!strcmp(argv[i], "--telemetry")) telemetry_to = "";
        else if (!strncmp(argv[i], "--telemetry=", 12)) telemetry_to = argv[i] + 12;
        else if (!strcmp(argv[i], "--first-person")) first_person = true;
        else if (!strcmp(argv[i], "--no-input-log")) input_log = false;
        else if (!strncmp(argv[i], "--input-log=", 12)) input_log_dir = argv[i] + 12;
        else if (!strncmp(argv[i], "--replay=", 9)) replay_dir = argv[i] + 9;
        else if (!strcmp(argv[i], "--sample")) debug_sampler_start();
        else if (!strcmp(argv[i], "--no-music")) { void audio_mute_music(bool); audio_mute_music(true); }
        else if (!strncmp(argv[i], "--record=", 9)) record_to = argv[i] + 9;
        else if (!strncmp(argv[i], "--record-size=", 14)) sscanf(argv[i] + 14, "%dx%d", &record_w, &record_h);
        else if (!strcmp(argv[i], "--headless")) headless = true;
        else if (!strcmp(argv[i], "--hidden")) hidden = true;
        else if (!strcmp(argv[i], "--script-only")) g_script_only = true;
        else if (!strcmp(argv[i], "--fast")) fast = true;
        else if (!strcmp(argv[i], "--fullscreen")) fullscreen = true;
        else if (!strncmp(argv[i], "--vsync=", 8)) {
            if (!parse_integer_option(argv[i] + 8, 0, 1, vsync)) { fprintf(stderr, "--vsync expects 0 or 1\n"); return 1; }
        }
        else if (!strncmp(argv[i], "--volume=", 9)) {
            if (!parse_integer_option(argv[i] + 9, 0, 100, volume)) { fprintf(stderr, "--volume expects 0 to 100\n"); return 1; }
        }
        else if (!strcmp(argv[i], "--cull-swap")) gx::g_cull_swap = true;
        else if (!strncmp(argv[i], "--scale=", 8)) {
            char* end = nullptr;
            scale = strtof(argv[i] + 8, &end);
            if (end == argv[i] + 8 || *end || !std::isfinite(scale) ||
                (scale != 0.0f && (scale < 1.0f || scale > gx::kMaxInternalScale))) {
                fprintf(stderr, "--scale expects 0 (match window) or 1 to 8, including 1.5\n"); return 1;
            }
        }
        else if (!strncmp(argv[i], "--aspect=", 9)) {
            aspect_name = argv[i] + 9;
            if (!strcmp(aspect_name, "original")) aspect = gx::DisplayAspect::Original;
            else if (!strcmp(aspect_name, "widescreen")) aspect = gx::DisplayAspect::Widescreen;
            else if (!strcmp(aspect_name, "stretch")) aspect = gx::DisplayAspect::Stretch;
            else { fprintf(stderr, "--aspect expects original, widescreen or stretch\n"); return 1; }
        }
        else if (!strncmp(argv[i], "--aa=", 5)) {
            if (!strcmp(argv[i] + 5, "fxaa")) fxaa = true;
            else if (!strcmp(argv[i] + 5, "off")) fxaa = false;
            else { fprintf(stderr, "--aa expects off or fxaa\n"); return 1; }
        }
        else if (!strcmp(argv[i], "--test-graphics")) test_graphics = true;
        else if (!strncmp(argv[i], "--filter=", 9)) {
            if (!strcmp(argv[i] + 9, "sharp")) sharp = true;
            else if (!strcmp(argv[i] + 9, "smooth")) sharp = false;
            else { fprintf(stderr, "--filter expects sharp or smooth\n"); return 1; }
        }
        else if (!strncmp(argv[i], "--deadzone=", 11)) {
            if (!parse_integer_option(argv[i] + 11, 0, 40, g_deadzone_percent)) {
                fprintf(stderr, "--deadzone expects 0 to 40, the percent of stick travel that reads as nothing\n"); return 1;
            }
        }
        else if (!strncmp(argv[i], "--dump-dir=", 11)) gx::g_dump_dir = argv[i] + 11;
        else if (!strncmp(argv[i], "--dump-every=", 13)) gx::g_dump_every = atoi(argv[i] + 13);
        else if (argv[i][0] != '-') iso = argv[i];
    }
    if (test_ffb) return input_map_test_ffb(controls);
    plat_install_crash_handlers(on_interrupt, on_fault);
    if (record_to && !record::start(record_to, record_w, record_h, 60)) return 1;
    if (telemetry_to && !telemetry::configure(telemetry_to)) {
        fprintf(stderr, "--telemetry: could not set up the telemetry socket\n");
        return 1;
    }
#ifndef GCN_OPENXR
    if (vr) {
        fprintf(stderr, "--vr: this build has no OpenXR frontend (GCN_OPENXR is off, or this platform has none).\n");
        return 1;
    }
#endif

    if (!plat_readable(iso)) {
        fprintf(stderr, "No game image found. Put your " GCN_GAME_TITLE " .iso or .ciso in rom/ or pass its path.\n");
        return 1;
    }
    mem_init();
    timing_init();
    if (fast) clock_set_scale(0);  // run as fast as the host allows; the game sees 60 Hz regardless
    input_script_init();

    // Every run records what the guest read from the controller, so that a route to
    // wherever something went wrong can be played back with --replay=<dir>. See
    // input_log.h. --no-input-log turns it off; --input-log=<dir> names the directory.
    // The memory card is snapshotted into the log, and a replay runs on a scratch copy
    // of that snapshot rather than the real card.
    std::string replay_card;
    if (!replay_dir.empty()) {
        if (!input_replay_load(replay_dir, replay_card)) return 1;
        if (!replay_card.empty()) g_memcard_path = replay_card.c_str();
    }
    if (input_log) {
        if (input_log_dir.empty()) {
            char stamp[64];
            time_t now = time(nullptr);
            strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", localtime(&now));
            input_log_dir = std::string("saves/inputs/") + stamp;
        }
        input_log_start(input_log_dir, replay_card.empty() ? "saves/memcard_a.raw" : replay_card);
    }

    if (headless) {
        uint32_t entry = boot_load(iso);
        threads_start_boot(entry);
        for (;;) {
            PadState p;
            p.connected = true;
            input_script_apply(p);
            pad_set_state(0, p);
            auto b = gx::take_batch(5);  // discard
            (void)b;
        }
    }

#ifdef _WIN32
    SDL_SetMainReady();
#endif
    // Joysticks are read without the window's focus: in --vr the headset has it, and a
    // wheel or pedals have no reason to stop when another window is clicked.
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
#ifdef _WIN32
    // Render at the monitor's real pixel resolution rather than letting Windows
    // enlarge a low-resolution bitmap when desktop scaling is above 100 percent.
    SDL_SetHint(SDL_HINT_WINDOWS_DPI_AWARENESS, "permonitorv2");
    SDL_SetHint(SDL_HINT_WINDOWS_DPI_SCALING, "1");
#endif
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMECONTROLLER | SDL_INIT_HAPTIC) != 0) fatal("SDL_Init: %s", SDL_GetError());
    input_map_load(controls);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    const bool gl_debug = getenv("GCN_GL_DEBUG") != nullptr;
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG |
                                                  (gl_debug ? SDL_GL_CONTEXT_DEBUG_FLAG : 0));
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_Window* win = SDL_CreateWindow(GCN_APP_LABEL, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                       1280, aspect == gx::DisplayAspect::Widescreen ? 720 : 960,
                                       SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI |
                                       (hidden ? SDL_WINDOW_HIDDEN : 0) |
                                       (fullscreen && !hidden ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0));
    if (!win) fatal("SDL_CreateWindow: %s", SDL_GetError());
    // Ask for the newest core profile first: the renderer needs only GCN_GL_MAJOR.MINOR, but an
    // OpenXR runtime may want more of the context it shares (Meta's wants 4.0), and drivers
    // hand back exactly the version asked for.
    SDL_GLContext ctx = nullptr;
    static const int kTry[][2] = {{4, 6}, {4, 5}, {4, 3}, {4, 1}, {4, 0}};
    for (const auto& v : kTry) {
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, v[0]);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, v[1]);
        if ((ctx = SDL_GL_CreateContext(win))) break;
    }
    if (!ctx) {
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, GCN_GL_MAJOR);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, GCN_GL_MINOR);
        ctx = SDL_GL_CreateContext(win);
    }
    static const char* kGLHelp =
        "  The renderer needs an OpenGL " GCN_STR(GCN_GL_MAJOR) "." GCN_STR(GCN_GL_MINOR)
        " core profile. If this host only\n"
        "  offers legacy OpenGL (\"GDI Generic\" 1.1, typical for a VM with no GL driver),\n"
        "  install a GL implementation that provides it -- see docs/dev/graphics.md.";
    if (!ctx) fatal("SDL_GL_CreateContext: %s\n%s", SDL_GetError(), kGLHelp);
    if (SDL_GL_SetSwapInterval(vsync) != 0)
        fprintf(stderr, "vsync: requested interval %d unavailable: %s\n", vsync, SDL_GetError());
    fprintf(stderr, "display: %s, vsync=%d, volume=%d%%\n",
            (SDL_GetWindowFlags(win) & SDL_WINDOW_FULLSCREEN) ? "fullscreen" : "windowed",
            SDL_GL_GetSwapInterval(), volume);
    // A legacy driver still "loads": it resolves the GL 1.1 exports and leaves every
    // 2.0+ entry point null, so check the version before handing off to the renderer.
    int glver = gl_load_with(SDL_GL_GetProcAddress);
    if (glver < GCN_GL_VERSION_MIN) {
        fatal("OpenGL %d.%d is too old (got \"%s\" / \"%s\")\n%s",
              glver / 10, glver % 10, glGetString(GL_VERSION) ? (const char*)glGetString(GL_VERSION) : "?",
              glGetString(GL_RENDERER) ? (const char*)glGetString(GL_RENDERER) : "?", kGLHelp);
    }
    LOG(LOG_GX, "GL: %s / %s", glGetString(GL_RENDERER), glGetString(GL_VERSION));
    if (gl_debug) gl_debug_enable(SDL_GL_GetProcAddress);
    // Beside the memory card: both are state this machine accumulates for this game.
    plat_make_dirs("saves");
    gx::render_set_shader_cache("saves/shaders.bin");
#ifdef GCN_OPENXR
    // --vr: the headset takes over from here, the window staying up as a mirror.
    if (vr) {
        const int rc = xr_desktop_main({win, pump_events, merge_desktop_pad}, iso);
        record::finish();
        input_log_end();
        input_map_shutdown();
        threads_request_quit();
        plat_exit_now(rc);
    }
#endif
    int drawable_w, drawable_h;
    SDL_GL_GetDrawableSize(win, &drawable_w, &drawable_h);
    int window_w, window_h;
    SDL_GetWindowSize(win, &window_w, &window_h);
    fprintf(stderr, "display pixels: window=%dx%d drawable=%dx%d\n", window_w, window_h, drawable_w, drawable_h);
    float active_scale = scale == 0.0f ? gx::display_auto_scale(drawable_w, drawable_h, aspect) : scale;
    gx::render_set_display_options(aspect, fxaa, sharp);
    gx::render_init(active_scale);
    fprintf(stderr, "graphics: OpenGL, aspect=%s, aa=%s, filter=%s, scale=%.2f%s\n",
            aspect_name, fxaa ? "fxaa" : "off", sharp ? "sharp" : "smooth", active_scale,
            scale == 0.0f ? " (match window)" : "");
    if (test_graphics) {
        bool ok = gx::render_test_display_options();
        const auto before = aspect;
        SDL_Event key{};
        key.type = SDL_KEYDOWN;
        key.key.keysym.sym = SDLK_F8;
        key.key.keysym.scancode = SDL_SCANCODE_F8;
        for (int i = 0; i < 2; ++i) {
            SDL_PushEvent(&key);
            pump_events();
            ok = ok && g_toggle_display_aspect;
            apply_display_toggle(aspect, fxaa, sharp);
        }
        ok = ok && aspect == before;
        key.key.repeat = 1;
        SDL_PushEvent(&key);
        pump_events();
        ok = ok && !g_toggle_display_aspect;
        fprintf(stderr, "graphics-test: F8-event-roundtrip=%s\n", ok ? "PASS" : "FAIL");
        return ok ? 0 : 1;
    }
    if (g_eye_mode) eye_init();
    if (first_person) gx::render_set_first_person(true);
    if (gx::g_dump_dir) plat_make_dirs(gx::g_dump_dir);

    audio_set_master_volume(static_cast<unsigned>(volume));
    audio_open();

    uint32_t entry = boot_load(iso);
    threads_start_boot(entry);

    bool running = true;
    uint32_t frames = 0;
    const float theater_stereo_m = getenv("GCN_THEATER_STEREO") ? (float)atof(getenv("GCN_THEATER_STEREO")) : 0.0f;
    auto t0 = std::chrono::steady_clock::now();
    while (running) {
        running = pump_events();
        apply_display_toggle(aspect, fxaa, sharp);
        update_pad();
        int dw, dh;
        SDL_GL_GetDrawableSize(win, &dw, &dh);
        gx::render_set_window_size(dw, dh);
        auto b = gx::take_batch(4);
        if (!b) continue;
        if (scale == 0.0f) {
            int source_w, source_h;
            gx::render_get_display_size(source_w, source_h);
            const float next_scale = gx::display_auto_scale(dw, dh, aspect, source_w, source_h);
            if (next_scale != active_scale) {
                gx::render_set_internal_scale(next_scale);
                active_scale = next_scale;
                fprintf(stderr, "graphics: match window scale=%.2f\n", active_scale);
            }
        }
        // GCN_STEREOLOG=1: what the game's stereo hook (vr_game.h) would have a headset
        // show, whenever the answer changes, numbered as the frame dumps are.
        static const bool stereolog = getenv("GCN_STEREOLOG") != nullptr;
        if (stereolog && vr::game_hooks().wants_stereo) {
            static int last = -1;
            const int want = vr::game_hooks().wants_stereo(*b) ? 1 : 0;
            if (want != last) {
                last = want;
                fprintf(stderr, "[stereo] frame %u: %s\n", gx::present_count(), want ? "stereo" : "theater");
            }
        }
        bool presented;
        if (g_eye_mode) {
            float P[16], V[16], H[16];
            eye_matrices(P, V, H);
            gx::render_set_vr_eye(P, V, H);
            presented = gx::render_execute_eye(*b, g_eye_fbo, kEyeW, kEyeH, true);
            static uint32_t eye_frames = 0;
            eye_frames++;
            if (gx::g_dump_dir && gx::g_dump_every && eye_frames % gx::g_dump_every == 0) eye_dump(eye_frames);
            glBindFramebuffer(GL_READ_FRAMEBUFFER, g_eye_fbo);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
            glBlitFramebuffer(0, 0, kEyeW, kEyeH, 0, 0, dw, dh, GL_COLOR_BUFFER_BIT, GL_LINEAR);
        } else if (theater_stereo_m > 0.0f &&
                   (!vr::game_hooks().wants_panel_pair || vr::game_hooks().wants_panel_pair(*b))) {
            // GCN_THEATER_STEREO=<metres>: the flat frame as the stereo pair a headset
            // would hang on its panel, the eyes that far apart; the window shows the right
            // eye's, and the frame dumps come in pairs (_l, _r). The panel is the headset
            // frontend's, 3.2 m wide (kQuadW there), in the game's units. A frame the game
            // wants flat (wants_panel_pair) is drawn flat, as the headset does.
            static const float u = [] {
                VrConfig d;
                if (vr::game_hooks().config_defaults) vr::game_hooks().config_defaults(d);
                gx::render_set_panel_band(d.panel_band);
                return d.units_per_metre;
            }();
            presented = gx::render_execute_stereo_pair(*b, 0, 0, theater_stereo_m * u, 3.2f * u);
        } else {
            presented = gx::render_execute(*b);
        }
        if (presented) {
            // macOS (GL on Metal) only presents correctly with the window framebuffer bound.
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            if (record::active()) {
                int rw, rh;
                SDL_GL_GetDrawableSize(win, &rw, &rh);
                record::frame(0, rw, rh);
            }
            SDL_GL_SwapWindow(win);
            frames++;
            auto now = std::chrono::steady_clock::now();
            double secs = std::chrono::duration<double>(now - t0).count();
            if (secs >= 2.0) {
                char title[128];
                snprintf(title, sizeof(title), GCN_APP_LABEL " - %.1f fps", frames / secs);
                SDL_SetWindowTitle(win, title);
                frames = 0;
                t0 = now;
            }
        }
    }
    record::finish();
    input_log_end();
    input_map_shutdown();
    threads_request_quit();
    plat_exit_now(0);
}
