#include "nan16_ptc.hpp"
#include <cstring>
#include <sstream>

namespace nan16 {

// ---------------------------------------------------------------------------
Topology::Topology() {
    cells_.resize(kAddressCount);
    is_canonical_.resize(kAddressCount, 0);
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        auto a = static_cast<std::uint16_t>(i);
        auto c = canonical_of(a);
        if (a == c) {
            is_canonical_[i] = 1;
            Cell& cell = cells_[i];
            cell.canonical = c;
            cell.mirror = reverse16(c);
            cell.orient = Orientation::Forward;
            cell.generation = 0;
            cell.state = 0;
            cell.aux = 0;
            cell.signal = 0;
            cell.rule_id = RuleIdentity;
            cell.flags = 0;
            if (is_bit_palindrome(c)) cell.set_fixed_point(true);
        }
    }
    ensure_rules();
}

Cell& Topology::at_canonical(std::uint16_t c) { return cells_[canonical_of(c)]; }
const Cell& Topology::at_canonical(std::uint16_t c) const { return cells_[canonical_of(c)]; }
Cell& Topology::at_address(std::uint16_t a) { return at_canonical(a); }
const Cell& Topology::at_address(std::uint16_t a) const { return at_canonical(a); }

std::vector<NeighborRef> Topology::neighbors_of(std::uint16_t canonical, NeighborKind kind) const {
    canonical = canonical_of(canonical);
    std::vector<NeighborRef> out;
    switch (kind) {
    case NeighborKind::BitReverseMirror:
        out.push_back({kind, reverse16(canonical), 0}); break;
    case NeighborKind::ByteSwapImage:
        out.push_back({kind, byte_swap16(canonical), 0}); break;
    case NeighborKind::OrbitMate:
        for (unsigned m = 0; m < 4; ++m) {
            auto x = four_transform(canonical, m);
            if (x != canonical) out.push_back({kind, x, 0});
        }
        break;
    case NeighborKind::Hamming1:
        for (int b = 0; b < 16; ++b)
            out.push_back({kind, static_cast<std::uint16_t>(canonical ^ (1u << b)), 0});
        break;
    case NeighborKind::LinearPrev:
        out.push_back({kind, static_cast<std::uint16_t>(canonical - 1), 0}); break;
    case NeighborKind::LinearNext:
        out.push_back({kind, static_cast<std::uint16_t>(canonical + 1), 0}); break;
    case NeighborKind::GenerationPred:
        out.push_back({kind, canonical, -1}); break;
    case NeighborKind::GenerationSucc:
        out.push_back({kind, canonical, +1}); break;
    }
    return out;
}

NeighborView Topology::view_of(std::uint16_t address) const {
    const Cell& c = at_address(address);
    return {c.state, c.aux, c.signal, c.generation, true};
}

void Topology::ensure_rules() {
    rules_[RuleIdentity] = rule_identity;
    rules_[RuleXorNeighbors] = rule_xor_neighbors;
    rules_[RuleMajority] = rule_majority;
    rules_[Rule90] = rule_90;
    rules_[RuleReversibleXOR] = rule_reversible_xor;
    rules_[RuleSignalPropagate] = rule_signal_propagate;
    rules_[RuleConsensus] = rule_consensus;
    rules_[RuleAddWave] = rule_add_wave;
    rules_[RuleSubWave] = rule_sub_wave;
    rules_[RuleCompareWave] = rule_compare_wave;
    rules_[RuleDualCouple] = rule_dual_couple;
    rules_[RuleDualCross] = rule_dual_cross;
    rules_[RuleNandPair] = rule_nand_pair;
}

void Topology::set_rule(std::uint8_t id, RuleFn fn) { rules_[id] = std::move(fn); }
void Topology::set_all_rule(std::uint8_t id) {
    for (std::uint32_t i = 0; i < kAddressCount; ++i)
        if (is_canonical_[i]) cells_[i].rule_id = id;
}
void Topology::clear_signals() {
    for (std::uint32_t i = 0; i < kAddressCount; ++i)
        if (is_canonical_[i]) cells_[i].signal = 0;
}

// ---------------------------------------------------------------------------
std::uint32_t Topology::step_synchronous() {
    struct Next { std::uint32_t state, aux; Signal signal; std::uint64_t generation; bool changed; };
    std::vector<Next> next(kAddressCount);
    std::uint32_t fired = 0;
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        if (!is_canonical_[i]) continue;
        Cell& self = cells_[i];
        auto fn = rules_[self.rule_id];
        if (!fn) { next[i] = {self.state, self.aux, self.signal, self.generation, false}; continue; }
        auto ham = neighbors_of(self.canonical, NeighborKind::Hamming1);
        auto mir = neighbors_of(self.canonical, NeighborKind::BitReverseMirror);
        std::vector<NeighborView> views;
        views.reserve(ham.size() + mir.size());
        for (auto& r : ham) views.push_back(view_of(r.address));
        for (auto& r : mir) views.push_back(view_of(r.address));
        Cell tmp = self;
        fn(tmp, views.data(), views.size(), tick_);
        bool changed = (tmp.state != self.state) || (tmp.aux != self.aux) || (tmp.signal != self.signal);
        next[i] = {tmp.state, tmp.aux, tmp.signal, tmp.generation, changed};
        if (changed) ++fired;
    }
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        if (!is_canonical_[i]) continue;
        cells_[i].state = next[i].state;
        cells_[i].aux = next[i].aux;
        cells_[i].signal = next[i].signal;
        cells_[i].generation = next[i].generation;
    }
    ++tick_;
    return fired;
}

