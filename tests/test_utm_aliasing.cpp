#include "nanlm/turing_machine.hpp"
#include "nanlm/universal_tm.hpp"
#include "test_util.hpp"

#include <cstdint>
#include <limits>
#include <vector>

using namespace nanlm;

int main() {
    // Signed Euclidean page splitting: negative and positive cells with the
    // same slot must never alias, and absent cells must read as blank 2.
    TuringTape pages;
    const std::vector<std::int64_t> positions{
        -4097, -4096, -1, 0, 4095, 4096,
        std::numeric_limits<std::int64_t>::min(),
        std::numeric_limits<std::int64_t>::max()
    };
    for (auto p : positions) CHECK_EQ(pages.read(p), 2);
    for (std::size_t i = 0; i < positions.size(); ++i)
        pages.write(positions[i], static_cast<std::uint8_t>(i + 10));
    for (std::size_t i = 0; i < positions.size(); ++i)
        CHECK_EQ(pages.read(positions[i]), static_cast<std::uint8_t>(i + 10));
    CHECK_EQ(pages.read(-4098), 2);
    CHECK_EQ(pages.read(1), 2);
    CHECK_EQ(pages.read(4097), 2);

    const std::vector<TmTransition> binary{
        {0, 1, 0, -1, 0, false},
        {0, 0, 1, 0, 0, true},
        {0, 2, 1, 0, 0, true},
    };

    // Description and working tapes are separate.  The old shared tape made
    // this negative working address alias description byte zero.
    Universe u(0x414C4941);
    UniversalTuringMachine utm(u);
    CHECK(utm.load_machine(binary, "", -UniversalTuringMachine::kWorkingTapeBase));
    CHECK_EQ(utm.symbol(-UniversalTuringMachine::kWorkingTapeBase), 2);
    CHECK(!utm.step());
    CHECK(utm.halted());

    // Repeated steps in the historical shared-tape overlap interval must
    // keep the description count and transition rows intact.
    const std::vector<TmTransition> walk{
        {0, 2, 0, 1, 0, false},
        {0, 0, 0, 1, 0, false},
    };
    Universe u_walk(0x57414C4B);
    UniversalTuringMachine walker(u_walk);
    const auto old_alias = -UniversalTuringMachine::kWorkingTapeBase;
    CHECK(walker.load_machine(walk, "", old_alias));
    CHECK(walker.step());
    CHECK(walker.step());
    CHECK(!walker.halted());
    CHECK_EQ(walker.head(), old_alias + 2);
    CHECK_EQ(walker.symbol(old_alias), 0);
    CHECK_EQ(walker.symbol(old_alias + 1), 0);

    // Signed head addition must fail closed instead of overflowing.
    const std::vector<TmTransition> grow{
        {0, 2, 1, 1, 4, false},
    };
    Universe u2(0x4F56464C);
    UniversalTuringMachine utm2(u2);
    CHECK(utm2.load_machine(grow, "", std::numeric_limits<std::int64_t>::max()));
    CHECK(!utm2.step());
    CHECK(utm2.halted());
    CHECK_EQ(utm2.head(), std::numeric_limits<std::int64_t>::max());
    CHECK_EQ(utm2.state(), 4);
    CHECK_EQ(utm2.symbol(utm2.head()), 1);

    Universe u3(0x4F564644);
    TuringMachine tm(u3);
    CHECK(tm.load(grow));
    tm.set_tape_symbols({}, std::numeric_limits<std::int64_t>::max());
    CHECK(!tm.step());
    CHECK(tm.halted());
    CHECK_EQ(tm.head(), std::numeric_limits<std::int64_t>::max());
    CHECK_EQ(tm.state(), 4);
    CHECK_EQ(tm.symbol(tm.head()), 1);

    const std::vector<TmTransition> shrink{
        {0, 2, 1, -1, 3, false},
    };
    Universe u4(0x554E4446);
    UniversalTuringMachine low(u4);
    CHECK(low.load_machine(shrink, "", std::numeric_limits<std::int64_t>::min()));
    CHECK(!low.step());
    CHECK(low.halted());
    CHECK_EQ(low.head(), std::numeric_limits<std::int64_t>::min());
    CHECK_EQ(low.state(), 3);
    CHECK_EQ(low.symbol(low.head()), 1);

    return test_done("UTM separate stores, signed pages, and overflow ordering");
}
