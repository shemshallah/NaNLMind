// The 256-Head Array / Palindromic Head Layer.
//
// One canonical head implementation is instantiated exactly 256 times, once
// per palindromic 16-bit address. The instances are *views* over the one
// Universe: they do not own private semantic state spaces. Each head owns its
// address identity, local phase/energy, topology links, runner handoff, and a
// local history cache; the global ledger remains the authority.
#pragma once

#include "nanlm/clock.hpp"
#include "nanlm/temporal.hpp"
#include "nanlm/universe.hpp"

#include <array>
#include <cstdint>
#include <functional>
#include <string>

namespace nanlm {

struct HeadAddress {
    std::uint16_t value = 0;

    static constexpr HeadAddress from_index(std::uint8_t i) {
        return HeadAddress{matrix_addr(i, i)};
    }
    static constexpr bool valid(std::uint16_t a) { return is_palindrome16(a); }
    constexpr std::uint8_t index() const { return matrix_row(value); }
    constexpr bool operator==(const HeadAddress& other) const { return value == other.value; }
};

// QNaN/SNaN phase classes, mapped to the four NaN types.
enum class HeadPhase : std::uint8_t {
    QuietPositive = 0,
    QuietNegative = 1,
    SignalingPositive = 2,
    SignalingNegative = 3,
};

constexpr NanType nan_type_of(HeadPhase p) {
    switch (p) {
        case HeadPhase::QuietPositive: return NanType::QuietPositive;
        case HeadPhase::QuietNegative: return NanType::QuietNegative;
        case HeadPhase::SignalingPositive: return NanType::SignalPositive;
        case HeadPhase::SignalingNegative: return NanType::SignalNegative;
    }
    return NanType::QuietPositive;
}

constexpr HeadPhase phase_of(NanType t) {
    switch (t) {
        case NanType::QuietPositive: return HeadPhase::QuietPositive;
        case NanType::QuietNegative: return HeadPhase::QuietNegative;
        case NanType::SignalPositive: return HeadPhase::SignalingPositive;
        case NanType::SignalNegative: return HeadPhase::SignalingNegative;
    }
    return HeadPhase::QuietPositive;
}

struct HeadLinks {
    std::uint16_t row_head = 0xFFFFu;
    std::uint16_t row_count = 0;
    std::uint16_t col_head = 0xFFFFu;
    std::uint16_t col_count = 0;

    std::uint16_t total() const {
        return static_cast<std::uint16_t>(row_count + col_count);
    }
};

struct HeadEvent {
    std::uint64_t epoch = 0;
    std::uint8_t kind = 0;
    std::uint32_t phase = 0;
    std::uint32_t energy = 0;
    std::uint64_t before = 0;
    std::uint64_t after = 0;
};

// A small local ring. It is a cache for diagnostics; the one global ledger is
// the authoritative history.
class HeadHistory {
public:
    static constexpr std::size_t kCapacity = 32;

    void record(const HeadEvent& event);
    void clear();
    std::size_t size() const { return count_; }
    const HeadEvent& at(std::size_t i) const;
    Hash256 digest() const;

private:
    std::array<HeadEvent, kCapacity> events_{};
    std::uint8_t count_ = 0;
    std::uint8_t next_ = 0;
};

class HeadArray;

class HeadView {
public:
    HeadView(HeadArray& array, std::uint8_t index) : array_(&array), index_(index) {}

    std::uint8_t index() const { return index_; }
    HeadAddress address() const;
    Head& record();
    const Head& record() const;
    NanCell& cell();
    const NanCell& cell() const;

    HeadLinks links() const;
    bool adjacent_to(std::uint8_t other) const;

    std::uint8_t transform_phase() const;
    void set_transform_phase(std::uint8_t phase);
    void advance_transform_phase();
    std::uint16_t self_error() const;
    std::uint8_t error_streak() const;
    std::uint16_t scratch_used() const;
    void set_self_error(std::uint16_t error);
    void note_self_model_error(std::uint16_t error, std::uint16_t threshold,
                               std::uint8_t required_streak);
    void note_scratch_used(std::uint16_t used);
    bool should_grow(std::uint16_t error_threshold, std::uint8_t required_streak,
                     std::uint16_t scratch_threshold) const;
    bool has_child() const;
    void mark_grown();

    HeadPhase phase() const;
    void set_phase(HeadPhase phase);
    void phase_step(std::uint32_t delta);
    void refresh();

    // Local scratchpad: 256 B local + 768 B work, per head.
    HeadScratch& scratch();
    const HeadScratch& scratch() const;