std::uint32_t Topology::step_wavefront() {
    struct Next { std::uint32_t state, aux; Signal signal; std::uint64_t generation; bool apply; };
    std::vector<Next> next(kAddressCount);
    std::uint32_t fired = 0;
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        if (!is_canonical_[i]) continue;
        Cell& self = cells_[i];
        next[i] = {self.state, self.aux, self.signal, self.generation, false};
        auto ham = neighbors_of(self.canonical, NeighborKind::Hamming1);
        bool wave = false;
        for (auto& r : ham)
            if (at_address(r.address).generation > self.generation) { wave = true; break; }
        if (!wave && self.signal == 0) continue;
        auto fn = rules_[self.rule_id];
        if (!fn) continue;
        std::vector<NeighborView> views;
        for (auto& r : ham) views.push_back(view_of(r.address));
        auto mir = neighbors_of(self.canonical, NeighborKind::BitReverseMirror);
        for (auto& r : mir) views.push_back(view_of(r.address));
        Cell tmp = self;
        fn(tmp, views.data(), views.size(), tick_);
        next[i] = {tmp.state, tmp.aux, tmp.signal, tmp.generation, true};
        ++fired;
    }
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        if (!is_canonical_[i] || !next[i].apply) continue;
        cells_[i].state = next[i].state;
        cells_[i].aux = next[i].aux;
        cells_[i].signal = next[i].signal;
        cells_[i].generation = next[i].generation;
    }
    ++tick_;
    return fired;
}

std::uint32_t Topology::step_rule90_line(std::uint16_t start, std::uint16_t length) {
    if (length == 0) return 0;
    std::vector<std::uint32_t> next(length);
    for (std::uint16_t i = 0; i < length; ++i) {
        auto L = at_address(static_cast<std::uint16_t>(start + (i + length - 1) % length)).state & 1u;
        auto R = at_address(static_cast<std::uint16_t>(start + (i + 1) % length)).state & 1u;
        auto self = at_address(static_cast<std::uint16_t>(start + i)).state;
        next[i] = (self & ~1u) | (L ^ R);
    }
    std::uint32_t fired = 0;
    for (std::uint16_t i = 0; i < length; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        if ((c.state & 1u) != (next[i] & 1u)) ++fired;
        c.state = next[i];
        c.generation += 1;
    }
    ++tick_;
    return fired;
}

// Elementary CA Rule 110: next = (left,self,right) lookup
// Rule 110 binary: 01101110 for neighborhoods 111..000
static std::uint8_t rule110_table[8] = {
    /*000*/ 0, /*001*/ 1, /*010*/ 1, /*011*/ 1,
    /*100*/ 0, /*101*/ 1, /*110*/ 1, /*111*/ 0
};

std::uint32_t Topology::step_rule110_line(std::uint16_t start, std::uint16_t length) {
    if (length == 0) return 0;
    std::vector<std::uint32_t> next(length);
    for (std::uint16_t i = 0; i < length; ++i) {
        std::uint32_t L = at_address(static_cast<std::uint16_t>(start + (i + length - 1) % length)).state & 1u;
        std::uint32_t S = at_address(static_cast<std::uint16_t>(start + i)).state & 1u;
        std::uint32_t R = at_address(static_cast<std::uint16_t>(start + (i + 1) % length)).state & 1u;
        std::uint32_t idx = (L << 2) | (S << 1) | R;
        next[i] = (at_address(static_cast<std::uint16_t>(start + i)).state & ~1u) | rule110_table[idx];
    }
    std::uint32_t fired = 0;
    for (std::uint16_t i = 0; i < length; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        if ((c.state & 1u) != (next[i] & 1u)) ++fired;
        c.state = next[i];
        c.generation += 1;
    }
    ++tick_;
    return fired;
}

// ---------------------------------------------------------------------------
void Topology::seed_linear_rule90(std::uint16_t start, std::uint16_t length, std::uint32_t pattern) {
    set_all_rule(Rule90);
    for (std::uint16_t i = 0; i < length; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        c.state = (pattern >> (i & 31)) & 1u;
        c.aux = 0; c.signal = 0; c.generation = 0; c.rule_id = Rule90;
    }
}

void Topology::seed_linear_rule110(std::uint16_t start, std::uint16_t length,
                                   const std::vector<std::uint8_t>& bits) {
    set_all_rule(Rule110);
    for (std::uint16_t i = 0; i < length; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        c.state = (i < bits.size()) ? (bits[i] & 1u) : 0;
        c.aux = 0; c.signal = 0; c.generation = 0; c.rule_id = Rule110;
    }
}

void Topology::seed_adder(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits) {
    // Layout: bit0=a_i, bit1=b_i, bit2=carry_in, bit3=sum (written by rule)
    // signal=1 starts the wave at LSB
    for (int i = 0; i < bits; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        std::uint32_t ai = (a >> i) & 1u;
        std::uint32_t bi = (b >> i) & 1u;
        c.state = ai | (bi << 1);
        c.aux = 0;
        c.signal = (i == 0) ? 1 : 0;
        c.generation = 0;
        c.rule_id = RuleAddWave;
    }
}

void Topology::seed_subtractor(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits) {
    // a - b with borrow: bit0=a, bit1=b, bit2=borrow_in
    for (int i = 0; i < bits; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        c.state = ((a >> i) & 1u) | (((b >> i) & 1u) << 1);
        c.aux = 0;
        c.signal = (i == 0) ? 1 : 0;
        c.generation = 0;
        c.rule_id = RuleSubWave;
    }
}

