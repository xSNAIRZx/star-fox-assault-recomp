#include "disc_image.h"

#include <algorithm>
#include <array>
#include <cstring>

namespace disc_image {
namespace {

constexpr uint32_t kCisoHeaderSize = 0x8000;
constexpr size_t kCisoMapEntries = kCisoHeaderSize - 8;
constexpr uint32_t kGameCubeMagic = 0xC2339F3D;

uint32_t read_be32(const uint8_t* p) {
    return (static_cast<uint32_t>(p[0]) << 24) | (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8) | static_cast<uint32_t>(p[3]);
}

std::string json_escape(const std::string& value) {
    std::string escaped;
    escaped.reserve(value.size() + 2);
    for (unsigned char c : value) {
        switch (c) {
        case '"': escaped += "\\\""; break;
        case '\\': escaped += "\\\\"; break;
        case '\b': escaped += "\\b"; break;
        case '\f': escaped += "\\f"; break;
        case '\n': escaped += "\\n"; break;
        case '\r': escaped += "\\r"; break;
        case '\t': escaped += "\\t"; break;
        default:
            if (c < 0x20) {
                constexpr char hex[] = "0123456789abcdef";
                escaped += "\\u00";
                escaped += hex[c >> 4];
                escaped += hex[c & 0x0f];
            } else {
                escaped += static_cast<char>(c);
            }
        }
    }
    return escaped;
}

}  // namespace

bool Reader::open(Source source, std::string& error) {
    source_ = source;
    format_ = Format::Iso;
    ciso_block_size_ = 0;
    ciso_map_.clear();
    if (!source_.read_at || !source_.context) {
        error = "image source is unavailable";
        return false;
    }
    std::array<uint8_t, 4> signature{};
    if ((!source_.physical_size || source_.physical_size >= signature.size()) &&
        source_.read_at(source_.context, 0, signature.data(), static_cast<uint32_t>(signature.size())) &&
        std::memcmp(signature.data(), "CISO", 4) == 0) {
        if (source_.physical_size && source_.physical_size < kCisoHeaderSize) {
            error = "CISO header is truncated";
            return false;
        }
        std::array<uint8_t, kCisoHeaderSize> header{};
        if (!source_.read_at(source_.context, 0, header.data(), static_cast<uint32_t>(header.size()))) {
            error = "cannot read CISO header";
            return false;
        }
        ciso_block_size_ = static_cast<uint32_t>(header[4]) |
                           (static_cast<uint32_t>(header[5]) << 8) |
                           (static_cast<uint32_t>(header[6]) << 16) |
                           (static_cast<uint32_t>(header[7]) << 24);
        if (ciso_block_size_ == 0) {
            error = "CISO block size is zero";
            return false;
        }
        ciso_map_.assign(static_cast<size_t>(kCisoMapEntries), -1);
        int32_t stored = 0;
        for (size_t i = 0; i < kCisoMapEntries; ++i) {
            const uint8_t entry = header[8 + i];
            if (entry > 1) {
                error = "CISO block map contains an invalid entry";
                ciso_map_.clear();
                ciso_block_size_ = 0;
                return false;
            }
            if (entry == 1) ciso_map_[i] = stored++;
        }
        const uint64_t payload_bytes = static_cast<uint64_t>(stored) * ciso_block_size_;
        if (source_.physical_size && payload_bytes > source_.physical_size - kCisoHeaderSize) {
            error = "CISO block data is truncated";
            ciso_map_.clear();
            ciso_block_size_ = 0;
            return false;
        }
        format_ = Format::Ciso;
    }
    error.clear();
    return true;
}

bool Reader::read(uint64_t offset, void* destination, uint32_t length) const {
    if (!source_.read_at || !source_.context || (!destination && length)) return false;
    if (format_ == Format::Iso) {
        if (source_.physical_size &&
            (offset > source_.physical_size || length > source_.physical_size - offset)) return false;
        return source_.read_at(source_.context, offset, destination, length);
    }
    auto* output = static_cast<uint8_t*>(destination);
    while (length) {
        const uint64_t block = offset / ciso_block_size_;
        const uint32_t in_block = static_cast<uint32_t>(offset % ciso_block_size_);
        const uint32_t count = std::min<uint32_t>(length, ciso_block_size_ - in_block);
        const int32_t stored = block < ciso_map_.size() ? ciso_map_[static_cast<size_t>(block)] : -1;
        if (stored < 0) {
            std::memset(output, 0, count);
        } else {
            const uint64_t file_offset = kCisoHeaderSize + static_cast<uint64_t>(stored) * ciso_block_size_ + in_block;
            if ((source_.physical_size &&
                 (file_offset > source_.physical_size || count > source_.physical_size - file_offset)) ||
                !source_.read_at(source_.context, file_offset, output, count)) return false;
        }
        offset += count;
        output += count;
        length -= count;
    }
    return true;
}

bool inspect(const Reader& reader, Info& info, std::string& error) {
    std::array<uint8_t, 0x440> header{};
    if (!reader.read(0, header.data(), static_cast<uint32_t>(header.size()))) {
        error = "disc image is truncated or unreadable";
        return false;
    }
    if (read_be32(header.data() + 0x1c) != kGameCubeMagic) {
        error = "image does not contain a valid GameCube disc header";
        return false;
    }
    info.game_id.assign(reinterpret_cast<const char*>(header.data()), 6);
    if (info.game_id != "GF7E01") {
        error = "disc is not Star Fox Assault (expected game ID GF7E01)";
        return false;
    }
    info.internal_name.assign(reinterpret_cast<const char*>(header.data() + 0x20), 0x20);
    while (!info.internal_name.empty() &&
           (info.internal_name.back() == '\0' || info.internal_name.back() == ' '))
        info.internal_name.pop_back();
    info.region = header[3] == 'E' ? "USA" : header[3] == 'P' ? "Europe" : header[3] == 'J' ? "Japan" : "Unknown";
    info.revision = header[7];
    info.format = reader.format();
    info.size_bytes = reader.physical_size();
    error.clear();
    return true;
}

const char* format_name(Format format) { return format == Format::Ciso ? "CISO" : "ISO"; }

std::string to_json(const Info& info) {
    return std::string("{\"valid\":true,\"game_id\":\"") + json_escape(info.game_id) +
           "\",\"internal_name\":\"" + json_escape(info.internal_name) + "\",\"region\":\"" +
           json_escape(info.region) + "\",\"revision\":" + std::to_string(info.revision) +
           ",\"format\":\"" + format_name(info.format) + "\",\"size_bytes\":" +
           std::to_string(info.size_bytes) + "}";
}

}  // namespace disc_image
