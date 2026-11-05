#include "nanlm/clock.hpp"

#include <cstring>

namespace nanlm {

const char* clock_state_name(ClockState state) {
    return state == ClockState::Halt ? "HALT" : "LOOP";
}
const char* clock_signal_name(ClockSignal signal) {
    return signal == ClockSignal::QnanPositive ? "+qNaN" : "-sNaN";
}
const char* clock_direction_name(ClockDirection direction) {
    return direction == ClockDirection::Future ? "BE/FUTURE" : "LE/PAST";
}
const char* clock_event_name(ClockEventKind kind) {
    switch (kind) {
        case ClockEventKind::Allocate: return "ALLOCATE";
        case ClockEventKind::Execute: return "EXECUTE";
        case ClockEventKind::Signal: return "SIGNAL";
        case ClockEventKind::Rewrite: return "REWRITE";
        case ClockEventKind::Contradiction: return "CONTRADICTION";
        case ClockEventKind::Cycle: return "CYCLE";
    }
    return "UNKNOWN";
}

TemporalClock::TemporalClock() { init(); }

void TemporalClock::init() {
    future_ = ClockState::Halt;
    past_rewrite_ = ClockState::Halt;
    future_address_ = kCells - 1;
    past_address_ = 0;
    execution_direction_ = ClockDirection::Future;
    signal_ = ClockSignal::QnanPositive;
    contradiction_ = false;
    tick_ = 0;
    cycle_start_ = 0;
    cycle_length_ = 0;
    memory_.fill(0);
    program_at_.fill(ClockState::Halt);
    event_count_ = 0;
    history_count_ = 0;

    program_at_[future_address_] = future_;
    memory_[future_address_] = 0x48414C54ull; // "HALT"
    history_[history_count_++] = future_;
    log(ClockEventKind::Allocate, future_address_, ClockDirection::Future,
        future_, ClockSignal::QnanPositive, past_address_);
}

void TemporalClock::log(ClockEventKind kind, std::int32_t address,
                        ClockDirection direction, ClockState state,
                        ClockSignal signal, std::int32_t target) {
    if (event_count_ >= kEventMax) return;
    ClockEvent& e = events_[event_count_++];
    e.tick = tick_;
    e.address = address;
    e.direction = direction;
    e.kind = kind;
    e.state = state;
    e.signal = signal;
    e.target = target;
}

void TemporalClock::execute_future() {
    future_ = program_at_[future_address_];
    log(ClockEventKind::Execute, future_address_, ClockDirection::Future,
        future_, signal_, past_address_);
    if (future_ == ClockState::Halt) {
        signal_ = ClockSignal::QnanPositive;
    } else {
        signal_ = ClockSignal::SnanNegative;
    }
    log(ClockEventKind::Signal, future_address_, ClockDirection::Future,
        future_, signal_, past_address_);
}

void TemporalClock::apply_past_feedback() {
    past_rewrite_ = (signal_ == ClockSignal::QnanPositive) ? ClockState::Loop
                                                           : ClockState::Halt;
    contradiction_ = (past_rewrite_ != future_);
    program_at_[future_address_] = past_rewrite_;
    log(ClockEventKind::Rewrite, past_address_, ClockDirection::Past,
        past_rewrite_, signal_, future_address_);
    if (contradiction_) {
        log(ClockEventKind::Contradiction, past_address_, ClockDirection::Past,
            future_, signal_, future_address_);
    }
}

void TemporalClock::step() {
    execute_future();
    apply_past_feedback();
    if (history_count_ < kHistoryMax) history_[history_count_++] = past_rewrite_;
    ++tick_;
}

bool TemporalClock::cycle(std::uint64_t& start, std::uint64_t& length) {
    if (history_count_ < 3) return false;
    const std::size_t n = history_count_;
    for (std::size_t len = 1; len <= n / 2; ++len) {
        const std::size_t a = n - len;
        const std::size_t b = a - len;
        bool equal = true;
        for (std::size_t i = 0; i < len; ++i) {
            if (history_[b + i] != history_[a + i]) {
                equal = false;
                break;
            }
        }
        if (equal) {
            start = b;
            length = len;
            cycle_start_ = b;
            cycle_length_ = len;
            return true;
        }
    }
    return false;
}

void TemporalClock::rewind_to(std::uint64_t tick) {
    init();
    for (std::uint64_t i = 0; i < tick; ++i) step();
}

bool TemporalClock::observe(const LogicalStamp& stamp) {
    if (stamp.tick <= tick_) return stamp.tick == tick_ && stamp.phase == phase();
    rewind_to(stamp.tick);
    return stamp.phase == phase();
}

void TemporalClock::run(std::size_t max_ticks) {
    for (std::size_t i = 0; i < max_ticks; ++i) {
        step();
        std::uint64_t start = 0, length = 0;
        if (cycle(start, length)) {
            log(ClockEventKind::Cycle, future_address_, ClockDirection::Future,
                future_, signal_, past_address_);
            return;
        }
    }
}

std::uint64_t TemporalClock::signal_bits() const {
    return signal_ == ClockSignal::QnanPositive ? kQnanPositive : kSnanNegative;
}

Hash256 TemporalClock::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'C', 'L', 'O', 'C', '1'};
    h.update(tag, sizeof(tag));
    const std::uint8_t future = static_cast<std::uint8_t>(future_);
    const std::uint8_t past = static_cast<std::uint8_t>(past_rewrite_);
    const std::uint8_t sig = static_cast<std::uint8_t>(signal_);
    h.update(&future, 1);
    h.update(&past, 1);
    h.update(&sig, 1);
    h.update(&contradiction_, sizeof(contradiction_));
    h.update(&tick_, sizeof(tick_));
    h.update(&cycle_start_, sizeof(cycle_start_));
    h.update(&cycle_length_, sizeof(cycle_length_));
    h.update(history_.data(), history_count_ * sizeof(history_[0]));
    for (std::size_t i = 0; i < event_count_; ++i) {
        const ClockEvent& e = events_[i];
        h.update(&e.tick, sizeof(e.tick));
        h.update(&e.address, sizeof(e.address));
        h.update(&e.direction, sizeof(e.direction));
        h.update(&e.kind, sizeof(e.kind));
        h.update(&e.state, sizeof(e.state));
        h.update(&e.signal, sizeof(e.signal));
        h.update(&e.target, sizeof(e.target));
    }
    return h.final();
}

} // namespace nanlm