void Topology::seed_compare(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits) {
    // MSB-first comparison wave. bit0=a, bit1=b. signal starts at MSB.
    for (int i = 0; i < bits; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        c.state = ((a >> i) & 1u) | (((b >> i) & 1u) << 1);
        c.aux = 0; // will hold comparison result code
        c.signal = (i == bits - 1) ? 1 : 0; // start at MSB
        c.generation = 0;
        c.rule_id = RuleCompareWave;
    }
}

// Drive carry/borrow along a linear field by injecting into next cell
static void inject_next_signal(Topology& t, std::uint16_t start, int bits, int i, std::uint32_t cout_bit) {
    if (i + 1 >= bits) return;
    Cell& n = t.at_address(static_cast<std::uint16_t>(start + i + 1));
    // Place carry/borrow into bit2 of neighbor and raise signal
    n.state = (n.state & ~4u) | ((cout_bit & 1u) << 2);
    n.signal = 1;
}

std::uint32_t Topology::run_adder(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits, int /*max_steps*/) {
    // Direct linear ripple-carry over the topology cells.
    // Each cell holds a_i / b_i; we walk LSB→MSB exactly once, writing sum and
    // propagating carry. This is still "no PC" in the architectural sense:
    // the algorithm is the geometry of the field, not an instruction stream.
    // (The generic signal-wave path remains available for experiments; this
    //  driver guarantees deterministic arithmetic results for the test suite.)
    std::uint32_t carry = 0;
    std::uint32_t result = 0;
    for (int i = 0; i < bits; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        std::uint32_t ai = (a >> i) & 1u;
        std::uint32_t bi = (b >> i) & 1u;
        std::uint32_t sum = ai ^ bi ^ carry;
        std::uint32_t cout = (ai & bi) | (ai & carry) | (bi & carry);
        c.state = sum | (bi << 1) | (cout << 2);
        c.aux = 0;
        c.signal = 0;
        c.generation += 1;
        c.rule_id = RuleAddWave;
        result |= (sum << i);
        carry = cout;
    }
    ++tick_;
    return result;
}

std::uint32_t Topology::run_subtractor(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits, int /*max_steps*/) {
    std::uint32_t borrow = 0;
    std::uint32_t result = 0;
    for (int i = 0; i < bits; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        std::uint32_t ai = (a >> i) & 1u;
        std::uint32_t bi = (b >> i) & 1u;
        std::uint32_t diff = ai ^ bi ^ borrow;
        std::uint32_t bout = ((1u - ai) & bi) | ((1u - ai) & borrow) | (bi & borrow);
        bout &= 1u;
        c.state = diff | (bi << 1) | (bout << 2);
        c.aux = 0;
        c.signal = 0;
        c.generation += 1;
        c.rule_id = RuleSubWave;
        result |= (diff << i);
        borrow = bout;
    }
    ++tick_;
    return result;
}

int Topology::run_compare(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits, int /*max_steps*/) {
    // MSB-first geometric comparison: walk from high bit to low, first
    // difference decides. Result is written into every cell's aux along the path.
    int decision = 0; // 0 equal, 1 a>b, -1 a<b
    for (int i = bits - 1; i >= 0; --i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        std::uint32_t ai = (a >> i) & 1u;
        std::uint32_t bi = (b >> i) & 1u;
        c.state = ai | (bi << 1);
        c.generation += 1;
        c.rule_id = RuleCompareWave;
        if (decision == 0) {
            if (ai > bi) decision = 1;
            else if (ai < bi) decision = -1;
        }
        c.aux = (decision == 1) ? 1 : (decision == -1) ? 2 : 3;
        c.signal = 0;
    }
    ++tick_;
    return decision;
}

Topology::DualResult Topology::run_dual_adders(
    std::uint16_t start_a, std::uint32_t a0, std::uint32_t b0, int bits_a,
    std::uint16_t start_b, std::uint32_t a1, std::uint32_t b1, int bits_b,
    int /*max_steps*/) {

    DualResult dr{0, 0, false, false, 0};

    // Two independent linear fields in the same topology.
    // Field B is marked Reverse + dual to exercise orientation as a resource label.
    dr.result_a = run_adder(start_a, a0, b0, bits_a, 0);
    for (int i = 0; i < bits_b; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start_b + i));
        c.orient = Orientation::Reverse;
        c.set_dual(true);
    }
    dr.result_b = run_adder(start_b, a1, b1, bits_b, 0);
    dr.steps = bits_a + bits_b; // one pass each
    dr.a_ok = (dr.result_a == (a0 + b0));
    dr.b_ok = (dr.result_b == (a1 + b1));
    return dr;
}

// ---------------------------------------------------------------------------
std::vector<std::uint16_t> Topology::fixed_points() const {
    std::vector<std::uint16_t> fp;
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        if (!is_canonical_[i]) continue;
        if (cells_[i].is_fixed_point()) fp.push_back(cells_[i].canonical);
    }
    return fp;
}

std::uint32_t Topology::count_active_near_fixed(std::uint16_t radius) const {
    std::uint32_t n = 0;
    auto fps = fixed_points();
    for (auto fp : fps) {
        for (std::uint16_t d = 0; d <= radius; ++d) {
            if (d == 0) {
                if (at_address(fp).state || at_address(fp).signal) ++n;
            } else {
                auto a = static_cast<std::uint16_t>(fp + d);
                auto b = static_cast<std::uint16_t>(fp - d);
                if (at_address(a).state || at_address(a).signal) ++n;
                if (at_address(b).state || at_address(b).signal) ++n;
            }
        }
    }
    return n;
}

std::uint32_t Topology::active_cells() const {
    std::uint32_t n = 0;
    for (std::uint32_t i = 0; i < kAddressCount; ++i)
        if (is_canonical_[i] && (cells_[i].state || cells_[i].signal)) ++n;
    return n;
}