    // Boolean self-modification. The head owns a 16-bit operator mask and a
    // selected rule; a patch is a capability-gated XOR of the mask. The
    // selected rule becomes the lowest enabled function.
    std::uint16_t boolean_mask() const;
    std::uint8_t boolean_rule() const;
    bool set_boolean_mask(std::uint16_t mask);
    bool self_modify_boolean(std::uint16_t patch);
    std::uint32_t eval_boolean_from_scratch();

    // Integer score learning over the 16 Boolean functions. Scores live in
    // scratch.work()[16..47] as 16 little-endian int16 values. No gradients.
    void reset_boolean_learner();
    void train_boolean(std::uint32_t a, std::uint32_t b, bool target);
    std::int16_t boolean_score(std::uint8_t op) const;
    std::uint16_t learned_mask() const;

    HeadHistory& history();
    const HeadHistory& history() const;

private:
    HeadArray* array_;
    std::uint8_t index_;
};

struct HeadToken {
    std::uint16_t id = 0;
    std::uint32_t payload = 0;
    std::uint64_t epoch = 0;
    std::uint32_t phase = 0;
};

struct RunnerResult {
    bool ok = false;
    bool modified = false;
    std::uint8_t next = 0;
    HeadToken out{};
    std::string error;
};

// One canonical runner. It advances a head within one object; it is not a
// thread and it does not create a private state space.
class HeadRunner {
public:
    HeadRunner(HeadArray& heads, PageId chart, BidirectionalMemory* temporal = nullptr,
               TemporalClock* clock = nullptr)
        : heads_(&heads), chart_(std::move(chart)), temporal_(temporal), clock_(clock) {}

    RunnerResult run(std::uint8_t head, const HeadToken& token);

private:
    HeadArray* heads_;
    PageId chart_;
    BidirectionalMemory* temporal_;
    TemporalClock* clock_;
};

// Exact before/after frame for inverse computation. The frame stores the full
// cell, head record, and 1 KiB scratchpad, so a head can be restored without
// guessing what a Boolean function did.
struct HeadFrame {
    std::uint8_t head = 0;
    NanCell before_cell{};
    Head before_head{};
    HeadScratch before_scratch{};
    NanCell after_cell{};
    Head after_head{};
    HeadScratch after_scratch{};
    bool has_after = false;
};

HeadFrame capture_head(HeadView& view);
void capture_after(HeadFrame& frame, HeadView& view);
void restore_before(HeadView& view, const HeadFrame& frame);
void restore_after(HeadView& view, const HeadFrame& frame);

// Reverse/forward frame computation. These are named aliases so a
// contemplation cycle reads as: forward -> reverse -> compare -> commit.
void compute_reverse_frame(HeadView& view, const HeadFrame& frame);
void compute_forward_frame(HeadView& view, const HeadFrame& frame);
std::uint64_t frame_hash(const HeadFrame& frame, bool after);

using HeadMutation = std::function<void(HeadView&)>;

struct ContemplationResult {
    bool ok = false;         // the inverse restored the before-state exactly
    bool inverse_ok = false;
    bool committed = false;  // true = after-frame kept, false = before-frame kept
    std::uint64_t forward_hash = 0;
    std::uint64_t inverse_hash = 0;
    std::string error;
};

// Contemplate one candidate mutation. The head is always left in a known
// state: the after-frame if commit, otherwise the exact before-frame.
ContemplationResult contemplate(HeadView& view, const HeadMutation& mutation,
                                bool commit);

class HeadArray {
public:
    // One implementation id for all 256 instances. The registry rejects a
    // head that claims a different implementation.
    static constexpr std::uint32_t kImplementationId = 0x4E414831u; // "NAH1"

    HeadArray(Universe& universe, PageId chart);

    static constexpr std::size_t size() { return kHeadCount; }
    HeadView at(std::uint8_t index);
    HeadView by_address(std::uint16_t address);

    HeadHistory& history(std::uint8_t index) { return histories_[index & 255u]; }
    const HeadHistory& history(std::uint8_t index) const { return histories_[index & 255u]; }

    bool verify(std::string* error = nullptr) const;
    Hash256 digest() const;
    Hash256 history_digest() const;

    Universe& universe() { return *universe_; }
    const Universe& universe() const { return *universe_; }
    const PageId& chart() const { return chart_; }

private:
    Universe* universe_;
    PageId chart_;
    std::array<HeadHistory, kHeadCount> histories_{};
};

} // namespace nanlm
