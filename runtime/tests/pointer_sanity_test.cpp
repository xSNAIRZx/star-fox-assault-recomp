#include "../runtime/pointer_sanity.h"

#include <string.h>

int main() {
    char note[128];

    // An ordinary guest pointer, inside main memory and aligned: nothing to report.
    if (gcn_word_pointer_note(0x8038666Cu, note, sizeof note)) return 1;
    if (gcn_word_pointer_note(0x800000E4u, note, sizeof note)) return 2;
    if (gcn_word_pointer_note(0x817FFFFCu, note, sizeof note)) return 3;

    // The value in the saved current-thread trace, named as the float it is.
    if (!gcn_word_pointer_note(0x3F000000u, note, sizeof note)) return 4;
    if (!strstr(note, "0.5")) return 5;

    // A null pointer, a misaligned pointer, the first word past RAM, and a float past it.
    if (!gcn_word_pointer_note(0u, note, sizeof note)) return 6;
    if (!strstr(note, "null")) return 7;
    if (!gcn_word_pointer_note(0x800000E2u, note, sizeof note)) return 8;
    if (!gcn_word_pointer_note(0x81800000u, note, sizeof note)) return 9;
    if (!gcn_word_pointer_note(0x40490FDBu, note, sizeof note)) return 10;  // pi
    if (!strstr(note, "3.14159")) return 11;
    // An infinity is not a stored value, so it is reported as a bad word without a float.
    if (!gcn_word_pointer_note(0x7F800000u, note, sizeof note)) return 12;
    if (strstr(note, "float")) return 13;

    float f = 0;
    if (!gcn_word_as_float(0x3F000000u, &f) || f != 0.5f) return 14;
    if (gcn_word_as_float(0x7F800000u, &f)) return 15;
    if (gcn_word_as_float(0x7FC00000u, &f)) return 16;  // NaN
    return 0;
}
