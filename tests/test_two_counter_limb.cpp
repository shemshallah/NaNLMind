#include "nanlm/limb_counter.hpp"
#include "nanlm/two_counter_limb.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    Universe u(0x32434C42);
    ChartLimbStore c0(u, 0x1000, 8);
    ChartLimbStore c1(u, 0x1100, 8);
    TwoCounterMachineLimb m(u, c0, c1);
    m.load_program({
        {TwoCounterOp::Jz0, 4},
        {TwoCounterOp::Dec0, 0},
        {TwoCounterOp::Inc1, 0},
        {TwoCounterOp::Jump, 0},
        {TwoCounterOp::Halt, 0},
    });
    m.reset();
    c0.set(0, 5);
    m.run(100);
    CHECK(m.halted());
    CHECK_EQ(m.counter(0), 0u);
    CHECK_EQ(m.counter(1), 5u);
    CHECK_EQ(m.limbs(1), 1u);

    // Atlas-backed counter crossing a page.
    Atlas atlas;
    AtlasLimbStore a0(atlas, 0x2000, 1); // one limb per page
    AtlasLimbStore a1(atlas, 0x2100, 1);
    TwoCounterMachineLimb big(u, a0, a1, 0x0300, 0x0500);
    big.load_program({{TwoCounterOp::Inc0, 0}, {TwoCounterOp::Halt, 0}});
    big.reset();
    a0.set(0, 0xFFFF);
    big.run(10);
    CHECK(big.halted());
    CHECK_EQ(big.counter(0), 0x10000u);
    CHECK_EQ(big.limbs(0), 2u);
    CHECK_EQ(atlas.page_count(), 2u);

    return test_done("2CM with limb counters and atlas pages");
}
