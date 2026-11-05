#include "nanlm/limb_counter.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    Universe u(0x4C494D42);
    ChartLimbStore chart(u, 0x1000, 4);
    LimbCounter c(chart);
    CHECK(c.increment());
    CHECK_EQ(c.low64(), 1u);
    chart.set(0, 0xFFFF);
    CHECK(c.increment());
    CHECK_EQ(c.low64(), 0x10000u);
    CHECK_EQ(c.limbs(), 2u);
    CHECK(c.decrement());
    CHECK_EQ(c.low64(), 0xFFFFu);
    Universe u2(0x4C494D43);
    ChartLimbStore chart2(u2, 0x1000, 4);
    LimbCounter one(chart2);
    CHECK(one.increment());
    CHECK(one.decrement());
    CHECK(one.is_zero());
    CHECK(!one.decrement());

    Atlas atlas;
    AtlasLimbStore atlas_store(atlas, 0x2000, 16);
    LimbCounter big(atlas_store);
    CHECK(big.increment());
    atlas_store.grow(17);
    atlas_store.set(16, 1);
    CHECK_EQ(atlas.page_count(), 2u);
    CHECK_EQ(big.limbs(), 17u);
    CHECK(!big.is_zero());
    CHECK_EQ(atlas_store.get(16), 1u);

    return test_done("multi-limb counters and atlas paging");
}
