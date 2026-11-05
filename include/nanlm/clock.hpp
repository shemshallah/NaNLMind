// Deterministic temporal oscillator, derived from nanclock.zip.
//
// The original prototype is a 64-cell temporal memory:
//
//   address 0  = LE / PAST boundary
//   address 63 = BE / FUTURE boundary
//
// The future program is allocated at the BE boundary, executed, and a signal
// travels to LE/PAST; the past rewrites the future allocation cell. The seed
// is HALT and the deliberate feedback rule is:
//
//   future HALT -> +qNaN -> past rewrites future to LOOP
//   future LOOP -> -sNaN -> past rewrites future to HALT
//
// so the temporal orbit is HALT -> +qNaN -> LOOP -> -sNaN -> HALT -> ...
//
// This module is a field of the one global topology, not a separate machine.
// It provides a deterministic global epoch/phase for the 256-Head Array. The
// period-2 orbit is a heartbeat, not a claim of time travel or hypercomputation.
#pragma once

#include "nanlm/sha256.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace nanlm {

enum class ClockState : std::uint8_t { Halt = 0, Loop = 1 };
enum class ClockSignal : std::uint8_t { QnanPositive = 0, SnanNegative = 1 };
enum class ClockDirection : std::int8_t { Past = -1, Future = 1 };
enum class ClockEventKind : std::uint8_t {
    Allocate = 0,
    Execute = 1,
    Signal = 2,
    Rewrite = 3,
    Contradiction = 4,
    Cycle = 5,
};

struct LogicalStamp {
    std::uint64_t tick = 0;
    std::uint8_t phase = 0; // 0 = +qNaN, 1 = -sNaN

    bool operator<(const LogicalStamp& other) const {
        return tick != other.tick ? tick < other.tick : phase < other.phase;
    }
    bool operator==(const LogicalStamp& other) const {
        return tick == other.tick && phase == other.phase;
    }
};

struct ClockEvent {
    std::uint64_t tick = 0;
    std::int32_t address = 0;
    ClockDirection direction = ClockDirection::Future;
    ClockEventKind kind = ClockEventKind::Allocate;
    ClockState state = ClockState::Halt;
    ClockSignal signal = ClockSignal::QnanPositive;
    std::int32_t target = 0;
};

class TemporalClock {
public:
    static constexpr int kCells = 64;
    static constexpr std::size_t kHistoryMax = 256;
    static constexpr std::size_t kEventMax = 512;

    // Exact NaN bit patterns from the prototype. They are integers, never
    // used as floating-point arithmetic values.
    static constexpr std::uint64_t kQnanPositive = 0x7FF8000000000000ull;
    static constexpr std::uint64_t kSnanNegative = 0xFFF0000000000001ull;

    TemporalClock();

    void init();
    void step();
    void run(std::size_t max_ticks);

    // Logical time, not wall time. A stamp orders events across replicas
    // without any claim about nanoseconds or milliseconds.
    LogicalStamp stamp() const { return LogicalStamp{tick_, static_cast<std::uint8_t>(signal_)}; }
    void rewind_to(std::uint64_t tick);
    bool observe(const LogicalStamp& stamp);

    bool cycle(std::uint64_t& start, std::uint64_t& length);

    std::uint64_t tick() const { return tick_; }
    ClockState future() const { return future_; }
    ClockState past_rewrite() const { return past_rewrite_; }
    ClockSignal signal() const { return signal_; }
    std::uint64_t signal_bits() const;
    bool contradiction() const { return contradiction_; }
    std::uint32_t phase() const {
        return static_cast<std::uint32_t>(signal_);
    }

    const ClockEvent* events() const { return events_.data(); }
    std::size_t event_count() const { return event_count_; }
    std::size_t history_count() const { return history_count_; }
    ClockState history_at(std::size_t i) const { return history_[i]; }

    Hash256 digest() const;

private:
    void log(ClockEventKind kind, std::int32_t address, ClockDirection direction,
             ClockState state, ClockSignal signal, std::int32_t target);
    void execute_future();
    void apply_past_feedback();

    ClockState future_ = ClockState::Halt;
    ClockState past_rewrite_ = ClockState::Halt;
    std::int32_t future_address_ = kCells - 1;
    std::int32_t past_address_ = 0;
    ClockDirection execution_direction_ = ClockDirection::Future;
    ClockSignal signal_ = ClockSignal::QnanPositive;
    bool contradiction_ = false;
    std::uint64_t tick_ = 0;
    std::uint64_t cycle_start_ = 0;
    std::uint64_t cycle_length_ = 0;

    std::array<std::uint64_t, kCells> memory_{};
    std::array<ClockState, kCells> program_at_{};
    std::array<ClockEvent, kEventMax> events_{};
    std::size_t event_count_ = 0;
    std::array<ClockState, kHistoryMax> history_{};
    std::size_t history_count_ = 0;
};

const char* clock_state_name(ClockState state);
const char* clock_signal_name(ClockSignal signal);
const char* clock_direction_name(ClockDirection direction);
const char* clock_event_name(ClockEventKind kind);

} // namespace nanlm
