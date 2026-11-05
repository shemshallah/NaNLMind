// U1 bounded two-counter machine stored in chart address registers.
// Program, state, IP and counters live in AddressReg::meta; no host counter map.
#pragma once

#include "nanlm/universe.hpp"

#include <cstdint>
#include <vector>

namespace nanlm {

enum class TwoCounterOp : std::uint8_t {
    Inc0 = 0,
    Inc1 = 1,
    Dec0 = 2,
    Dec1 = 3,
    Jz0 = 4,
    Jz1 = 5,
    Jump = 6,
    Halt = 7,
};

struct TwoCounterInstruction {
    TwoCounterOp op = TwoCounterOp::Halt;
    std::uint32_t target = 0;
};

class TwoCounterMachine {
public:
    explicit TwoCounterMachine(Universe& universe,
                               std::uint16_t state_base = 0x0200,
                               std::uint16_t program_base = 0x0400);

    void load_program(const std::vector<TwoCounterInstruction>& program);
    void reset(std::uint64_t c0 = 0, std::uint64_t c1 = 0);
    bool step();
    std::size_t run(std::size_t max_steps = 1000000);
    bool halted() const;
    std::uint64_t counter(std::uint8_t which) const;
    std::uint32_t ip() const;
    std::size_t program_size() const { return program_size_; }

    const Universe& universe() const { return *universe_; }
    Universe& universe() { return *universe_; }

private:
    Universe* universe_;
    std::uint16_t state_base_;
    std::uint16_t program_base_;
    std::size_t program_size_ = 0;
};

} // namespace nanlm