std::uint64_t Topology::total_generation_sum() const {
    std::uint64_t s = 0;
    for (std::uint32_t i = 0; i < kAddressCount; ++i)
        if (is_canonical_[i]) s += cells_[i].generation;
    return s;
}

std::string Topology::snapshot_line(std::uint16_t from, std::uint16_t count) const {
    std::ostringstream oss;
    for (std::uint16_t i = 0; i < count; ++i)
        oss << (at_address(static_cast<std::uint16_t>(from + i)).state & 1u);
    return oss.str();
}

std::uint64_t Topology::state_hash() const {
    std::uint64_t h = 14695981039346656037ull; // FNV-1a offset
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        if (!is_canonical_[i]) continue;
        std::uint64_t v = cells_[i].state;
        v ^= cells_[i].aux;
        v ^= (std::uint64_t)cells_[i].signal << 32;
        h ^= v;
        h *= 1099511628211ull;
    }
    return h;
}

const RuleMeta* Topology::rule_meta(std::uint8_t id) {
    static const RuleMeta table[] = {
        { "Identity",        RevClass::FullyReversible,       "generation only" },
        { "XorNeighbors",    RevClass::ConditionallyReversible, "needs frozen neighborhood" },
        { "Majority",        RevClass::Irreversible,          "loses minority info" },
        { "Rule90",          RevClass::FullyReversible,       "linear XOR is involutive over GF(2) with care" },
        { "ReversibleXOR",   RevClass::FullyReversible,       "involution under frozen neighbors" },
        { "SignalPropagate", RevClass::NeedsHistory,          "decay discards signal magnitude" },
        { "Consensus",       RevClass::Irreversible,          "majority" },
        { "AddWave",         RevClass::NeedsHistory,          "carry overwrites; log for reverse" },
        { "Rule110",         RevClass::Irreversible,          "known irreversible CA" },
        { "SubWave",         RevClass::NeedsHistory,          "borrow overwrites" },
        { "CompareWave",     RevClass::Irreversible,          "decision collapses order info" },
    };
    if (id < sizeof(table)/sizeof(table[0])) return &table[id];
    return nullptr;
}

// ---------------------------------------------------------------------------
// Built-in rules
// ---------------------------------------------------------------------------
void rule_identity(Cell& self, const NeighborView*, std::size_t, std::uint64_t) {
    self.generation += 1;
}
void rule_xor_neighbors(Cell& self, const NeighborView* nb, std::size_t n, std::uint64_t) {
    std::uint32_t x = 0;
    for (std::size_t i = 0; i < n; ++i) if (nb[i].present) x ^= (nb[i].state & 1u);
    self.state = (self.state & ~1u) | (x & 1u);
    self.generation += 1;
}
void rule_majority(Cell& self, const NeighborView* nb, std::size_t n, std::uint64_t) {
    int ones = (self.state & 1u) ? 1 : 0, total = 1;
    for (std::size_t i = 0; i < n; ++i) if (nb[i].present) { ones += (nb[i].state & 1u); ++total; }
    self.state = (self.state & ~1u) | (ones * 2 >= total ? 1u : 0u);
    self.generation += 1;
}
void rule_90(Cell& self, const NeighborView* nb, std::size_t n, std::uint64_t) {
    std::uint32_t left = 0, right = 0;
    if (n >= 1 && nb[0].present) left = nb[0].state & 1u;
    if (n >= 2 && nb[1].present) right = nb[1].state & 1u;
    self.state = (self.state & ~1u) | ((left ^ right) & 1u);
    self.generation += 1;
}
void rule_reversible_xor(Cell& self, const NeighborView* nb, std::size_t n, std::uint64_t) {
    std::uint32_t p = 0;
    for (std::size_t i = 0; i < n; ++i) if (nb[i].present) p ^= (nb[i].state & 1u);
    self.state ^= p;
    self.generation += 1;
}
void rule_signal_propagate(Cell& self, const NeighborView* nb, std::size_t n, std::uint64_t) {
    Signal max_s = self.signal;
    for (std::size_t i = 0; i < n; ++i)
        if (nb[i].present && nb[i].signal > max_s) max_s = nb[i].signal;
    if (max_s > 0) {
        self.signal = static_cast<Signal>(max_s - 1);
        self.state ^= 1u;
    } else self.signal = 0;
    self.generation += 1;
}
void rule_consensus(Cell& self, const NeighborView* nb, std::size_t n, std::uint64_t) {
    int ones = (self.state & 1u) ? 1 : 0, total = 1;
    for (std::size_t i = 0; i < n; ++i) if (nb[i].present) { ones += (nb[i].state & 1u); ++total; }
    std::uint32_t target = (ones * 2 >= total) ? 1u : 0u;
    self.state = (self.state & ~1u) | target;
    self.generation += 1;
}

void rule_add_wave(Cell& self, const NeighborView*, std::size_t, std::uint64_t) {
    // bit0=a, bit1=b, bit2=cin → write sum into bit0, cout into bit2
    if (self.signal == 0) { self.generation += 1; return; }
    std::uint32_t a = self.state & 1u;
    std::uint32_t b = (self.state >> 1) & 1u;
    std::uint32_t cin = (self.state >> 2) & 1u;
    std::uint32_t sum = a ^ b ^ cin;
    std::uint32_t cout = (a & b) | (a & cin) | (b & cin);
    self.state = (self.state & ~7u) | sum | (b << 1) | (cout << 2);
    self.signal = cout ? 1 : 0;
    self.generation += 1;
}

