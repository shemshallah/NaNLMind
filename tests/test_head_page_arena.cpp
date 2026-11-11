#include "nanlm/head_page_arena.hpp"
#include "test_util.hpp"
#include <array>

using namespace nanlm;

int main() {
    HeadPageArena arena;
    CHECK(arena.valid());
    CHECK_EQ(HeadPageArena::kHeadCount, 255u);
    CHECK_EQ(HeadPageArena::kPageBytes, 1048576u);
    CHECK_EQ(HeadPageArena::kTotalBytes, 267386880u);

    arena.clear_page(0);
    arena.page(0)[0] = 0x11;
    arena.page(0)[HeadPageArena::kPageBytes - 1] = 0x22;
    CHECK_EQ(arena.page(0)[0], 0x11);
    CHECK_EQ(arena.page(0)[HeadPageArena::kPageBytes - 1], 0x22);

    // Last page is separately addressable and remains outside VOID head 255.
    arena.clear_page(254);
    arena.page(254)[17] = 0x33;
    CHECK_EQ(arena.page(254)[17], 0x33);
    CHECK_EQ(arena.page(0)[17], 0);

    std::array<std::uint8_t, HeadPageArena::kPageBytes> page{};
    page[0] = 0xA5;
    page[HeadPageArena::kPageBytes - 1] = 0x5A;
    arena.load_page(7, page.data(), page.size());
    CHECK_EQ(arena.page(7)[0], 0xA5);
    CHECK_EQ(arena.page(7)[HeadPageArena::kPageBytes - 1], 0x5A);

    bool rejected = false;
    try { (void)arena.page(255); } catch (const std::out_of_range&) {
        rejected = true;
    }
    CHECK(rejected);

    return test_done("native head page arena");
}
