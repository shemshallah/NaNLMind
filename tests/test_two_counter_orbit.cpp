#include "nanlm/two_counter.hpp"
#include "test_util.hpp"

#include <cstdint>
#include <vector>

using namespace nanlm;

namespace {
struct Ref2CM {
    std::vector<TwoCounterInstruction> program;
    std::uint64_t c0 = 0, c1 = 0;
    std::uint32_t ip = 0;
    bool halt = false;

    bool step() {
        if (halt) return false;
        if (ip >= program.size()) { halt = true; return false; }
        const auto& ins = program[ip];
        switch (ins.op) {
            case TwoCounterOp::Inc0: ++c0; ++ip; return true;
            case TwoCounterOp::Inc1: ++c1; ++ip; return true;
            case TwoCounterOp::Dec0: if (c0) --c0; ++ip; return true;
            case TwoCounterOp::Dec1: if (c1) --c1; ++ip; return true;
            case TwoCounterOp::Jz0: ip = c0 == 0 ? ins.target : ip + 1; return true;
            case TwoCounterOp::Jz1: ip = c1 == 0 ? ins.target : ip + 1; return true;
            case TwoCounterOp::Jump: ip = ins.target; return true;
            case TwoCounterOp::Halt: halt = true; return false;
        }
        return false;
    }
};
} // namespace

int main() {
    const std::vector<TwoCounterInstruction> program{
        {TwoCounterOp::Jz0, 4},
        {TwoCounterOp::Dec0, 0},
        {TwoCounterOp::Inc1, 0},
        {TwoCounterOp::Jump, 0},
        {TwoCounterOp::Halt, 0},
    };
    Universe u(0x4F524249);
    TwoCounterMachine m(u);
    m.load_program(program);
    m.reset(5, 0);
    Ref2CM ref{program, 5, 0, 0, false};

    std::size_t steps = 0;
    while (!m.halted() && steps < 100) {
        const bool alive = m.step();
        ref.step();
        CHECK_EQ(m.ip(), ref.ip);
        CHECK_EQ(m.counter(0), ref.c0);
        CHECK_EQ(m.counter(1), ref.c1);
        CHECK_EQ(m.halted(), ref.halt);
        ++steps;
        if (!alive) break;
    }
    CHECK(m.halted());
    CHECK(ref.halt);
    CHECK_EQ(steps, 22u); // includes both JZ checks and HALT decode
    CHECK_EQ(m.counter(1), 5u);

    // Snapshot/replay preserves the same orbit endpoint.
    Universe copy = u;
    TwoCounterMachine replay(copy);
    CHECK(replay.halted());
    CHECK_EQ(replay.counter(0), 0u);
    CHECK_EQ(replay.counter(1), 5u);
    return test_done("reference 2CM orbit comparison");
}