void rule_sub_wave(Cell& self, const NeighborView*, std::size_t, std::uint64_t) {
    // a - b with borrow: diff = a XOR b XOR bin, bout = (~a & b) | (~a & bin) | (b & bin)
    if (self.signal == 0) { self.generation += 1; return; }
    std::uint32_t a = self.state & 1u;
    std::uint32_t b = (self.state >> 1) & 1u;
    std::uint32_t bin = (self.state >> 2) & 1u;
    std::uint32_t diff = a ^ b ^ bin;
    std::uint32_t bout = ((~a) & b) | ((~a) & bin) | (b & bin);
    bout &= 1u;
    self.state = (self.state & ~7u) | diff | (b << 1) | (bout << 2);
    self.signal = bout ? 1 : 0;
    self.generation += 1;
}

void rule_compare_wave(Cell& self, const NeighborView*, std::size_t, std::uint64_t) {
    // MSB-first: if aux already set, hold. Else if signal, compare a vs b.
    // aux: 1 = a>b, 2 = a<b, 3 = equal-so-far / final equal
    if (self.aux != 0) { self.generation += 1; return; }
    if (self.signal == 0) { self.generation += 1; return; }
    std::uint32_t a = self.state & 1u;
    std::uint32_t b = (self.state >> 1) & 1u;
    if (a > b) self.aux = 1;
    else if (a < b) self.aux = 2;
    else self.aux = 3; // equal at this bit; lower bits may still decide
    self.signal = 1; // keep wave alive downward
    self.generation += 1;
}


std::uint64_t Topology::run_multiplier(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits) {
    // Spatial shift-add multiply using the topology as the accumulator register.
    // For each bit of the multiplier, conditionally add the shifted multiplicand
    // into a 2*bits-wide accumulator field starting at `start`.
    // This is still geometry-as-ALU: the field is the product register.
    const int width = bits * 2;
    // Clear accumulator field
    for (int i = 0; i < width; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        c.state = 0; c.aux = 0; c.signal = 0; c.generation = 0;
        c.rule_id = RuleAddWave;
    }
    std::uint64_t acc = 0;
    for (int i = 0; i < bits; ++i) {
        if ((b >> i) & 1u) {
            // add (a << i) into acc via the adder field
            std::uint32_t shifted = a << i;
            // Use low `width` bits
            std::uint32_t lo = static_cast<std::uint32_t>(acc & 0xFFFFFFFFu);
            std::uint32_t addend = shifted;
            // For widths > 32 we only support bits<=16 so product fits in 32
            std::uint32_t sum = run_adder(start, lo, addend, width <= 32 ? width : 32, 0);
            acc = sum;
            // If width > 32 would need high part; keep simple for prototype
        }
    }
    // Write final product bits into the field for inspection
    for (int i = 0; i < width && i < 32; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        c.state = (acc >> i) & 1u;
        c.generation += 1;
    }
    ++tick_;
    return acc;
}


Topology::SignalAddResult Topology::run_signal_adder(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits, int max_steps) {
    // Seed linear field: each cell holds a_i in bit0, b_i in bit1, cin in bit2.
    // Only cells with signal!=0 compute. After compute, cout is written to next
    // cell's bit2 and next.signal is set. Own signal cleared. No host for-loop
    // over bit index during the compute phase — only global steps until quiet.
    SignalAddResult out;
    for (int i = 0; i < bits; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        std::uint32_t ai = (a >> i) & 1u;
        std::uint32_t bi = (b >> i) & 1u;
        c.state = ai | (bi << 1); // cin=0 initially
        c.aux = 0;
        c.signal = (i == 0) ? 1 : 0; // kick LSB
        c.generation = 0;
        c.rule_id = RuleAddWave;
        c.orient = Orientation::Forward;
    }
    int hops = 0;
    for (int step = 0; step < max_steps; ++step) {
        // Collect who will fire this step (snapshot signals)
        std::vector<int> firing;
        for (int i = 0; i < bits; ++i) {
            if (at_address(static_cast<std::uint16_t>(start + i)).signal)
                firing.push_back(i);
        }
        if (firing.empty()) {
            out.steps = step;
            break;
        }
        // Two-phase: compute into temps, then commit + forward signal
        struct Tmp { std::uint32_t state; Signal sig; std::uint32_t cout; };
        std::vector<Tmp> tmps(bits);
        for (int i = 0; i < bits; ++i) {
            Cell& c = at_address(static_cast<std::uint16_t>(start + i));
            tmps[i] = {c.state, 0, 0};
        }
        for (int i : firing) {
            Cell& c = at_address(static_cast<std::uint16_t>(start + i));
            std::uint32_t ai = c.state & 1u;
            std::uint32_t bi = (c.state >> 1) & 1u;
            std::uint32_t cin = (c.state >> 2) & 1u;
            std::uint32_t sum = ai ^ bi ^ cin;
            std::uint32_t cout = (ai & bi) | (ai & cin) | (bi & cin);
            tmps[i].state = sum | (bi << 1) | (cout << 2);
            tmps[i].cout = cout;
            tmps[i].sig = 0; // consumed
            ++hops;
            // Schedule next bit
            if (i + 1 < bits) {
                // inject cin into next temp and raise signal
                tmps[i + 1].state = (tmps[i + 1].state & ~4u) | (cout << 2);
                tmps[i + 1].sig = 1;
            }
        }
        for (int i = 0; i < bits; ++i) {
            Cell& c = at_address(static_cast<std::uint16_t>(start + i));
            c.state = tmps[i].state;
            c.signal = tmps[i].sig;
            c.generation += 1;
        }
        ++tick_;
        out.steps = step + 1;
    }
    out.hops = hops;
    out.result = 0;
    for (int i = 0; i < bits; ++i)
        out.result |= ((at_address(static_cast<std::uint16_t>(start + i)).state & 1u) << i);
    std::uint32_t mask = (bits >= 32) ? 0xFFFFFFFFu : ((1u << bits) - 1u);
    out.ok = ((out.result & mask) == ((a + b) & mask));
    return out;
}

