#include "nanlm/head_page_checkpoint.hpp"
#include "test_util.hpp"

#include <filesystem>
#include <fstream>
#include <vector>

using namespace nanlm;

namespace {
std::vector<std::uint8_t> page(std::uint8_t lane) {
    std::vector<std::uint8_t> data(HeadPageCheckpoint::kPageBytes, 0);
    const std::uint32_t magic = 0x48315233u;
    for (unsigned i = 0; i < 4; ++i)
        data[0xFCC00 + i] = static_cast<std::uint8_t>(magic >> (8 * i));
    data[0x100] = lane;
    return data;
}
} // namespace

int main() {
    const auto dir = std::filesystem::path("state") /
        "benchmarks" / "head_page_checkpoint_test";
    std::filesystem::remove_all(dir);
    {
        HeadPageCheckpoint store(dir);
        const auto p0 = page(3);
        const auto p1 = page(7);
        store.write_page(0, p0.data(), p0.size(), 11);
        store.write_page(254, p1.data(), p1.size(), 12);
        CHECK_EQ(store.page_count(), 2u);
        CHECK(store.record(0).generation == 11u);
        CHECK_EQ(store.record(0).sha256.size(), 64u);
        CHECK(!store.root_digest().empty());

        std::vector<std::uint8_t> out;
        CHECK(store.read_page(0, out));
        CHECK(out == p0);
        CHECK(store.read_page(254, out));
        CHECK(out == p1);
        std::string error;
        CHECK(store.verify_all(&error));
        CHECK(error.empty());
    }
    {
        HeadPageCheckpoint reloaded(dir);
        CHECK_EQ(reloaded.page_count(), 2u);
        std::vector<std::uint8_t> out;
        CHECK(reloaded.read_page(0, out));
        CHECK(out == page(3));

        // Corrupt one page; verification and reads must fail closed.
        auto bad = page(3);
        bad[0x100] ^= 0xFFu;
        {
            std::ofstream out_file(reloaded.page_path(0),
                                   std::ios::binary | std::ios::trunc);
            out_file.write(reinterpret_cast<const char*>(bad.data()),
                           static_cast<std::streamsize>(bad.size()));
        }
        std::string error;
        CHECK(!reloaded.verify_all(&error));
        CHECK(!error.empty());
        CHECK(!reloaded.read_page(0, out));

        // A page without the canonical header is rejected before write.
        auto no_header = page(1);
        no_header[0xFCC00] = 0;
        bool rejected = false;
        try {
            reloaded.write_page(1, no_header.data(), no_header.size(), 13);
        } catch (const std::invalid_argument&) {
            rejected = true;
        }
        CHECK(rejected);
    }
    std::filesystem::remove_all(dir);
    return test_done("persistent head-page checkpoint store");
}
