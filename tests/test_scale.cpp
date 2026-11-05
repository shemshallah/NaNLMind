#include "nanlm/ring.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    const ScalePlan l0 = scale_plan(0);
    CHECK_EQ(l0.universes, static_cast<u128>(1));
    CHECK_EQ(l0.addresses, static_cast<u128>(65536));
    CHECK_EQ(l0.canonical, static_cast<u128>(32896));
    CHECK_EQ(l0.pairs, static_cast<u128>(32640));
    CHECK_EQ(l0.fixed, static_cast<u128>(256));
    CHECK_EQ(l0.dense_bytes, static_cast<u128>(8 * 1024 * 1024));

    const ScalePlan l1 = scale_plan(1);
    CHECK_EQ(l1.universes, static_cast<u128>(256));
    CHECK_EQ(l1.addresses, static_cast<u128>(16777216));
    CHECK_EQ(l1.canonical, static_cast<u128>(8421376));
    CHECK_EQ(l1.pairs, static_cast<u128>(8355840));
    CHECK_EQ(l1.fixed, static_cast<u128>(65536));
    CHECK_EQ(l1.dense_bytes, static_cast<u128>(2048ull * 1024 * 1024));

    const ScalePlan l2 = scale_plan(2);
    CHECK_EQ(l2.universes, static_cast<u128>(65536));
    CHECK_EQ(l2.addresses, static_cast<u128>(4294967296ull));
    CHECK_EQ(l2.canonical, static_cast<u128>(2155872256ull));
    CHECK_EQ(l2.dense_bytes, static_cast<u128>(512ull * 1024 * 1024 * 1024));

    const ScalePlan l3 = scale_plan(3);
    CHECK_EQ(u128_to_string(l3.addresses), std::string("1099511627776"));
    CHECK_EQ(u128_to_string(l3.pairs), std::string("547608330240"));

    const RingPlan r1 = ring_plan(1, 5, 7ull * 1024 * 1024 * 1024);
    CHECK_EQ(r1.nodes, 5);
    CHECK(r1.per_node_universes == static_cast<u128>(52));
    CHECK(r1.all_fit);
    CHECK_EQ(r1.members.size(), 5u);

    const RingPlan r2 = ring_plan(2, 5, 7ull * 1024 * 1024 * 1024);
    CHECK(r2.per_node_universes == static_cast<u128>(13108));
    CHECK(!r2.all_fit);

    for (int i = 0; i < 100; ++i) {
        PageId p = PageId::child(PageId::root(), static_cast<std::uint8_t>(i));
        const std::uint32_t owner = owner_of(p, 5);
        CHECK(owner < 5);
    }

    CHECK_EQ(human_bytes(static_cast<u128>(4 * 1024 * 1024)), std::string("4.000 MiB"));
    CHECK_EQ(u128_to_string(static_cast<u128>(0)), std::string("0"));

    return test_done("scaling arithmetic and ring planning");
}