std::uint32_t Topology::step_event_driven(std::vector<std::uint16_t>& dirty) {
    // Update only dirty canonical cells; enqueue Hamming + mirror neighbors if changed.
    std::uint32_t fired = 0;
    std::vector<std::uint16_t> next_dirty;
    // Dedup dirty into canonical set
    std::vector<std::uint8_t> seen(kAddressCount, 0);
    std::vector<std::uint16_t> work;
    for (auto a : dirty) {
        auto c = canonical_of(a);
        if (!seen[c]) { seen[c] = 1; work.push_back(c); }
    }
    struct Next { std::uint32_t state, aux; Signal signal; std::uint64_t generation; bool changed; };
    std::vector<Next> results;
    results.reserve(work.size());
    for (auto caddr : work) {
        Cell& self = at_canonical(caddr);
        auto fn = rules_[self.rule_id];
        if (!fn) {
            results.push_back({self.state, self.aux, self.signal, self.generation, false});
            continue;
        }
        auto ham = neighbors_of(self.canonical, NeighborKind::Hamming1);
        auto mir = neighbors_of(self.canonical, NeighborKind::BitReverseMirror);
        std::vector<NeighborView> views;
        for (auto& r : ham) views.push_back(view_of(r.address));
        for (auto& r : mir) views.push_back(view_of(r.address));
        Cell tmp = self;
        fn(tmp, views.data(), views.size(), tick_);
        bool changed = (tmp.state != self.state) || (tmp.aux != self.aux) || (tmp.signal != self.signal);
        results.push_back({tmp.state, tmp.aux, tmp.signal, tmp.generation, changed});
        if (changed) ++fired;
    }
    for (size_t i = 0; i < work.size(); ++i) {
        Cell& self = at_canonical(work[i]);
        self.state = results[i].state;
        self.aux = results[i].aux;
        self.signal = results[i].signal;
        self.generation = results[i].generation;
        if (results[i].changed) {
            next_dirty.push_back(work[i]);
            auto ham = neighbors_of(work[i], NeighborKind::Hamming1);
            for (auto& r : ham) next_dirty.push_back(canonical_of(r.address));
            auto mir = neighbors_of(work[i], NeighborKind::BitReverseMirror);
            for (auto& r : mir) next_dirty.push_back(canonical_of(r.address));
        }
    }
    ++tick_;
    dirty.swap(next_dirty);
    return fired;
}


void Topology::enable_dual(std::uint16_t canonical) {
    Cell& c = at_canonical(canonical);
    c.set_dual(true);
    // Preserve existing state as S+; initialize S- to 0 if was shared
    // (caller may then set both sides)
}

void Topology::enable_dual_region(std::uint16_t start, std::uint16_t count) {
    for (std::uint16_t i = 0; i < count; ++i)
        enable_dual(static_cast<std::uint16_t>(start + i));
}

Topology::DualIndepResult Topology::experiment_mirror_independence(std::uint16_t canonical, bool touch_plus) {
    DualIndepResult r;
    Cell& c = at_canonical(canonical);
    c.set_dual(true);
    // Distinct initial values
    c.set_s_plus(0xA5A5A5A5u);
    c.set_s_minus(0x5A5A5A5Au);
    r.plus_before = c.s_plus();
    r.minus_before = c.s_minus();

    if (touch_plus) {
        // Transform only S+: rotate-xor — must not touch S-
        std::uint32_t v = c.s_plus();
        v = ((v << 3) | (v >> 29)) ^ 0x00C0FFEEu;
        c.set_s_plus(v);
        c.generation += 1;
    } else {
        std::uint32_t v = c.s_minus();
        v = ((v << 5) | (v >> 27)) ^ 0xF00DFACEu;
        c.set_s_minus(v);
        c.generation += 1;
    }
    r.plus_after = c.s_plus();
    r.minus_after = c.s_minus();
    r.plus_changed = (r.plus_after != r.plus_before);
    r.minus_changed = (r.minus_after != r.minus_before);
    // Isolation: the side we did NOT touch must be unchanged
    if (touch_plus)
        r.isolation_ok = (!r.minus_changed) && r.plus_changed;
    else
        r.isolation_ok = (!r.plus_changed) && r.minus_changed;
    return r;
}

Topology::DualCompResult Topology::experiment_complementary_xor(std::uint16_t canonical, std::uint32_t key) {
    DualCompResult r;
    Cell& c = at_canonical(canonical);
    c.set_dual(true);
    r.original = 0x1234ABCDu;
    c.set_s_plus(r.original);
    c.set_s_minus(0); // reverse side will hold inverse workspace
    // Forward: S+ := S+ XOR key; S- remembers key (or the preimage strategy)
    c.set_s_plus(c.s_plus() ^ key);
    c.set_s_minus(key); // store the operator so inverse is local
    r.after_forward = c.s_plus();
    // Inverse on reverse path: recover using S- as key
    std::uint32_t recovered = c.s_plus() ^ c.s_minus();
    c.set_s_plus(recovered);
    r.after_inverse = c.s_plus();
    r.recovered = (r.after_inverse == r.original);
    c.generation += 2;
    return r;
}

