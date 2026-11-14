#include "nanlm/universal_tm.hpp"

#include <limits>

namespace nanlm {
namespace {
constexpr std::uint16_t kHaltSlot = 0;
constexpr std::uint16_t kStateSlot = 1;
constexpr std::uint16_t kHeadSlot = 2;
constexpr std::int64_t kEntrySize = 6;
constexpr std::int64_t kEntryBase = 2;

bool checked_add(std::int64_t a, std::int64_t b, std::int64_t& out) {
    if (b > 0 && a > std::numeric_limits<std::int64_t>::max() - b) return false;
    if (b < 0 && a < std::numeric_limits<std::int64_t>::min() - b) return false;
    out = a + b;
    return true;
}
} // namespace

bool UniversalTuringMachine::load_machine(
    const std::vector<TmTransition>& transitions, const std::string& initial_tape,
    std::int64_t head) {
    if (transitions.size() > 255) return false;
    for (const auto& t : transitions) {
        if (t.from >= 32 || t.to >= 32 || t.read >= 8 || t.write >= 8 || t.move < -1 || t.move > 1) return false;
    }
    description_.clear();
    tape_.clear();
    description_.write(kDescriptionBase, static_cast<std::uint8_t>(transitions.size()));
    for (std::size_t i = 0; i < transitions.size(); ++i) {
        const auto& t = transitions[i];
        const std::int64_t p = kEntryBase + static_cast<std::int64_t>(i) * kEntrySize;
        description_.write(p + 0, t.from);
        description_.write(p + 1, t.read);
        description_.write(p + 2, t.write);
        description_.write(p + 3, static_cast<std::uint8_t>(t.move + 1));
        description_.write(p + 4, t.to);
        description_.write(p + 5, t.halt ? 1 : 0);
    }
    for (std::int64_t i = 0; i < static_cast<std::int64_t>(initial_tape.size()); ++i) {
        const char c = initial_tape[static_cast<std::size_t>(i)];
        tape_.write(i, c == '0' ? 0 : c == '1' ? 1 : 2);
    }
    universe_->set_address_meta(kControlBase + kHaltSlot, 0);
    universe_->set_address_meta(kControlBase + kStateSlot, 0);
    universe_->set_address_meta(kControlBase + kHeadSlot,
                                static_cast<std::uint64_t>(head));
    return true;
}

bool UniversalTuringMachine::load_machine_symbols(
    const std::vector<TmTransition>& transitions,
    const std::vector<std::uint8_t>& initial_tape, std::int64_t head) {
    if (transitions.size() > 255) return false;
    for (const auto& t : transitions) {
        if (t.from >= 32 || t.to >= 32 || t.read >= 8 || t.write >= 8 ||
            t.move < -1 || t.move > 1) return false;
    }
    description_.clear();
    tape_.clear();
    description_.write(kDescriptionBase, static_cast<std::uint8_t>(transitions.size()));
    for (std::size_t i = 0; i < transitions.size(); ++i) {
        const auto& t = transitions[i];
        const std::int64_t p = kEntryBase + static_cast<std::int64_t>(i) * kEntrySize;
        description_.write(p + 0, t.from);
        description_.write(p + 1, t.read);
        description_.write(p + 2, t.write);
        description_.write(p + 3, static_cast<std::uint8_t>(t.move + 1));
        description_.write(p + 4, t.to);
        description_.write(p + 5, t.halt ? 1 : 0);
    }
    for (std::int64_t i = 0;
         i < static_cast<std::int64_t>(initial_tape.size()); ++i) {
        tape_.write(i, initial_tape[static_cast<std::size_t>(i)]);
    }
    universe_->set_address_meta(kControlBase + kHaltSlot, 0);
    universe_->set_address_meta(kControlBase + kStateSlot, 0);
    universe_->set_address_meta(kControlBase + kHeadSlot,
                                static_cast<std::uint64_t>(head));
    return true;
}

bool UniversalTuringMachine::load_description(
    const TmDescription& description, const std::string& initial_tape,
    std::int64_t head) {
    if (!description.valid()) return false;
    return load_machine(description.transitions, initial_tape, head);
}

bool UniversalTuringMachine::load_encoded_description(
    const std::uint8_t* data, std::size_t len, const std::string& initial_tape,
    std::int64_t head) {
    const auto description = TmDescription::decode(data, len);
    if (!description) return false;
    return load_description(*description, initial_tape, head);
}

bool UniversalTuringMachine::load_description_symbols(
    const TmDescription& description,
    const std::vector<std::uint8_t>& initial_tape, std::int64_t head) {
    if (!description.valid()) return false;
    return load_machine_symbols(description.transitions, initial_tape, head);
}

void UniversalTuringMachine::set_state(std::uint8_t state) {
    universe_->set_address_meta(kControlBase + kStateSlot, state);
}

std::uint8_t UniversalTuringMachine::description_count() const {
    return description_.read(kDescriptionBase);
}

bool UniversalTuringMachine::halted() const {
    return universe_->address_reg(kControlBase + kHaltSlot).meta != 0;
}

std::uint8_t UniversalTuringMachine::state() const {
    return static_cast<std::uint8_t>(universe_->address_reg(kControlBase + kStateSlot).meta);
}

std::int64_t UniversalTuringMachine::head() const {
    return static_cast<std::int64_t>(universe_->address_reg(kControlBase + kHeadSlot).meta);
}

std::string UniversalTuringMachine::tape(std::int64_t begin, std::int64_t end) const {
    return tape_.slice(begin, end);
}

bool UniversalTuringMachine::step() {
    if (halted()) return false;
    const std::uint8_t s = state();
    const std::int64_t h = head();
    const std::uint8_t read = tape_.read(h);
    const std::size_t count = description_count();
    for (std::size_t i = 0; i < count; ++i) {
        const std::int64_t p = kEntryBase + static_cast<std::int64_t>(i) * kEntrySize;
        if (description_.read(p + 0) != s || description_.read(p + 1) != read) continue;
        const std::uint8_t write = description_.read(p + 2);
        const std::int8_t move = static_cast<std::int8_t>(description_.read(p + 3)) - 1;
        const std::uint8_t to = description_.read(p + 4);
        const bool halt = description_.read(p + 5) != 0;
        tape_.write(h, write);
        universe_->set_address_meta(kControlBase + kStateSlot, to);
        std::int64_t next_head = 0;
        if (!checked_add(h, move, next_head)) {
            universe_->set_address_meta(kControlBase + kHaltSlot, 1);
            return false;
        }
        universe_->set_address_meta(kControlBase + kHeadSlot,
                                    static_cast<std::uint64_t>(next_head));
        if (halt) {
            universe_->set_address_meta(kControlBase + kHaltSlot, 1);
            return false;
        }
        return true;
    }
    universe_->set_address_meta(kControlBase + kHaltSlot, 1);
    return false;
}

std::size_t UniversalTuringMachine::run(std::size_t max_steps) {
    std::size_t n = 0;
    while (n < max_steps && step()) ++n;
    return n;
}

} // namespace nanlm
