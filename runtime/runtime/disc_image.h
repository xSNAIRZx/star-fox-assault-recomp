#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace disc_image {

using ReadAt = bool (*)(void* context, uint64_t offset, void* destination, uint32_t length);

struct Source {
    void* context = nullptr;
    uint64_t physical_size = 0;
    ReadAt read_at = nullptr;
};

enum class Format { Iso, Ciso };

class Reader {
public:
    bool open(Source source, std::string& error);
    bool read(uint64_t offset, void* destination, uint32_t length) const;
    Format format() const { return format_; }
    uint64_t physical_size() const { return source_.physical_size; }

private:
    Source source_{};
    Format format_ = Format::Iso;
    uint32_t ciso_block_size_ = 0;
    std::vector<int32_t> ciso_map_;
};

struct Info {
    std::string game_id;
    std::string internal_name;
    std::string region;
    uint8_t revision = 0;
    Format format = Format::Iso;
    uint64_t size_bytes = 0;
};

bool inspect(const Reader& reader, Info& info, std::string& error);
std::string to_json(const Info& info);
const char* format_name(Format format);

}  // namespace disc_image
