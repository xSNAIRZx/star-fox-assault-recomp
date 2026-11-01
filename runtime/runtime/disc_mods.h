#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace disc_mods {

// Loads a directory overlay from the game FST. Files must have the exact on-disc size;
// the FST is never rewritten. A null/empty directory disables mods.
bool init(const char* directory, const uint8_t* fst, size_t fst_size, std::string& error);
void clear();

// Replace the overlapping portions of an already completed image read. Safe for
// concurrent calls after init() returns. Returns false if an overlay becomes unreadable.
bool apply(uint64_t disc_offset, void* data, uint32_t length);
size_t count();

} // namespace disc_mods
