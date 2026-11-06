#include "nanlm/binary_utm.hpp"

#include <algorithm>

namespace nanlm {

void BinaryUniversalMachine::load(const BinaryTm& machine,
                                  const std::vector<std::uint8_t>& initial_tape,
                                  std::int64_t head,
                                  std::uint16_t initial_state) {
    machine_ = &machine;
    tape_.clear();
    for (std::int64_t i = 0; i < static_cast<std::int64_t>(initial_tape.size()); ++i) {
        tape_.write(i, initial_tape[static_cast<std::size_t>(i)]);
    }
    state_ = initial_state;
    head_ = head;
    halted_ = false;
}

bool BinaryUniversalMachine::step() {
    if (halted_ || machine_ == nullptr) return false;
    const std::uint8_t raw = tape_.read(head_);
    const std::uint8_t read = raw == 2 ? 0 : raw;
    const auto it = std::find_if(machine_->transitions.begin(),
                                 machine_->transitions.end(),
                                 [&](const BinaryTransition& t) {
                                     return t.from == state_ && t.read == read;
                                 });
    if (it == machine_->transitions.end()) {
        halted_ = true;
        return false;
    }
    tape_.write(head_, it->write);
    state_ = it->to;
    head_ += it->move;
    return true;
}

std::size_t BinaryUniversalMachine::run(std::size_t max_steps) {
    std::size_t n = 0;
    while (n < max_steps && step()) ++n;
    return n;
}

} // namespace nanlm
