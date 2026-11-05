#include "nanlm/two_counter.hpp"

namespace nanlm {
namespace {
constexpr std::uint16_t kHalt = 0;
constexpr std::uint16_t kIp = 1;
constexpr std::uint16_t kC0 = 2;
constexpr std::uint16_t kC1 = 3;
} // namespace

TwoCounterMachine::TwoCounterMachine(Universe& universe, std::uint16_t state_base,
                                     std::uint16_t program_base)
    : universe_(&universe), state_base_(state_base), program_base_(program_base) {}

void TwoCounterMachine::load_program(const std::vector<TwoCounterInstruction>& program) {
    program_size_ = program.size();
    for (std::size_t i = 0; i < program.size(); ++i) {
        universe_->address_reg(static_cast<std::uint16_t>(program_base_ + i)).meta =
            static_cast<std::uint64_t>(program[i].op) |
            (static_cast<std::uint64_t>(program[i].target) << 8);
    }
    reset(0, 0);
}

void TwoCounterMachine::reset(std::uint64_t c0, std::uint64_t c1) {
    universe_->address_reg(state_base_ + kHalt).meta = 0;
    universe_->address_reg(state_base_ + kIp).meta = 0;
    universe_->address_reg(state_base_ + kC0).meta = c0;
    universe_->address_reg(state_base_ + kC1).meta = c1;
}

bool TwoCounterMachine::halted() const {
    return universe_->address_reg(state_base_ + kHalt).meta != 0;
}

std::uint64_t TwoCounterMachine::counter(std::uint8_t which) const {
    return universe_->address_reg(state_base_ + (which == 0 ? kC0 : kC1)).meta;
}

std::uint32_t TwoCounterMachine::ip() const {
    return static_cast<std::uint32_t>(universe_->address_reg(state_base_ + kIp).meta);
}

bool TwoCounterMachine::step() {
    if (halted()) return false;
    const std::uint32_t ip = this->ip();
    if (ip >= program_size_) {
        universe_->address_reg(state_base_ + kHalt).meta = 1;
        return false;
    }
    const std::uint64_t raw =
        universe_->address_reg(static_cast<std::uint16_t>(program_base_ + ip)).meta;
    const auto op = static_cast<TwoCounterOp>(raw & 0xFFu);
    const std::uint32_t target = static_cast<std::uint32_t>(raw >> 8);
    auto& c0 = universe_->address_reg(state_base_ + kC0).meta;
    auto& c1 = universe_->address_reg(state_base_ + kC1).meta;
    auto& next = universe_->address_reg(state_base_ + kIp).meta;

    switch (op) {
        case TwoCounterOp::Inc0: ++c0; next = ip + 1u; break;
        case TwoCounterOp::Inc1: ++c1; next = ip + 1u; break;
        case TwoCounterOp::Dec0: if (c0 > 0) --c0; next = ip + 1u; break;
        case TwoCounterOp::Dec1: if (c1 > 0) --c1; next = ip + 1u; break;
        case TwoCounterOp::Jz0: next = (c0 == 0) ? target : ip + 1u; break;
        case TwoCounterOp::Jz1: next = (c1 == 0) ? target : ip + 1u; break;
        case TwoCounterOp::Jump: next = target; break;
        case TwoCounterOp::Halt:
            universe_->address_reg(state_base_ + kHalt).meta = 1;
            return false;
    }
    return true;
}

std::size_t TwoCounterMachine::run(std::size_t max_steps) {
    std::size_t steps = 0;
    while (steps < max_steps && step()) ++steps;
    return steps;
}

} // namespace nanlm
