#include "../runtime/disc_mods.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#ifdef _WIN32
#include <process.h>
static int process_id() { return _getpid(); }
#else
#include <unistd.h>
static int process_id() { return getpid(); }
#endif

namespace fs = std::filesystem;

static void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

static void put_be32(std::vector<uint8_t>& data, size_t at, uint32_t value) {
    data[at] = static_cast<uint8_t>(value >> 24);
    data[at + 1] = static_cast<uint8_t>(value >> 16);
    data[at + 2] = static_cast<uint8_t>(value >> 8);
    data[at + 3] = static_cast<uint8_t>(value);
}

static std::vector<uint8_t> make_fst(const std::string& file_name, uint32_t file_offset, uint32_t file_size,
                                     bool nested = true, const std::string& directory_name = "data") {
    std::vector<uint8_t> strings{0};
    auto add_name = [&strings](const std::string& value) {
        const uint32_t offset = static_cast<uint32_t>(strings.size());
        strings.insert(strings.end(), value.begin(), value.end());
        strings.push_back(0);
        return offset;
    };
    const uint32_t dir_name = add_name(directory_name);
    const uint32_t file_name_offset = add_name(file_name);
    const uint32_t missing_name_offset = nested ? add_name("missing.bin") : 0;
    const uint32_t count = nested ? 4 : 2;
    const size_t strings_at = static_cast<size_t>(count) * 12;
    std::vector<uint8_t> fst(strings_at + strings.size(), 0);
    put_be32(fst, 0, 0x01000000);
    put_be32(fst, 4, 0);
    put_be32(fst, 8, count);
    if (nested) {
        put_be32(fst, 12, 0x01000000 | dir_name);
        put_be32(fst, 16, 0);
        put_be32(fst, 20, 3);
        put_be32(fst, 24, file_name_offset);
        put_be32(fst, 28, file_offset);
        put_be32(fst, 32, file_size);
        put_be32(fst, 36, missing_name_offset);
        put_be32(fst, 40, 300);
        put_be32(fst, 44, 4);
    } else {
        put_be32(fst, 12, file_name_offset);
        put_be32(fst, 16, file_offset);
        put_be32(fst, 20, file_size);
    }
    std::copy(strings.begin(), strings.end(), fst.begin() + strings_at);
    return fst;
}

static void write_file(const fs::path& path, const std::string& bytes) {
    fs::create_directories(path.parent_path());
    std::ofstream out(path, std::ios::binary);
    out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    require(static_cast<bool>(out), "failed to create synthetic mod file");
}

int main() {
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    const fs::path root = fs::temp_directory_path() /
        ("gcn-disc-mods-test-" + std::to_string(process_id()) + "-" + std::to_string(stamp));
    try {
        require(fs::create_directory(root), "could not create unique temporary directory");
        const fs::path mods = root / "mods";
        write_file(mods / "data" / "texture.bin", "ABCDEFGH");
        std::string error;

        const std::vector<uint8_t> fst = make_fst("texture.bin", 100, 8);
        require(disc_mods::init(mods.string().c_str(), fst.data(), fst.size(), error), "valid exact-size mod was rejected");
        require(disc_mods::count() == 1, "expected one replacement file");

        std::vector<uint8_t> partial(15, 'x');
        require(disc_mods::apply(95, partial.data(), static_cast<uint32_t>(partial.size())), "partial disc read failed");
        const std::string expected = "xxxxxABCDEFGHxx";
        require(std::string(partial.begin(), partial.end()) == expected, "overlay did not replace only the intersecting bytes");

        std::vector<uint8_t> inside(3, 'x');
        require(disc_mods::apply(103, inside.data(), static_cast<uint32_t>(inside.size())), "interior disc read failed");
        require(std::string(inside.begin(), inside.end()) == "DEF", "partial replacement offset was incorrect");

        write_file(mods / "data" / "texture.bin", "TOO-SMALL");
        require(!disc_mods::init(mods.string().c_str(), fst.data(), fst.size(), error), "wrong-size replacement was accepted");
        require(error.find("disc file") != std::string::npos && error.find("replacement") != std::string::npos,
                "size rejection did not report both sizes");
        require(error.find("disc-mods.md") != std::string::npos,
                "size rejection did not point at the documented override limit");
        require(disc_mods::count() == 0, "failed initialization left replacements active");

        const std::vector<uint8_t> traversal = make_fst("../escape.bin", 100, 8, false);
        write_file(mods / "escape.bin", "12345678");
        require(!disc_mods::init(mods.string().c_str(), traversal.data(), traversal.size(), error), "traversal filename was accepted");

        write_file(mods / "code.rel", "12345678");
        const std::vector<uint8_t> rel = make_fst("code.rel", 100, 8, false);
        require(!disc_mods::init(mods.string().c_str(), rel.data(), rel.size(), error), "REL replacement was accepted");
        write_file(mods / "code.dol", "12345678");
        const std::vector<uint8_t> dol = make_fst("code.dol", 100, 8, false);
        require(!disc_mods::init(mods.string().c_str(), dol.data(), dol.size(), error), "DOL replacement was accepted");
        write_file(mods / "sys" / "boot.bin", "12345678");
        const std::vector<uint8_t> system_file = make_fst("boot.bin", 100, 8, true, "sys");
        require(!disc_mods::init(mods.string().c_str(), system_file.data(), system_file.size(), error), "system-file replacement was accepted");

        const fs::path outside = root / "outside";
        write_file(outside / "asset.bin", "OUTSIDE!");
        std::error_code symlink_error;
        fs::create_symlink(outside / "asset.bin", mods / "link.bin", symlink_error);
        if (!symlink_error) {
            const std::vector<uint8_t> linked = make_fst("link.bin", 100, 8, false);
            require(!disc_mods::init(mods.string().c_str(), linked.data(), linked.size(), error), "symlink replacement was accepted");
        }

        disc_mods::clear();
        fs::remove_all(root);
        std::cout << "disc_mods_test: exact-size, partial reads, missing-file ignore, size rejection, traversal, system and code-file rejection"
                  << (symlink_error ? " passed (symlink creation unavailable)\n" : " and symlink rejection passed\n");
        return 0;
    } catch (const std::exception& e) {
        disc_mods::clear();
        std::error_code ignored;
        fs::remove_all(root, ignored);
        std::cerr << "disc_mods_test: " << e.what() << '\n';
        return 1;
    }
}
