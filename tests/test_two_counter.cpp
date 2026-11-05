#include "nanlm/two_counter.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    Universe u(0x32434D31);
    TwoCounterMachine m(u);
    // Copy C0 into C1: while C0 != 0 { C0--; C1++ }.
    m.load_program({
        {TwoCounterOp::Jz0, 4},
        {TwoCounterOp::Dec0, 0},
        {TwoCounterOp::Inc1, 0},
        {TwoCounterOp::Jump, 0},
        {TwoCounterOp::Halt, 0},
    });
    m.reset(5, 0);
    CHECK_EQ(m.counter(0), 5u);
    const std::size_t steps = m.run(100);
    CHECK(m.halted());
    CHECK_EQ(m.counter(0), 0u);
    CHECK_EQ(m.counter(1), 5u);
    CHECK_EQ(m.ip(), 4u);
    CHECK(steps > 0); // HALT is not counted as a successful step

    // Replay determinism from a snapshot of the address registers.
    Universe snap = u;
    TwoCounterMachine replay(snap);
    // Program and state are in the address registers; no host state needed.
    CHECK(replay.halted());
    CHECK_EQ(replay.counter(1), 5u);

    // Increment-only program.
    Universe u2(0x32434D32);
    TwoCounterMachine m2(u2);
    m2.load_program({{TwoCounterOp::Inc0, 0}, {TwoCounterOp::Inc0, 0},
                     {TwoCounterOp::Halt, 0}});
    m2.reset(0, 0);
    CHECK_EQ(m2.run(10), 2u);
    CHECK_EQ(m2.counter(0), 2u);

    return test_done("bounded two-counter machine in chart registers");
}
