#include "nanlm/vector_store.hpp"
#include "test_util.hpp"

#include <cstring>
#include <vector>

using namespace nanlm;

int main() {
    BinStore store;
    const BinId b1 = store.create(4, 2);
    const BinId b2 = store.create(4, 2);
    CHECK(b1 != kInvalidBin);
    CHECK(b2 != kInvalidBin);

    CHECK(store.write(b1, 0, {1, 0, 0, 0}));   // key A
    CHECK(store.write(b1, 1, {10, 0, 0, 0}));  // value A
    CHECK(store.write(b2, 0, {0, 1, 0, 0}));   // key B
    CHECK(store.write(b2, 1, {20, 0, 0, 0}));  // value B

    std::vector<std::int16_t> v;
    CHECK(store.read(b1, 1, v));
    CHECK((v == std::vector<std::int16_t>{10, 0, 0, 0}));
    CHECK(store.vector(b2, 0) != nullptr);

    PointBinMap points;
    CHECK(points.bind(16254, BinRef{b1, 0}));
    CHECK(points.bind(16255, BinRef{b2, 0}));
    CHECK_EQ(points.resolve(16254).bin, b1);
    CHECK_EQ(points.resolve(16254).slot, 0u);
    CHECK_EQ(points.resolve(16255).bin, b2);
    CHECK_EQ(points.bindings(), 2u);
    CHECK(points.unbind(16255));
    CHECK(!points.resolve(16255).valid());

    AssocMemory memory(store);
    const std::uint32_t a = memory.bind({BinRef{b1, 0}}, {BinRef{b1, 1}}, 65536, 1);
    const std::uint32_t b = memory.bind({BinRef{b2, 0}}, {BinRef{b2, 1}}, 65536, 2);
    const std::uint32_t macro = memory.bind(
        {BinRef{b1, 0}, BinRef{b2, 0}}, {BinRef{b2, 1}}, 65536, 3);
    CHECK(a != 0 && b != 0 && macro != 0);
    CHECK(memory.get(a) != nullptr);

    auto hit = memory.recall({1, 0, 0, 0}, 1);
    CHECK_EQ(hit.size(), 1u);
    if (!hit.empty()) {
        CHECK_EQ(hit[0].id, a);
        CHECK_EQ(hit[0].score, 1);
        CHECK_EQ(hit[0].values.at(0).bin, b1);
    }

    // The macro key contributes both component scores, so it beats either
    // single-key entry when both components are present.
    auto macro_hit = memory.recall({1, 1, 0, 0}, 1);
    CHECK_EQ(macro_hit.size(), 1u);
    if (!macro_hit.empty()) {
        CHECK_EQ(macro_hit[0].id, macro);
        CHECK_EQ(macro_hit[0].score, 2);
    }

    HeadScratch scratch;
    const std::int16_t query[4] = {1, 1, 0, 0};
    std::memcpy(scratch.work(), query, sizeof(query));
    auto from_head = memory.recall_from_head(scratch, 4, 1);
    CHECK_EQ(from_head.size(), 1u);
    if (!from_head.empty()) CHECK_EQ(from_head[0].id, macro);

    // A separate store with the same bins is deterministic.
    BinStore copy;
    const BinId c1 = copy.create(4, 2);
    const BinId c2 = copy.create(4, 2);
    CHECK(c1 == b1 && c2 == b2);
    CHECK(copy.write(c1, 0, {1, 0, 0, 0}));
    CHECK(copy.write(c1, 1, {10, 0, 0, 0}));
    CHECK(copy.write(c2, 0, {0, 1, 0, 0}));
    CHECK(copy.write(c2, 1, {20, 0, 0, 0}));
    CHECK(store.digest() == copy.digest());

    CHECK(memory.remove(macro));
    CHECK(memory.get(macro) == nullptr);
    CHECK(memory.size() == 2u);

    return test_done("addressable vector bins and macro associations");
}