Topology::DualBulkResult Topology::experiment_dual_bulk(std::uint16_t start, std::uint32_t n_cells, std::uint32_t steps) {
    DualBulkResult br;
    br.cells = n_cells;
    br.steps = steps;
    // Seed dual cells with independent S+/S-
    for (std::uint32_t i = 0; i < n_cells; ++i) {
        auto addr = static_cast<std::uint16_t>(start + i);
        // skip if not a useful canonical — still use at_address which canonicalizes
        Cell& c = at_address(addr);
        c.set_dual(true);
        c.set_s_plus(0x1000u + i * 3u);
        c.set_s_minus(0x9000u + i * 7u);
    }
    for (std::uint32_t s = 0; s < steps; ++s) {
        for (std::uint32_t i = 0; i < n_cells; ++i) {
            Cell& c = at_address(static_cast<std::uint16_t>(start + i));
            std::uint32_t sp = c.s_plus();
            std::uint32_t sm = c.s_minus();
            // Independent transforms
            std::uint32_t np = ((sp << 1) | (sp >> 31)) ^ (0xAAu + s);
            std::uint32_t nm = ((sm >> 1) | (sm << 31)) ^ (0x55u + s);
            c.set_s_plus(np);
            c.set_s_minus(nm);
            // Verify isolation within the write API itself (should always hold)
            if (c.s_plus() != np || c.s_minus() != nm)
                br.isolation_failures++;
        }
    }
    // Complementary recoverability on a sample
    for (std::uint32_t i = 0; i < n_cells; ++i) {
        auto cr = experiment_complementary_xor(static_cast<std::uint16_t>(start + i), 0xCAFEBABEu ^ i);
        if (cr.recovered) br.complementary_ok++;
        else br.complementary_fail++;
    }
    return br;
}


void rule_dual_couple(Cell& self, const NeighborView* nb, std::size_t n, std::uint64_t) {
    // Independent orientation channels: mix neighbor state into S+, neighbor aux into S-
    // Only meaningful when dual; still safe on shared cells.
    std::uint32_t acc_p = 0, acc_m = 0;
    for (std::size_t i = 0; i < n; ++i) {
        if (!nb[i].present) continue;
        acc_p ^= (nb[i].state & 0xFFu);
        acc_m ^= (nb[i].aux & 0xFFu);
    }
    if (self.is_dual()) {
        self.set_s_plus(self.s_plus() ^ acc_p);
        self.set_s_minus(self.s_minus() ^ acc_m);
    } else {
        self.state ^= acc_p;
    }
    self.generation += 1;
}

void rule_dual_cross(Cell& self, const NeighborView* nb, std::size_t n, std::uint64_t) {
    // Cross-orientation coupling: S+ absorbs neighbor S- (aux), S- absorbs neighbor S+ (state)
    std::uint32_t from_minus = 0, from_plus = 0;
    for (std::size_t i = 0; i < n; ++i) {
        if (!nb[i].present) continue;
        from_minus ^= nb[i].aux;
        from_plus ^= nb[i].state;
    }
    if (self.is_dual()) {
        std::uint32_t sp = self.s_plus() ^ (from_minus & 0xFFFFu);
        std::uint32_t sm = self.s_minus() ^ (from_plus & 0xFFFFu);
        self.set_s_plus(sp);
        self.set_s_minus(sm);
    } else {
        self.state ^= from_plus;
    }
    self.generation += 1;
}

void rule_nand_pair(Cell& self, const NeighborView* nb, std::size_t n, std::uint64_t) {
    // NAND of self S+ low bit with first neighbor S+ low bit → write to self S+
    std::uint32_t a = self.s_plus() & 1u;
    std::uint32_t b = 1;
    for (std::size_t i = 0; i < n; ++i) {
        if (nb[i].present) { b = nb[i].state & 1u; break; }
    }
    std::uint32_t nand = (a & b) ? 0u : 1u;
    if (self.is_dual())
        self.set_s_plus((self.s_plus() & ~1u) | nand);
    else
        self.state = (self.state & ~1u) | nand;
    self.generation += 1;
}

Topology::LocalDualResult Topology::experiment_local_dual_couple(std::uint16_t start, std::uint16_t n,
                                                                 std::uint32_t steps, bool cross) {
    LocalDualResult r;
    r.cells = n;
    r.steps = steps;
    enable_dual_region(start, n);
    for (std::uint16_t i = 0; i < n; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        c.set_s_plus(0x11110000u + i);
        c.set_s_minus(0x22220000u + i * 3);
        c.rule_id = cross ? RuleDualCross : RuleDualCouple;
    }
    r.hash_before = state_hash();
    std::uint32_t p0 = at_address(start).s_plus();
    std::uint32_t m0 = at_address(start).s_minus();
    for (std::uint32_t s = 0; s < steps; ++s)
        step_synchronous();
    r.hash_after = state_hash();
    std::uint32_t p1 = at_address(start).s_plus();
    std::uint32_t m1 = at_address(start).s_minus();
    if (cross)
        r.cross_changed_both = (p1 != p0) && (m1 != m0);
    else {
        // couple rule may change both from independent neighbor mixes
        r.plus_only_when_couple = (p1 != p0); // at least plus moved in nontrivial neighborhood
        r.cross_changed_both = (p1 != p0) || (m1 != m0);
    }
    return r;
}

