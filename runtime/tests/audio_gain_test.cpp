#include "../runtime/audio_gain.h"
#include <array>
#include <cstdio>

int main() {
    const std::array<int16_t, 7> input{-32768, -10001, -1, 0, 1, 10001, 32767};
    auto output = input;
    audio_apply_output_gain(output.data(), output.size(), 100);
    if (output != input) return 1;
    audio_apply_output_gain(output.data(), output.size(), 50);
    const std::array<int16_t, 7> half{-16384, -5000, 0, 0, 0, 5000, 16383};
    if (output != half) {
        std::fprintf(stderr, "host gain corrupted signed PCM values\n");
        return 1;
    }
    audio_apply_output_gain(output.data(), output.size(), 0);
    if (output != std::array<int16_t, 7>{}) return 1;
    output = input;
    audio_apply_output_gain(output.data(), 0, 0);
    if (output != input) return 1;
    audio_apply_output_gain(output.data(), output.size(), 101);
    if (output != input) return 1;
    return 0;
}
