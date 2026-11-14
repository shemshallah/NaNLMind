#include "nanlm/turing_machine.hpp"
#include "nanlm/universal_tm.hpp"
#include "test_util.hpp"

#include <cstdint>
#include <limits>

using namespace nanlm;

int main() {
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

    // Signed head addition must fail closed instead of overflowing.
    const std::vector<TmTransition> grow{
        {0, 2, 2, 1, 0, false},
    };
    Universe u2(0x4F56464C);
    UniversalTuringMachine utm2(u2);
    CHECK(utm2.load_machine(grow, "", std::numeric_limits<std::int64_t>::max()));
    CHECK(!utm2.step());
    CHECK(utm2.halted());

    Universe u3(0x4F564644);
    TuringMachine tm(u3);
    CHECK(tm.load(grow));
    tm.set_tape_symbols({}, std::numeric_limits<std::int64_t>::max());
    CHECK(!tm.step());
    CHECK(tm.halted());

    return test_done("UTM description/work separation and signed-head overflow");
}
