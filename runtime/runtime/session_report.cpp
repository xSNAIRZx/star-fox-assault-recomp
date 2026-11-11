#include "session_report.h"

#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>

#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#define GCN_SESSION_CPUID 1
#if defined(_MSC_VER)
#include <intrin.h>
static void cpuid(unsigned leaf, unsigned r[4]) {
    int v[4];
    __cpuid(v, (int)leaf);
    for (int i = 0; i < 4; i++) r[i] = (unsigned)v[i];
}
#else
#include <cpuid.h>
static void cpuid(unsigned leaf, unsigned r[4]) { __cpuid(leaf, r[0], r[1], r[2], r[3]); }
#endif
#endif

namespace session_report {
namespace {

using Clock = std::chrono::steady_clock;

constexpr double kSummaryEverySeconds = 30.0;
constexpr double kHitchFrameMs = 50.0;  // what render_report_frame calls a stall

// Frame times in 1 ms buckets, the last holding everything longer. A game may run at 60 or
// at 30 from one screen to the next, so a fixed "slow" threshold miscounts one or the other;
// the median says what rate it held and the 99th percentile how evenly.
constexpr int kBuckets = 256;

struct Window {
    uint64_t frames = 0;
    uint64_t hitches = 0;
    double worst_ms = 0.0;
    uint32_t hist[kBuckets] = {};
    void add(double ms) {
        frames++;
        if (ms > kHitchFrameMs) hitches++;
        if (ms > worst_ms) worst_ms = ms;
        const int b = ms < 0.0 ? 0 : ms >= kBuckets - 1 ? kBuckets - 1 : (int)ms;
        hist[b]++;
    }
    // The bucket holding the given fraction of frames, as its upper edge in ms.
    int percentile_ms(double fraction) const {
        const uint64_t want = (uint64_t)(fraction * frames);
        uint64_t seen = 0;
        for (int b = 0; b < kBuckets; b++) {
            seen += hist[b];
            if (seen > want) return b + 1;
        }
        return kBuckets;
    }
};

std::mutex g_lock;
std::string g_power = "unknown";
int g_power_percent = -1;
bool g_have_last = false;
Clock::time_point g_start, g_window_start, g_last;
Window g_window, g_total;
bool g_finished = false;

std::string power_text() {
    if (g_power_percent < 0) return g_power;
    return g_power + " " + std::to_string(g_power_percent) + "%";
}

void vnote(const char* fmt, va_list ap) {
    std::fputs("[session] ", stdout);
    std::vfprintf(stdout, fmt, ap);
    std::fputc('\n', stdout);
    std::fflush(stdout);
}

void print_window(const char* label, const Window& w, double seconds) {
    const double fps = seconds > 0.0 ? w.frames / seconds : 0.0;
    note("%s %.0fs: %.1f fps; frame ms median <=%d, 99%% <=%d, longest %.0f; %llu over %.0f ms; power %s",
         label, seconds, fps, w.percentile_ms(0.5), w.percentile_ms(0.99), w.worst_ms,
         (unsigned long long)w.hitches, kHitchFrameMs, power_text().c_str());
}

std::string cpu_brand() {
#ifdef GCN_SESSION_CPUID
    unsigned r[4] = {};
    cpuid(0x80000000u, r);
    if (r[0] < 0x80000004u) return "";
    char brand[49] = {};
    for (unsigned i = 0; i < 3; i++) {
        cpuid(0x80000002u + i, r);
        std::memcpy(brand + i * 16, r, 16);
    }
    const char* s = brand;
    while (*s == ' ') s++;
    std::string out = s;
    while (!out.empty() && out.back() == ' ') out.pop_back();
    return out;
#else
    return "";
#endif
}

}  // namespace

void note(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vnote(fmt, ap);
    va_end(ap);
}

void machine(const char* platform, int logical_cpus, int ram_mb) {
    const std::string brand = cpu_brand();
    note("machine: %s, cpu %s, %d logical threads, %d MB RAM", platform ? platform : "unknown",
         brand.empty() ? "unknown" : brand.c_str(), logical_cpus, ram_mb);
}

void set_power(const char* state, int percent) {
    std::lock_guard<std::mutex> hold(g_lock);
    const std::string next = state ? state : "unknown";
    // A battery's percentage moves all the time; only the source is worth a line.
    const bool changed = next != g_power;
    g_power = next;
    g_power_percent = percent;
    if (changed) note("power: %s", power_text().c_str());
}

void frame_presented() {
    std::lock_guard<std::mutex> hold(g_lock);
    const auto now = Clock::now();
    if (!g_have_last) {
        g_have_last = true;
        g_start = g_window_start = g_last = now;
        return;
    }
    const double ms = std::chrono::duration<double, std::milli>(now - g_last).count();
    g_last = now;
    g_window.add(ms);
    g_total.add(ms);
    const double seconds = std::chrono::duration<double>(now - g_window_start).count();
    if (seconds >= kSummaryEverySeconds) {
        print_window("frames, last", g_window, seconds);
        g_window = {};
        g_window_start = now;
    }
}

void finish() {
    std::lock_guard<std::mutex> hold(g_lock);
    if (g_finished) return;
    g_finished = true;
    if (!g_have_last) {
        note("no frames shown");
        return;
    }
    print_window("session total, over", g_total,
                 std::chrono::duration<double>(g_last - g_start).count());
}

}  // namespace session_report
