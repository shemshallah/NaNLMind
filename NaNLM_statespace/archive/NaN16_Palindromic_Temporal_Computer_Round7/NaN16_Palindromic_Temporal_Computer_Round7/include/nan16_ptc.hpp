#pragma once
// NaN16 Palindromic Temporal Computer — Round 4
// Address-derived spatial computer: cells, multi-geometry, arithmetic fields,
// Rule 110, dual-orientation, reversibility audit, fixed-point subsystem.

#include <algorithm>
#include <array>
#include <cstdint>
#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace nan16 {

constexpr std::uint32_t kAddressCount = 1u << 16;

inline std::uint16_t reverse16(std::uint16_t x) {
    std::uint16_t y = 0;
    for (int i = 0; i < 16; ++i) {
        y = static_cast<std::uint16_t>((y << 1) | (x & 1u));
        x = static_cast<std::uint16_t>(x >> 1);
    }
    return y;
}
inline std::uint16_t byte_swap16(std::uint16_t x) {
    return static_cast<std::uint16_t>((x << 8) | (x >> 8));
}
inline std::uint16_t four_transform(std::uint16_t x, unsigned mask) {
    if (mask & 1u) x = byte_swap16(x);
    if (mask & 2u) x = reverse16(x);
    return x;
}
inline std::uint16_t canonical_of(std::uint16_t a) {
    return std::min(a, reverse16(a));
}
inline bool is_bit_palindrome(std::uint16_t a) {
    return reverse16(a) == a;
}

enum class Orientation : std::uint8_t { Forward = 0, Reverse = 1 };
using Signal = std::uint8_t;

enum class NeighborKind : std::uint8_t {
    BitReverseMirror, ByteSwapImage, OrbitMate, Hamming1,
    LinearPrev, LinearNext, GenerationPred, GenerationSucc
};

struct NeighborRef {
    NeighborKind kind;
    std::uint16_t address;
    std::int8_t delta = 0;
};

enum class SyncKind : std::uint8_t {
    Always, GenerationMatch, SignalNonZero, NeighborAgree, Wavefront, Locked
};

struct Cell {
    std::uint16_t canonical = 0;
    std::uint16_t mirror = 0;
    Orientation orient = Orientation::Forward;
    std::uint64_t generation = 0;
    std::uint32_t state = 0;   // primary payload
    std::uint32_t aux = 0;     // dual-state / carry / rule-meta
    Signal signal = 0;
    std::uint8_t rule_id = 0;
    std::uint8_t flags = 0;    // bit0 fixed-point, bit1 locked, bit2 dual-state
    bool is_fixed_point() const { return (flags & 1u) != 0; }
    void set_fixed_point(bool v) { if (v) flags |= 1u; else flags &= ~1u; }
    bool is_dual() const { return (flags & 4u) != 0; }
    void set_dual(bool v) { if (v) flags |= 4u; else flags &= ~4u; }

    // Dual-state view: when dual, state=S+ (forward), aux=S- (reverse)
    std::uint32_t s_plus() const { return state; }
    std::uint32_t s_minus() const { return is_dual() ? aux : state; }
    void set_s_plus(std::uint32_t v) { state = v; }
    void set_s_minus(std::uint32_t v) { if (is_dual()) aux = v; else state = v; }
};

struct NeighborView {
    std::uint32_t state = 0;
    std::uint32_t aux = 0;
    Signal signal = 0;
    std::uint64_t generation = 0;
    bool present = false;
};

using RuleFn = std::function<void(Cell&, const NeighborView*, std::size_t, std::uint64_t)>;

enum RuleID : std::uint8_t {
    RuleIdentity = 0,
    RuleXorNeighbors = 1,
    RuleMajority = 2,
    Rule90 = 3,
    RuleReversibleXOR = 4,
    RuleSignalPropagate = 5,
    RuleConsensus = 6,
    RuleAddWave = 7,
    Rule110 = 8,
    RuleSubWave = 9,
    RuleCompareWave = 10,
    RuleCustom = 255
};

// Reversibility classification
enum class RevClass : std::uint8_t {
    FullyReversible,      // involution under frozen neighbors
    ConditionallyReversible,
    Irreversible,
    NeedsHistory
};

struct RuleMeta {
    const char* name;
    RevClass rev;
    const char* note;
};

// ---------------------------------------------------------------------------
// Topology
// ---------------------------------------------------------------------------
class Topology {
public:
    Topology();

    Cell& at_canonical(std::uint16_t c);
    const Cell& at_canonical(std::uint16_t c) const;
    Cell& at_address(std::uint16_t a);
    const Cell& at_address(std::uint16_t a) const;

    std::size_t cell_count() const { return cells_.size(); }
    std::uint64_t global_tick() const { return tick_; }

