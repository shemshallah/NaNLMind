#include "nanlm/head_page_loader.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    RawFieldVM vm("build/field_driver.nan");
    CHECK(vm.ready());
    HeadPageArena arena;
    HeadPageLoader loader(vm, arena);
    CHECK_EQ(HeadPageLoader::kSlots, 20u);
    CHECK_EQ(HeadPageLoader::kWordsPerPage, 262144u);
    CHECK_EQ(HeadPageLoader::slot_base(0), 0x00800000u);
    CHECK_EQ(HeadPageLoader::slot_base(15), 0x00BC0000u);
    CHECK_EQ(HeadPageLoader::slot_base(19), 0x00CC0000u);

    for (std::size_t h = 0; h < 17; ++h) {
        arena.clear_page(h);
        arena.page(h)[0] = static_cast<std::uint8_t>(h);
        arena.page(h)[1] = 0x5A;
    }
    const std::size_t slot0 = loader.load(0);
    CHECK_EQ(slot0, 0u);
    CHECK(loader.resident(0));
    CHECK_EQ(loader.slot_of(0), 0);
    CHECK_EQ(vm.read_payload_word(HeadPageLoader::slot_base(0)), 0x5A00u);
    CHECK_EQ(vm.read_payload_word(HeadPageLoader::slot_base(0) + 1u), 0u);

    arena.clear_page(254);
    arena.page(254)[0] = 254;
    arena.page(254)[1] = 0x5A;
    const std::size_t slot254 = loader.load(254);
    CHECK(slot254 < 20);
    CHECK(loader.resident(254));
    CHECK_EQ(vm.read_payload_word(HeadPageLoader::slot_base(slot254)), 0x5AFEu);

    // Reloading an existing head does not allocate another slot.
    CHECK_EQ(loader.load(0), slot0);
    CHECK_EQ(loader.resident_count(), 2u);

    // Fill all 20 slots, then force an LRU eviction.
    for (std::size_t h = 1; h < 20; ++h) loader.load(h);
    CHECK_EQ(loader.resident_count(), 20u);
    const int evicted = loader.load(20);
    CHECK(evicted >= 0 && evicted < 20);
    CHECK(!loader.resident(254)); // 254 was least recently used after 0 was reloaded
    CHECK(loader.resident(20));

    return test_done("native head page loader");
}
