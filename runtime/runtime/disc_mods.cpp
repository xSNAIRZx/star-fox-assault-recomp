#include "disc_mods.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <system_error>
#include <vector>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif

namespace disc_mods {
namespace fs = std::filesystem;

struct Entry {
    uint64_t begin;
    uint64_t end;
    fs::path source;
};

static std::vector<Entry> g_entries;

static uint32_t read_be32(const uint8_t* p) {
    return (static_cast<uint32_t>(p[0]) << 24) | (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8) | p[3];
}

static bool is_link_or_reparse(const fs::path& path, std::error_code& ec) {
    const fs::file_status status = fs::symlink_status(path, ec);
    if (ec) return false;
    if (fs::is_symlink(status)) return true;
#ifdef _WIN32
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
#else
    return false;
#endif
}

static bool safe_component(const std::string& component) {
    return !component.empty() && component != "." && component != ".." &&
           component.find('/') == std::string::npos && component.find('\\') == std::string::npos &&
           component.find(':') == std::string::npos;
}

static bool supported_asset_path(const std::string& path) {
    std::string lower;
    lower.reserve(path.size());
    for (unsigned char c : path) lower.push_back(static_cast<char>(std::tolower(c)));
    if (lower.rfind("sys/", 0) == 0) return false;
    const size_t dot = lower.find_last_of('.');
    if (dot != std::string::npos) {
        const std::string extension = lower.substr(dot);
        if (extension == ".dol" || extension == ".rel") return false;
    }
    return true;
}

static bool path_is_within(const fs::path& root, const fs::path& candidate) {
    const fs::path relative = candidate.lexically_relative(root);
    if (relative.empty() || relative.is_absolute()) return false;
    for (const fs::path& part : relative) {
        if (part == "..") return false;
    }
    return true;
}

void clear() { g_entries.clear(); }

size_t count() { return g_entries.size(); }

bool init(const char* directory, const uint8_t* fst, size_t fst_size, std::string& error) {
    clear();
    error.clear();
    if (!directory || !*directory) return true;
    if (!fst || fst_size < 12 || fst_size > 64u * 1024u * 1024u) {
        error = "disc FST has an invalid size";
        return false;
    }

    std::error_code ec;
    const fs::path requested_root(directory);
    if (!fs::exists(requested_root, ec) || ec || !fs::is_directory(requested_root, ec) || ec) {
        error = "mods directory is missing or is not a directory";
        return false;
    }
    if (is_link_or_reparse(requested_root, ec) || ec) {
        error = "mods directory cannot be a symlink or reparse point";
        return false;
    }
    const fs::path root = fs::canonical(requested_root, ec);
    if (ec) {
        error = "cannot resolve mods directory";
        return false;
    }

    const uint32_t entry_count = read_be32(fst + 8);
    const uint64_t entries_bytes = static_cast<uint64_t>(entry_count) * 12;
    if (!entry_count || entries_bytes > fst_size ||
        (read_be32(fst) >> 24) != 1 || read_be32(fst + 4) != 0) {
        error = "disc FST root entry is malformed";
        return false;
    }
    const size_t strings_at = static_cast<size_t>(entries_bytes);

    struct Directory { uint32_t end; uint32_t index; std::string path; };
    std::vector<Directory> stack;
    stack.push_back({entry_count, 0, ""});
    std::vector<Entry> found;

    for (uint32_t i = 1; i < entry_count; ++i) {
        while (!stack.empty() && i >= stack.back().end) stack.pop_back();
        if (stack.empty()) {
            error = "disc FST directory ranges are malformed";
            return false;
        }
        const uint8_t* record = fst + static_cast<size_t>(i) * 12;
        const uint32_t type_name = read_be32(record);
        const bool is_directory = (type_name >> 24) != 0;
        const uint32_t name_offset = type_name & 0x00FFFFFFu;
        if (name_offset >= fst_size - strings_at) {
            error = "disc FST filename is outside the string table";
            return false;
        }
        const char* name = reinterpret_cast<const char*>(fst + strings_at + name_offset);
        const size_t remaining = fst_size - strings_at - name_offset;
        const void* nul = std::memchr(name, 0, remaining);
        if (!nul) {
            error = "disc FST filename is not terminated";
            return false;
        }
        const size_t name_length = static_cast<const char*>(nul) - name;
        const std::string component(name, name_length);
        if (!safe_component(component)) {
            error = "disc FST contains an unsafe path component";
            return false;
        }
        const std::string relative = stack.back().path.empty() ? component : stack.back().path + "/" + component;

        if (is_directory) {
            const uint32_t end = read_be32(record + 8);
            if (read_be32(record + 4) != stack.back().index || end <= i || end > stack.back().end) {
                error = "disc FST directory range is invalid";
                return false;
            }
            stack.push_back({end, i, relative});
            continue;
        }

        const uint64_t begin = read_be32(record + 4);
        const uint64_t size = read_be32(record + 8);
        if (!size || begin > std::numeric_limits<uint64_t>::max() - size) continue;
        const fs::path relative_path = fs::path(relative);
        const fs::path candidate = root / relative_path;

        fs::path current = root;
        bool missing = false;
        for (const fs::path& part : relative_path) {
            current /= part;
            const fs::file_status status = fs::symlink_status(current, ec);
            if (ec == std::errc::no_such_file_or_directory) {
                ec.clear();
                missing = true;
                break;
            }
            if (ec) {
                error = "cannot inspect mod path " + relative;
                return false;
            }
            if (status.type() == fs::file_type::not_found) {
                missing = true;
                break;
            }
            if (is_link_or_reparse(current, ec) || ec) {
                error = "mod path contains a symlink or reparse point: " + relative;
                return false;
            }
            (void)status;
        }
        if (missing) continue;

        const fs::path canonical_candidate = fs::canonical(candidate, ec);
        if (ec || !path_is_within(root, canonical_candidate)) {
            error = "mod path escapes the selected folder: " + relative;
            return false;
        }
        if (!fs::is_regular_file(canonical_candidate, ec) || ec) {
            error = "mod path is not a regular file: " + relative;
            return false;
        }
        if (!supported_asset_path(relative)) {
            error = "executable and system-file mods are not supported: " + relative;
            return false;
        }
        const uint64_t replacement_size = fs::file_size(canonical_candidate, ec);
        if (ec) {
            error = "cannot read the size of a replacement file: " + relative;
            return false;
        }
        if (replacement_size != size) {
            // The overlay is written at the original disc offset and the guest asks the disc
            // for the FST's length, so another size cannot be delivered here: a larger file
            // would move every file after it, and the read-only image cannot be repacked.
            // Higher-resolution art needs a container that carries its own sizes.
            error = "replacement size must match the disc file exactly: " + relative + " (disc file " +
                    std::to_string(size) + " bytes, replacement " + std::to_string(replacement_size) +
                    "); a larger asset cannot be placed at the original disc offset - see runtime/docs/disc-mods.md";
            return false;
        }
        found.push_back({begin, begin + size, canonical_candidate});
    }

    std::sort(found.begin(), found.end(), [](const Entry& a, const Entry& b) { return a.begin < b.begin; });
    for (size_t i = 1; i < found.size(); ++i) {
        if (found[i].begin < found[i - 1].end) {
            error = "two replacement files overlap on the disc";
            return false;
        }
    }
    g_entries = std::move(found);
    return true;
}

bool apply(uint64_t disc_offset, void* data, uint32_t length) {
    if (g_entries.empty() || !length) return true;
    if (!data) return false;
    if (disc_offset > std::numeric_limits<uint64_t>::max() - length) return false;
    const uint64_t read_end = disc_offset + length;
    uint8_t* out = static_cast<uint8_t*>(data);
    auto it = std::lower_bound(g_entries.begin(), g_entries.end(), disc_offset,
                               [](const Entry& entry, uint64_t offset) { return entry.end <= offset; });
    for (; it != g_entries.end() && it->begin < read_end; ++it) {
        const uint64_t overlap_begin = std::max(disc_offset, it->begin);
        const uint64_t overlap_end = std::min(read_end, it->end);
        const uint32_t overlap_size = static_cast<uint32_t>(overlap_end - overlap_begin);
        const uint64_t source_offset = overlap_begin - it->begin;
        std::ifstream source(it->source, std::ios::binary);
        if (!source) return false;
        source.seekg(static_cast<std::streamoff>(source_offset));
        if (!source) return false;
        source.read(reinterpret_cast<char*>(out + (overlap_begin - disc_offset)), overlap_size);
        if (source.gcount() != static_cast<std::streamsize>(overlap_size)) return false;
    }
    return true;
}

} // namespace disc_mods
