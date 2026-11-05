#include "nanlm/two_counter_limb.hpp"

namespace nanlm {
namespace {
constexpr std::uint16_t kHalt = 0;
constexpr std::uint16_t kIp = 1;
} // namespace

TwoCounterMachineLimb::TwoCounterMachineLimb(Universe& universe, LimbStore& c0,
                                             LimbStore& c1, std::uint16_t state_base,
                                             std::uint16_t program_base)
    : universe_(&universe), c0_(c0), c1_(c1), state_base_(state_base),
      program_base_(program_base) {}

void TwoCounterMachineLimb::load_program(
    const std::vector<TwoCounterInstruction>& program) {
    program_size_ = program.size();
    for (std::size_t i = 0; i < program.size(); ++i) {
        universe_->address_reg(static_cast<std::uint16_t>(program_base_ + i)).meta =
            static_cast<std::uint64_t>(program[i].op) |
            (static_cast<std::uint64_t>(program[i].target) << 8);
    }
    reset();
}

void TwoCounterMachineLimb::reset() {
    c0_.clear();
    c1_.clear();
    universe_->address_reg(state_base_ + kHalt).meta = 0;
    universe_->address_reg(state_base_ + kIp).meta = 0;
}

bool TwoCounterMachineLimb::halted() const {
    return universe_->address_reg(state_base_ + kHalt).meta != 0;
}

std::uint64_t TwoCounterMachineLimb::counter(std::uint8_t which) const {
    return (which == 0 ? c0_ : c1_).low64();
}

std::uint32_t TwoCounterMachineLimb::ip() const {
    return static_cast<std::uint32_t>(universe_->address_reg(state_base_ + kIp).meta);
}

std::size_t TwoCounterMachineLimb::limbs(std::uint8_t which) const {
    return (which == 0 ? c0_ : c1_).limbs();
}

bool TwoCounterMachineLimb::step() {
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
    auto& next = universe_->address_reg(state_base_ + kIp).meta;
    switch (op) {
        case TwoCounterOp::Inc0: if (!c0_.increment()) return false; next = ip + 1u; break;
        case TwoCounterOp::Inc1: if (!c1_.increment()) return false; next = ip + 1u; break;
        case TwoCounterOp::Dec0: c0_.decrement(); next = ip + 1u; break;
        case TwoCounterOp::Dec1: c1_.decrement(); next = ip + 1u; break;
        case TwoCounterOp::Jz0: next = c0_.is_zero() ? target : ip + 1u; break;
        case TwoCounterOp::Jz1: next = c1_.is_zero() ? target : ip + 1u; break;
        case TwoCounterOp::Jump: next = target; break;
        case TwoCounterOp::Halt:
            universe_->address_reg(state_base_ + kHalt).meta = 1;
            return false;
    }
    return true;
}

std::size_t TwoCounterMachineLimb::run(std::size_t max_steps) {
    std::size_t n = 0;
    while (n < max_steps && step()) ++n;
    return n;
}

} // namespace nanlm
