#pragma once
// A short account of the session on stdout, always on, for the log a player attaches to a
// report: the machine, the GL driver, the settings in effect, the shader cache, and how
// steadily frames came. Every line starts "[session]" and is flushed as it is written, so
// a log cut short by a crash or a kill still holds everything up to that point.
//
// stdout, not stderr: a launcher that keeps the two in separate files, and a report tool
// that attaches only one of them, most often takes stdout. The diagnostics that go to
// stderr stay there; the lines here repeat only what a report needs.
//
// Free of SDL and GL, like the rest of the core: a frontend hands over what it reads from
// either.

#include <cstdint>

namespace session_report {

// One "[session] ..." line on stdout, flushed.
void note(const char* fmt, ...)
#if defined(__GNUC__) || defined(__clang__)
    __attribute__((format(printf, 1, 2)))
#endif
    ;

// The host's processor, logical thread count and memory, and the platform's name.
void machine(const char* platform, int logical_cpus, int ram_mb);

// Where the power comes from, which a laptop's clocks follow. `state` is a short word
// ("battery", "charging", "charged", "mains", "unknown"); `percent` < 0 when unknown.
// Printed at once when it changes, and with each frame summary.
void set_power(const char* state, int percent);

// Call once per frame shown on screen. Every 30 seconds it prints how the frames since the
// last summary went: the average rate, the longest frame, and how many frames took longer
// than 20 ms (under 50 fps) and 50 ms (a visible hitch).
void frame_presented();

// The whole session's figures, printed once, at a normal exit.
void finish();

}  // namespace session_report