    std::vector<NeighborRef> neighbors_of(std::uint16_t canonical, NeighborKind kind) const;

    std::uint32_t step_synchronous();
    std::uint32_t step_wavefront();
    std::uint32_t step_rule90_line(std::uint16_t start, std::uint16_t length);
    std::uint32_t step_rule110_line(std::uint16_t start, std::uint16_t length);

    void set_rule(std::uint8_t id, RuleFn fn);
    void set_all_rule(std::uint8_t id);
    void clear_signals();

    // Seeding
    void seed_linear_rule90(std::uint16_t start, std::uint16_t length, std::uint32_t pattern);
    void seed_linear_rule110(std::uint16_t start, std::uint16_t length, const std::vector<std::uint8_t>& bits);
    void seed_adder(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits);
    void seed_subtractor(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits);
    void seed_compare(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits);

    // Arithmetic field helpers (linear embedding)
    std::uint32_t run_adder(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits, int max_steps = 64);
    std::uint32_t run_subtractor(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits, int max_steps = 64);
    int run_compare(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits, int max_steps = 64); // -1,0,+1

    // Shift-add multiplication field; product width = 2*bits
    std::uint64_t run_multiplier(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits);

    // Pure signal-carried ripple adder: carry travels only via signal + linear neighbor.
    struct SignalAddResult {
        std::uint32_t result = 0;
        int steps = 0;
        int hops = 0;
        bool ok = false;
    };
    SignalAddResult run_signal_adder(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits, int max_steps = 128);

    // Event-driven sparse step over a dirty address list.
    std::uint32_t step_event_driven(std::vector<std::uint16_t>& dirty);

    // Dual-orientation / simultaneous fields
    // Field A at start_a (forward), Field B at start_b (can use reverse orientation semantics)
    struct DualResult {
        std::uint32_t result_a;
        std::uint32_t result_b;
        bool a_ok;
        bool b_ok;
        int steps;
    };
    DualResult run_dual_adders(std::uint16_t start_a, std::uint32_t a0, std::uint32_t b0, int bits_a,
                               std::uint16_t start_b, std::uint32_t a1, std::uint32_t b1, int bits_b,
                               int max_steps = 64);

    // Dual-state / mirror-pair experiments (Round 7)
    // Enable dual-state on a canonical cell: S+=state, S-=aux
    void enable_dual(std::uint16_t canonical);
    void enable_dual_region(std::uint16_t start, std::uint16_t count);

    // Experiment 1: independence — transform only S+ or only S-, verify the other is untouched
    struct DualIndepResult {
        bool plus_changed = false;
        bool minus_changed = false;
        bool isolation_ok = false;  // the "other" side stayed fixed
        std::uint32_t plus_before = 0, plus_after = 0;
        std::uint32_t minus_before = 0, minus_after = 0;
    };
    DualIndepResult experiment_mirror_independence(std::uint16_t canonical, bool touch_plus);

    // Experiment 2: complementary — S+ := S+ XOR k; S- tracks inverse; recover original
    struct DualCompResult {
        bool recovered = false;
        std::uint32_t original = 0;
        std::uint32_t after_forward = 0;
        std::uint32_t after_inverse = 0;
    };
    DualCompResult experiment_complementary_xor(std::uint16_t canonical, std::uint32_t key);

    // Bulk: N dual cells, independent S+/S- random walks, count isolation failures
    struct DualBulkResult {
        std::uint32_t cells = 0;
        std::uint32_t steps = 0;
        std::uint32_t isolation_failures = 0;
        std::uint32_t complementary_ok = 0;
        std::uint32_t complementary_fail = 0;
    };
    DualBulkResult experiment_dual_bulk(std::uint16_t start, std::uint32_t n_cells, std::uint32_t steps);

    // Fixed-point subsystem
    std::vector<std::uint16_t> fixed_points() const;
    std::uint32_t count_active_near_fixed(std::uint16_t radius = 1) const;

    // Diagnostics
    std::uint32_t active_cells() const;
    std::uint64_t total_generation_sum() const;
    std::string snapshot_line(std::uint16_t from, std::uint16_t count) const;
    std::uint64_t state_hash() const;  // FNV-1a over all canonical states

    // Reversibility audit table
    static const RuleMeta* rule_meta(std::uint8_t id);

private:
    std::vector<Cell> cells_;
    std::vector<std::uint8_t> is_canonical_;
    std::array<RuleFn, 256> rules_{};
    std::uint64_t tick_ = 0;

    void ensure_rules();
    NeighborView view_of(std::uint16_t address) const;
};

// Built-in rules
void rule_identity(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_xor_neighbors(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_majority(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_90(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_reversible_xor(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_signal_propagate(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_consensus(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_add_wave(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_sub_wave(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_compare_wave(Cell&, const NeighborView*, std::size_t, std::uint64_t);

} // namespace nan16
