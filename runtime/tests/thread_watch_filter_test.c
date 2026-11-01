#define GCN_THREAD_WATCH
#include "../runtime/recomp.h"

int main(void) {
    if (!gcn_thread_watch_store_might_overlap(0x800000E4u)) return 1;
    if (!gcn_thread_watch_store_might_overlap(0xC00000E4u)) return 2;
    if (!gcn_thread_watch_store_might_overlap(0x80000068u)) return 3;
    if (!gcn_thread_watch_store_might_overlap(0x800000E7u)) return 4;
    if (gcn_thread_watch_store_might_overlap(0xE00000E4u)) return 5;
    if (gcn_thread_watch_store_might_overlap(0x8038666Cu)) return 6;
    if (gcn_thread_watch_store_might_overlap(0x00000100u)) return 7;
    return 0;
}