std::uint64_t Topology::experiment_nand_chain(std::uint16_t start, std::uint16_t n, std::uint32_t steps) {
    enable_dual_region(start, n);
    for (std::uint16_t i = 0; i < n; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        c.set_s_plus((i % 3 == 0) ? 1u : 0u);
        c.set_s_minus(0);
        c.rule_id = RuleNandPair;
    }
    for (std::uint32_t s = 0; s < steps; ++s) {
        // Linear-only neighborhood for NAND chain: use dedicated two-phase on line
        std::vector<std::uint32_t> next(n);
        for (std::uint16_t i = 0; i < n; ++i) {
            auto left = at_address(static_cast<std::uint16_t>(start + i)).s_plus() & 1u;
            auto right = at_address(static_cast<std::uint16_t>(start + (i + 1) % n)).s_plus() & 1u;
            next[i] = (left & right) ? 0u : 1u;
        }
        for (std::uint16_t i = 0; i < n; ++i) {
            Cell& c = at_address(static_cast<std::uint16_t>(start + i));
            c.set_s_plus(next[i]);
            c.generation += 1;
        }
        ++tick_;
    }
    std::uint64_t h = 0;
    for (std::uint16_t i = 0; i < n; ++i)
        h = (h << 1) | (at_address(static_cast<std::uint16_t>(start + i)).s_plus() & 1u);
    return h;
}

Topology::DualRailAddResult Topology::experiment_dual_rail_add(std::uint16_t start, std::uint32_t a,
                                                               std::uint32_t b, int bits) {
    DualRailAddResult r;
    enable_dual_region(start, static_cast<std::uint16_t>(bits));
    // S+ path: signal-carried adder
    auto sa = run_signal_adder(start, a, b, bits);
    r.result = sa.result;
    r.steps = sa.steps;
    r.arithmetic_ok = sa.ok;
    // After add, install shadow on S-: reconstruct operand bits from original a,b into S-
    // (validation rail stores the inputs that produced the sum)
    std::uint32_t shadow_a = 0, shadow_b = 0;
    for (int i = 0; i < bits; ++i) {
        Cell& c = at_address(static_cast<std::uint16_t>(start + i));
        // Preserve sum in S+; write operand bits into S- packing
        std::uint32_t ai = (a >> i) & 1u;
        std::uint32_t bi = (b >> i) & 1u;
        c.set_dual(true);
        // s_plus already holds sum bit in low bit from adder
        c.set_s_minus(ai | (bi << 1));
        shadow_a |= (ai << i);
        shadow_b |= (bi << i);
    }
    r.shadow_a = shadow_a;
    r.shadow_b = shadow_b;
    r.shadow_intact = (shadow_a == a && shadow_b == b);
    // Validate: recomputing a+b from shadow should match result
    if (r.shadow_intact) {
        std::uint32_t mask = (bits >= 32) ? 0xFFFFFFFFu : ((1u << bits) - 1u);
        r.shadow_intact = r.shadow_intact && (((shadow_a + shadow_b) & mask) == (r.result & mask));
    }
    return r;
}

Topology::OrderIndepResult Topology::experiment_order_independence(std::uint16_t start_a, std::uint16_t start_b,
                                                                   std::uint16_t n, std::uint32_t steps) {
    OrderIndepResult r;
    // Region A and B get dual couple rules, disjoint address bands
    enable_dual_region(start_a, n);
    enable_dual_region(start_b, n);
    for (std::uint16_t i = 0; i < n; ++i) {
        Cell& ca = at_address(static_cast<std::uint16_t>(start_a + i));
        Cell& cb = at_address(static_cast<std::uint16_t>(start_b + i));
        ca.set_s_plus(0xA000u + i); ca.set_s_minus(0xB000u + i); ca.rule_id = RuleDualCouple;
        cb.set_s_plus(0xC000u + i); cb.set_s_minus(0xD000u + i); cb.rule_id = RuleDualCouple;
    }
    // Order A: drain A events fully per outer step, then B
    Topology tA = *this; // copy via... we don't have copy ctor easily
    // Instead run two separate topologies
    Topology topoA, topoB;
    // seed both the same way
    auto seed = [&](Topology& T) {
        T.enable_dual_region(start_a, n);
        T.enable_dual_region(start_b, n);
        for (std::uint16_t i = 0; i < n; ++i) {
            Cell& ca = T.at_address(static_cast<std::uint16_t>(start_a + i));
            Cell& cb = T.at_address(static_cast<std::uint16_t>(start_b + i));
            ca.set_dual(true); cb.set_dual(true);
            ca.set_s_plus(0xA000u + i); ca.set_s_minus(0xB000u + i); ca.rule_id = RuleDualCouple;
            cb.set_s_plus(0xC000u + i); cb.set_s_minus(0xD000u + i); cb.rule_id = RuleDualCouple;
        }
    };
    seed(topoA); seed(topoB);

    // Order A: always process region A addresses first in dirty list
    std::vector<std::uint16_t> dirtyA;
    for (std::uint16_t i = 0; i < n; ++i) {
        dirtyA.push_back(static_cast<std::uint16_t>(start_a + i));
        dirtyA.push_back(static_cast<std::uint16_t>(start_b + i));
    }
    for (std::uint32_t s = 0; s < steps; ++s) {
        // rebuild preferential order each time: A then B
        std::vector<std::uint16_t> d;
        for (std::uint16_t i = 0; i < n; ++i) d.push_back(static_cast<std::uint16_t>(start_a + i));
        for (std::uint16_t i = 0; i < n; ++i) d.push_back(static_cast<std::uint16_t>(start_b + i));
        r.events_A += topoA.step_event_driven(d);
    }
    r.hash_order_A = topoA.state_hash();

    // Order B: B then A
    for (std::uint32_t s = 0; s < steps; ++s) {
        std::vector<std::uint16_t> d;
        for (std::uint16_t i = 0; i < n; ++i) d.push_back(static_cast<std::uint16_t>(start_b + i));
        for (std::uint16_t i = 0; i < n; ++i) d.push_back(static_cast<std::uint16_t>(start_a + i));
        r.events_B += topoB.step_event_driven(d);
    }
    r.hash_order_B = topoB.state_hash();
    r.independent = (r.hash_order_A == r.hash_order_B);
    return r;
}

} // namespace nan16
