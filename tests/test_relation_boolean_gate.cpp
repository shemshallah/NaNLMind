#include "nanlm/head_gate.hpp"
#include "test_util.hpp"

#include <array>

using namespace nanlm;

namespace {
std::uint8_t op_for(std::array<bool, 4> table) {
    std::uint8_t op = 0;
    for (std::uint8_t i = 0; i < 4; ++i) if (table[i]) op = static_cast<std::uint8_t>(op | (1u << i));
    return op;
}
} // namespace

int main() {
    auto u = std::make_unique<Universe>(0x4E414E4C);
    HeadArray heads(*u, PageId::root());
    std::string err;
    CHECK(heads.verify(&err));
    CHECK_EQ(heads.size(), 256u);

    // Learn all 16 functions in 16 separate heads.
    for (std::uint8_t op = 0; op < 16; ++op) {
        HeadGate gate(heads, op);
        gate.train(op);
        CHECK_EQ(gate.rule(), op);
        CHECK_EQ(gate.mask(), static_cast<std::uint16_t>(1u << op));
        for (std::uint32_t a : {0u, 1u, 0xAAAAAAAAu, 0xFFFFFFFFu}) {
            for (std::uint32_t b : {0u, 1u, 0x55555555u, 0xFFFFFFFFu}) {
                CHECK_EQ(gate.apply(a, b), NanWord::eval_bool(op, a, b));
            }
        }
    }

    // Penguin-style relation evaluation: can_fly = is_bird AND NOT exception.
    const std::uint8_t and_not = op_for({false, false, true, false});
    HeadGate can_fly(heads, 16);
    can_fly.train(and_not);
    const std::uint32_t birds = 0x0000000F;    // eagle, penguin, sparrow, ostrich
    const std::uint32_t exception = 0x0000000A; // penguin, ostrich
    const std::uint32_t expected = 0x00000005;  // eagle, sparrow
    CHECK_EQ(can_fly.apply(birds, exception), expected);

    // The same gate handles a different bit assignment without retraining.
    const std::uint32_t more_birds = 0x000000F0;
    const std::uint32_t more_exception = 0x00000020;
    CHECK_EQ(can_fly.apply(more_birds, more_exception),
             static_cast<std::uint32_t>(0x000000D0));

    // Self-modification and restore.
    const std::uint16_t before = can_fly.mask();
    CHECK(can_fly.patch(1u << 0));
    CHECK(can_fly.mask() != before);
    CHECK(can_fly.patch(1u << 0));
    CHECK_EQ(can_fly.mask(), before);
    CHECK(heads.verify(&err));

    return test_done("learned Boolean heads as relation gates");
}
