#pragma once

#include "nanlm/binary_tm_compiler.hpp"
#include "nanlm/turing_machine.hpp"

#include <cstdint>

namespace nanlm {

// Direct table-driven binary-machine runtime. This is the compact path for the
// compiled Minsky table: no 22 KB Minsky description scan per microstep.
class BinaryUniversalMachine {
public:
    BinaryUniversalMachine() = default;

    void load(const BinaryTm& machine,
              const std::vector<std::uint8_t>& initial_tape,
              std::int64_t head,
              std::uint16_t initial_state);
    bool step();
    std::size_t run(std::size_t max_steps = 1000000);
    bool halted() const { return halted_; }
    std::uint16_t state() const { return state_; }
    std::int64_t head() const { return head_; }
    std::uint8_t symbol(std::int64_t position) const {
        const std::uint8_t s = tape_.read(position);
        return s == 2 ? 0 : s;
    }
    std::size_t pages() const { return tape_.pages(); }

private:
    const BinaryTm* machine_;
    TuringTape tape_;
    std::uint16_t state_ = 0;
    std::int64_t head_ = 0;
    bool halted_ = false;
};

} // namespace nanlm
