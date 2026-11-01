#include "../../runtime/disc_image.h"

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <string>

namespace {

struct FileSource {
    std::ifstream file;
    uint64_t size = 0;
};

bool read_at(void* context, uint64_t offset, void* destination, uint32_t length) {
    auto& source = *static_cast<FileSource*>(context);
    if (offset > source.size || length > source.size - offset ||
        offset > static_cast<uint64_t>(std::numeric_limits<std::streamoff>::max())) return false;
    source.file.clear();
    source.file.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
    if (!source.file) return false;
    source.file.read(static_cast<char*>(destination), static_cast<std::streamsize>(length));
    return source.file.gcount() == static_cast<std::streamsize>(length);
}

int usage() {
    std::cerr << "usage: assault-image-tool --inspect-image=<path>\n";
    return 2;
}

}  // namespace

template <typename Char>
int run(int argc, Char** argv) {
    if (argc != 2) return usage();
    constexpr Char prefix[] = {static_cast<Char>('-'), static_cast<Char>('-'), static_cast<Char>('i'),
                               static_cast<Char>('n'), static_cast<Char>('s'), static_cast<Char>('p'),
                               static_cast<Char>('e'), static_cast<Char>('c'), static_cast<Char>('t'),
                               static_cast<Char>('-'), static_cast<Char>('i'), static_cast<Char>('m'),
                               static_cast<Char>('a'), static_cast<Char>('g'), static_cast<Char>('e'),
                               static_cast<Char>('=')};
    const std::basic_string<Char> argument(argv[1]);
    if (argument.compare(0, std::size(prefix), prefix, std::size(prefix)) != 0 ||
        argument.size() == std::size(prefix)) return usage();
    const std::filesystem::path path(argument.substr(std::size(prefix)));

    std::error_code ec;
    const uint64_t size = std::filesystem::file_size(path, ec);
    if (ec || size == 0) {
        std::cerr << "cannot read image file size\n";
        return 1;
    }
    FileSource source;
    source.size = size;
    source.file.open(path, std::ios::binary);
    if (!source.file) {
        std::cerr << "cannot open image\n";
        return 1;
    }

    disc_image::Reader reader;
    std::string error;
    if (!reader.open({&source, size, read_at}, error)) {
        std::cerr << error << "\n";
        return 1;
    }
    disc_image::Info info;
    if (!disc_image::inspect(reader, info, error)) {
        std::cerr << error << "\n";
        return 1;
    }
    std::cout << disc_image::to_json(info) << "\n";
    return 0;
}

#if defined(_WIN32)
int wmain(int argc, wchar_t** argv) { return run(argc, argv); }
#else
int main(int argc, char** argv) { return run(argc, argv); }
#endif
