#pragma once
#include <cstddef>
#include <cstdint>

// Host output gain only; the guest DSP/mixer and recorded samples retain their values.
inline void audio_apply_output_gain(int16_t* samples, size_t count, unsigned percent) {
    if (percent >= 100) return;
    const int32_t gain = static_cast<int32_t>(percent);
    for (size_t i = 0; i < count; ++i)
        samples[i] = static_cast<int16_t>(static_cast<int32_t>(samples[i]) * gain / 100);
}
