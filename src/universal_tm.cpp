#include "nanlm/universal_tm.hpp"

namespace nanlm {
namespace {
constexpr std::uint16_t kHaltSlot = 0;
constexpr std::uint16_t kStateSlot = 1;
constexpr std::uint16_t kHeadSlot = 2;
constexpr std::int64_t kEntrySize = 6;
constexpr std::int64_t kEntryBase = 2;
} // namespace

bool UniversalTuringMachine::load_machine(
    const std::vector<TmTransition>& transitions, const std::string& initial_tape,
    std::int64_t head) {
    if (transitions.size() > 255) return false;
    for (const auto& t : transitions) {
        if (t.from >= 32 || t.to >= 32 || t.read >= 8 || t.write >= 8 || t.move < -1 || t.move > 1) return false;
    }
    tape_.clear();
    tape_.write(kDescriptionBase, static_cast<std::uint8_t>(transitions.size()));
    for (std::size_t i = 0; i < transitions.size(); ++i) {
        const auto& t = transitions[i];
        const std::int64_t p = kEntryBase + static_cast<std::int64_t>(i) * kEntrySize;
        tape_.write(p + 0, t.from);
        tape_.write(p + 1, t.read);
        tape_.write(p + 2, t.write);
        tape_.write(p + 3, static_cast<std::uint8_t>(t.move + 1));
        tape_.write(p + 4, t.to);
        tape_.write(p + 5, t.halt ? 1 : 0);
    }
    for (std::int64_t i = 0; i < static_cast<std::int64_t>(initial_tape.size()); ++i) {
        const char c = initial_tape[static_cast<std::size_t>(i)];
        tape_.write(kWorkingTapeBase + i, c == '0' ? 0 : c == '1' ? 1 : 2);
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

std::uint8_t UniversalTuringMachine::description_count() const {
    return tape_.read(kDescriptionBase);
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
    return tape_.slice(kWorkingTapeBase + begin, kWorkingTapeBase + end);
}

bool UniversalTuringMachine::step() {
    if (halted()) return false;
    const std::uint8_t s = state();
    const std::int64_t h = head();
    const std::uint8_t read = tape_.read(kWorkingTapeBase + h);
    const std::size_t count = description_count();
    for (std::size_t i = 0; i < count; ++i) {
        const std::int64_t p = kEntryBase + static_cast<std::int64_t>(i) * kEntrySize;
        if (tape_.read(p + 0) != s || tape_.read(p + 1) != read) continue;
        const std::uint8_t write = tape_.read(p + 2);
        const std::int8_t move = static_cast<std::int8_t>(tape_.read(p + 3)) - 1;
        const std::uint8_t to = tape_.read(p + 4);
        const bool halt = tape_.read(p + 5) != 0;
        tape_.write(kWorkingTapeBase + h, write);
        universe_->set_address_meta(kControlBase + kStateSlot, to);
        universe_->set_address_meta(kControlBase + kHeadSlot,
                                    static_cast<std::uint64_t>(h + move));
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
