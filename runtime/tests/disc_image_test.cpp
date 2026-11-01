#include "../runtime/disc_image.h"

#include <algorithm>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

static bool read_memory(void* context, uint64_t offset, void* destination, uint32_t length) {
    const auto& bytes = *static_cast<const std::vector<uint8_t>*>(context);
    if (offset > bytes.size() || length > bytes.size() - static_cast<size_t>(offset)) return false;
    std::copy_n(bytes.data() + static_cast<size_t>(offset), length, static_cast<uint8_t*>(destination));
    return true;
}

static void put_be32(std::vector<uint8_t>& data, size_t offset, uint32_t value) {
    data[offset] = static_cast<uint8_t>(value >> 24);
    data[offset + 1] = static_cast<uint8_t>(value >> 16);
    data[offset + 2] = static_cast<uint8_t>(value >> 8);
    data[offset + 3] = static_cast<uint8_t>(value);
}

static void put_le32(std::vector<uint8_t>& data, size_t offset, uint32_t value) {
    data[offset] = static_cast<uint8_t>(value);
    data[offset + 1] = static_cast<uint8_t>(value >> 8);
    data[offset + 2] = static_cast<uint8_t>(value >> 16);
    data[offset + 3] = static_cast<uint8_t>(value >> 24);
}

static std::vector<uint8_t> make_disc() {
    std::vector<uint8_t> disc(0x8000, 0);
    const std::string id = "GF7E01";
    std::copy(id.begin(), id.end(), disc.begin());
    disc[7] = 2;
    const std::string name = "STAR FOX ASSAULT";
    std::copy(name.begin(), name.end(), disc.begin() + 0x20);
    put_be32(disc, 0x1c, 0xC2339F3D);
    return disc;
}

static disc_image::Reader open_reader(std::vector<uint8_t>& bytes, std::string& error) {
    disc_image::Reader reader;
    require(reader.open({&bytes, bytes.size(), read_memory}, error), error.c_str());
    return reader;
}

int main() {
    try {
        std::string error;
        auto iso = make_disc();
        auto iso_reader = open_reader(iso, error);
        disc_image::Info info;
        require(disc_image::inspect(iso_reader, info, error), error.c_str());
        require(info.game_id == "GF7E01", "ISO game ID was not read");
        require(info.internal_name == "STAR FOX ASSAULT", "ISO name was not trimmed");
        require(info.region == "USA" && info.revision == 2, "ISO region/revision mismatch");
        require(info.format == disc_image::Format::Iso && info.size_bytes == iso.size(), "ISO metadata mismatch");
        require(disc_image::to_json(info) ==
                "{\"valid\":true,\"game_id\":\"GF7E01\",\"internal_name\":\"STAR FOX ASSAULT\","
                "\"region\":\"USA\",\"revision\":2,\"format\":\"ISO\",\"size_bytes\":32768}",
                "JSON schema/output mismatch");

        constexpr uint32_t block_size = 0x8000;
        std::vector<uint8_t> ciso(0x8000 + block_size, 0);
        std::copy_n("CISO", 4, ciso.begin());
        put_le32(ciso, 4, block_size);
        ciso[8] = 1;
        std::copy(iso.begin(), iso.end(), ciso.begin() + 0x8000);
        auto ciso_reader = open_reader(ciso, error);
        require(disc_image::inspect(ciso_reader, info, error), error.c_str());
        require(info.format == disc_image::Format::Ciso && info.size_bytes == ciso.size(), "CISO metadata mismatch");
        std::vector<uint8_t> hole(16, 0xA5);
        require(ciso_reader.read(block_size, hole.data(), static_cast<uint32_t>(hole.size())), "CISO sparse read failed");
        require(std::all_of(hole.begin(), hole.end(), [](uint8_t value) { return value == 0; }),
                "CISO omitted block was not zero-filled");
        disc_image::Reader unknown_size_reader;
        require(unknown_size_reader.open({&ciso, 0, read_memory}, error), error.c_str());
        require(unknown_size_reader.format() == disc_image::Format::Ciso,
                "runtime-style unknown-size source did not detect CISO");
        std::vector<uint8_t> runtime_read(16, 0);
        require(unknown_size_reader.read(0, runtime_read.data(), static_cast<uint32_t>(runtime_read.size())) &&
                std::equal(runtime_read.begin(), runtime_read.end(), iso.begin()),
                "runtime-style unknown-size CISO read was incorrect");

        std::vector<uint8_t> short_ciso{'C', 'I', 'S', 'O'};
        disc_image::Reader bad_reader;
        require(!bad_reader.open({&short_ciso, short_ciso.size(), read_memory}, error), "truncated CISO was accepted");
        require(error == "CISO header is truncated", "truncated CISO returned an unexpected error");

        std::vector<uint8_t> truncated_payload(0x8000, 0);
        std::copy_n("CISO", 4, truncated_payload.begin());
        put_le32(truncated_payload, 4, block_size);
        truncated_payload[8] = 1;
        require(!bad_reader.open({&truncated_payload, truncated_payload.size(), read_memory}, error),
                "CISO with missing stored block data was accepted");
        require(error == "CISO block data is truncated", "truncated CISO payload returned an unexpected error");

        auto bad_map = std::vector<uint8_t>(0x8000, 0);
        std::copy_n("CISO", 4, bad_map.begin());
        put_le32(bad_map, 4, block_size);
        bad_map[8] = 2;
        require(!bad_reader.open({&bad_map, bad_map.size(), read_memory}, error), "invalid CISO map byte was accepted");

        auto wrong_id = make_disc();
        std::copy_n("GF7P01", 6, wrong_id.begin());
        auto wrong_id_reader = open_reader(wrong_id, error);
        require(!disc_image::inspect(wrong_id_reader, info, error), "nonmatching game ID was accepted");

        auto bad_magic = make_disc();
        put_be32(bad_magic, 0x1c, 0);
        auto bad_magic_reader = open_reader(bad_magic, error);
        require(!disc_image::inspect(bad_magic_reader, info, error), "invalid GameCube magic was accepted");

        std::vector<uint8_t> truncated_iso(32, 0);
        auto truncated_reader = open_reader(truncated_iso, error);
        require(!disc_image::inspect(truncated_reader, info, error), "truncated ISO was accepted");

        std::cout << "disc image inspection passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << "\n";
        return 1;
    }
}
