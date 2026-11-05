#include "nanlm/turing_machine.hpp"

#include <algorithm>

namespace nanlm {
namespace {
constexpr std::uint16_t kStateSlot = 0;
constexpr std::uint16_t kHeadSlot = 1;
constexpr std::uint16_t kHaltSlot = 2;

std::pair<std::int64_t, std::int64_t> split_position(std::int64_t position) {
    std::int64_t page = position / TuringTape::kCellsPerPage;
    std::int64_t offset = position % TuringTape::kCellsPerPage;
    if (offset < 0) { offset += TuringTape::kCellsPerPage; --page; }
    return {page, offset};
}
} // namespace

std::uint8_t TuringTape::read(std::int64_t position) const {
    const auto [page, offset] = split_position(position);
    const auto it = pages_.find(page);
    if (it == pages_.end()) return 2; // blank symbol
    return static_cast<std::uint8_t>(
        it->second->address_reg(static_cast<std::uint16_t>(offset)).meta & 0xFFu);
}

void TuringTape::write(std::int64_t position, std::uint8_t symbol) {
    const auto [page, offset] = split_position(position);
    auto& ptr = pages_[page];
    if (!ptr) ptr = std::make_unique<Universe>(0x544D5047u + static_cast<std::uint64_t>(page));
    ptr->address_reg(static_cast<std::uint16_t>(offset)).meta = symbol;
}

std::string TuringTape::slice(std::int64_t begin, std::int64_t end) const {
    std::string out;
    for (std::int64_t p = begin; p < end; ++p) {
        const std::uint8_t s = read(p);
        out.push_back(s == 0 ? '0' : s == 1 ? '1' : ' ');
    }
    return out;
}

void TuringMachine::load(const std::vector<TmTransition>& transitions) {
    for (const auto& t : transitions) {
        if (t.from >= kMaxStates || t.read >= kAlphabet) continue;
        const std::uint64_t move = static_cast<std::uint64_t>(t.move + 1);
        universe_->address_reg(static_cast<std::uint16_t>(
            kTableBase + t.from * 8u + t.read)).meta =
            static_cast<std::uint64_t>(t.write) |
            (static_cast<std::uint64_t>(t.to) << 8) |
            (move << 16) |
            (1ull << 20) |
            (t.halt ? (1ull << 21) : 0ull);
    }
    universe_->address_reg(kControlBase + kHaltSlot).meta = 0;
    universe_->address_reg(kControlBase + kStateSlot).meta = 0;
}

void TuringMachine::set_tape(const std::string& tape, std::int64_t head) {
    for (std::int64_t i = 0; i < static_cast<std::int64_t>(tape.size()); ++i) {
        const char c = tape[static_cast<std::size_t>(i)];
        tape_.write(i, c == '0' ? 0 : c == '1' ? 1 : 2);
    }
    universe_->address_reg(kControlBase + kHeadSlot).meta = static_cast<std::uint64_t>(head);
    universe_->address_reg(kControlBase + kStateSlot).meta = 0;
    universe_->address_reg(kControlBase + kHaltSlot).meta = 0;
}

bool TuringMachine::halted() const {
    return universe_->address_reg(kControlBase + kHaltSlot).meta != 0;
}

std::uint8_t TuringMachine::state() const {
    return static_cast<std::uint8_t>(universe_->address_reg(kControlBase + kStateSlot).meta);
}

std::int64_t TuringMachine::head() const {
    return static_cast<std::int64_t>(universe_->address_reg(kControlBase + kHeadSlot).meta);
}

std::string TuringMachine::tape(std::int64_t begin, std::int64_t end) const {
    return tape_.slice(begin, end);
}

bool TuringMachine::step() {
    if (halted()) return false;
    const std::uint8_t s = state();
    const std::int64_t h = head();
    const std::uint8_t read = tape_.read(h);
    const std::uint64_t raw =
        universe_->address_reg(static_cast<std::uint16_t>(kTableBase + s * 8u + read)).meta;
    if ((raw & (1ull << 20)) == 0) {
        universe_->address_reg(kControlBase + kHaltSlot).meta = 1;
        return false;
    }
    const std::uint8_t write = static_cast<std::uint8_t>(raw & 0xFFu);
    const std::uint8_t to = static_cast<std::uint8_t>((raw >> 8) & 0xFFu);
    const std::int8_t move = static_cast<std::int8_t>(((raw >> 16) & 0x3u) - 1);
    tape_.write(h, write);
    universe_->address_reg(kControlBase + kStateSlot).meta = to;
    universe_->address_reg(kControlBase + kHeadSlot).meta =
        static_cast<std::uint64_t>(h + move);
    if ((raw & (1ull << 21)) != 0) {
        universe_->address_reg(kControlBase + kHaltSlot).meta = 1;
        return false;
    }
    return true;
}

std::size_t TuringMachine::run(std::size_t max_steps) {
    std::size_t n = 0;
    while (n < max_steps && step()) ++n;
    return n;
}

} // namespace nanlm
