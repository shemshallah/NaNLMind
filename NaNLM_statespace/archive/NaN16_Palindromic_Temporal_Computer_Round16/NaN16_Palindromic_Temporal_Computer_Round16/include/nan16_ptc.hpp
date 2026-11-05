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
    RuleDualCouple = 11,   // S+ ^= f(neighbors.S+); S- ^= f(neighbors.S-) independently via local rule
    RuleDualCross = 12,    // S+ ^= neighbor.S-; S- ^= neighbor.S+  (cross-orientation couple)
    RuleNandPair = 13,     // linear pair-to-pair NAND on S+ bits
    RuleLocalXor = 14,     // S+ bit0 ^= neighbor S+ bit0 (pure local)
    RuleLocalAnd = 15,     // S+ bit0 &= neighbor S+ bit0
    RuleRippleCell = 16,   // pure local full-adder cell: host only steps, never injects carry
    RuleOpDispatch = 17,   // SINGLE fixed rule: interprets opcode in aux, executes ADD/SUB/XOR/AND/CMP
    RuleVmCycle = 18,      // One instruction cycle of the in-topology VM
    RuleCustom = 255
};

// Opcodes for RuleOpDispatch (stored in aux low byte at init; machine interprets)
enum OpCode : std::uint8_t {
    OpAdd = 0,
    OpSub = 1,
    OpXor = 2,
    OpAnd = 3,
    OpCmp = 4,   // result: 1 if a>b, 2 if a<b, 3 if equal — in cell0 aux bits 8-9
    OpNot = 5,
    OpCount = 6
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

    // Round 8: local-rule dual coupling & order independence
    // Apply RuleDualCouple / RuleDualCross via synchronous step on a dual region
    struct LocalDualResult {
        std::uint32_t cells = 0;
        std::uint32_t steps = 0;
        bool cross_changed_both = false;  // cross rule touched both sides
        bool plus_only_when_couple = false;
        std::uint64_t hash_before = 0, hash_after = 0;
    };
    LocalDualResult experiment_local_dual_couple(std::uint16_t start, std::uint16_t n, std::uint32_t steps, bool cross);

    // Pair-to-pair NAND chain on S+ along linear neighbors (logic circuit sketch)
    // cells[i].S+ = NAND(cells[i].S+, cells[i+1].S+) style evolution; returns final bitstring hash
    std::uint64_t experiment_nand_chain(std::uint16_t start, std::uint16_t n, std::uint32_t steps);

    // Dual-rail signal add: S+ carries arithmetic, S- holds shadow copy of operands for validation
    struct DualRailAddResult {
        std::uint32_t result = 0;
        std::uint32_t shadow_a = 0, shadow_b = 0;
        bool arithmetic_ok = false;
        bool shadow_intact = false;
        int steps = 0;
    };
    DualRailAddResult experiment_dual_rail_add(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits);

    // Order independence: two disjoint dual regions, permute event order, compare final hashes
    struct OrderIndepResult {
        std::uint64_t hash_order_A = 0;
        std::uint64_t hash_order_B = 0;
        bool independent = false;
        std::uint32_t events_A = 0, events_B = 0;
    };
    OrderIndepResult experiment_order_independence(std::uint16_t start_a, std::uint16_t start_b,
                                                   std::uint16_t n, std::uint32_t steps);

    // Round 9: host-blind local-rule machine
    // Host only: seed cells, call step_synchronous until quiet / max steps, read result.
    // No host-side sum/cout arithmetic and no host carry injection.
    struct PureAddResult {
        std::uint32_t result = 0;
        int steps = 0;
        bool ok = false;
        bool host_blind = true; // documented contract
    };
    PureAddResult experiment_pure_local_adder(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits, int max_steps = 64);

    // Local XOR/AND gate network: seed inputs, step rules, read outputs — host does not compute gate outputs
    struct GateNetResult {
        std::uint8_t xor_out = 0, and_out = 0;
        bool xor_ok = false, and_ok = false;
    };
    GateNetResult experiment_local_gates(std::uint16_t base, std::uint8_t x, std::uint8_t y);

    // Two independent pure local adders in one topology (regions only)
    struct TwoPureResult {
        std::uint32_t r0 = 0, r1 = 0;
        bool ok0 = false, ok1 = false;
        int steps = 0;
    };
    TwoPureResult experiment_two_pure_adders(std::uint16_t s0, std::uint32_t a0, std::uint32_t b0, int bits0,
                                             std::uint16_t s1, std::uint32_t a1, std::uint32_t b1, int bits1);

    // ---- Round 10 checkpoint suite ----
    // Reversible gates on dual-state triples (bits in S+/S- packs). Host applies gate rules only.
    struct RevGateResult {
        std::uint32_t trials = 0, passed = 0;
        bool not_ok = false, cnot_ok = false, toffoli_ok = false, fredkin_ok = false;
    };
    RevGateResult experiment_reversible_gates(std::uint32_t trials);

    // Dual-side: 64 pairs, S+ does pure local add field, S- does independent XOR walk; no contamination
    struct DualCoopResult {
        bool plus_arith_ok = false;
        bool minus_intact = false;
        bool recover_ok = false;
        std::uint32_t pairs = 0;
    };
    DualCoopResult experiment_dual_cooperation(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits);

    // Schedule matrix: pure adder under sync-line, reverse-order line, and scrambled activation
    struct ScheduleResult {
        std::uint32_t result_sync = 0, result_rev = 0, result_scramble = 0;
        bool all_match = false;
        bool expect_ok = false;
    };
    ScheduleResult experiment_schedule_matrix(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits);

    // Fault inject on dual-rail: flip S+ sum bit, detect via S- shadow, restore
    struct FaultResult {
        bool detected = false;
        bool recovered = false;
        std::uint32_t faults_tested = 0, recoveries = 0;
    };
    FaultResult experiment_fault_recovery(std::uint16_t start, std::uint32_t a, std::uint32_t b, int bits);

    // Fixed rule map: same RuleRippleCell everywhere; only initial state differs → different sums
    struct FixedRuleProgResult {
        std::uint32_t r_prog0 = 0, r_prog1 = 0;
        bool distinct = false;
        bool both_ok = false;
    };
    FixedRuleProgResult experiment_fixed_rule_programs(std::uint16_t s0, std::uint16_t s1);

    // Mirror Machine Challenge (subset): simultaneous pure add + local gates, reverse recover, schedule match
    struct ChallengeResult {
        bool arith_ok = false;
        bool gates_ok = false;
        bool reverse_ok = false;
        bool schedule_ok = false;
        bool fault_ok = false;
        bool all_ok = false;
    };
    ChallengeResult experiment_mirror_machine_challenge();

    // Round 11: Initial-State Programmability
    // ONE immutable rule (RuleOpDispatch) for all ops. Host only seeds opcode+operands and steps.
    struct ProgOpResult {
        std::uint32_t result = 0;
        int cmp_code = 0; // -1,0,+1 for OpCmp
        int steps = 0;
        bool ok = false;
        OpCode op = OpAdd;
    };
    ProgOpResult experiment_programmable_op(std::uint16_t start, OpCode op,
                                            std::uint32_t a, std::uint32_t b, int bits,
                                            int max_steps = 128);

    // Battery: all ops under same rule map, many inputs; schedule variants
    struct ProgBatteryResult {
        std::uint32_t cases = 0, passed = 0;
        bool add_ok = false, sub_ok = false, xor_ok = false, and_ok = false, cmp_ok = false;
        bool schedule_ok = false;
        bool multi_region_ok = false;
        bool dual_rail_ok = false;
    };
    ProgBatteryResult experiment_programmability_battery();

    // ---- Round 12: Program-in-State VM ----
    // Immutable RuleVmCycle interprets instructions stored in topology cells.
    // Registers, IP, flags, program, and HALT live entirely in machine state.
    enum VmOp : std::uint8_t {
        VmHalt = 0,
        VmLoadA = 1,   // A := imm
        VmLoadB = 2,   // B := imm
        VmAdd = 3,     // A := A + B
        VmSub = 4,     // A := A - B
        VmXor = 5,     // A := A ^ B
        VmAnd = 6,     // A := A & B
        VmCmp = 7,     // FLAGS from A ? B
        VmJmp = 8,     // IP := imm
        VmJz = 9,      // if Z: IP := imm
        VmJnz = 10,    // if !Z: IP := imm
        VmJg = 11,     // if GT: IP := imm
        VmJl = 12,     // if LT: IP := imm
        VmMovBA = 13,  // B := A
        VmMovAB = 14,  // A := B
        VmNotA = 15,   // A := ~A (8-bit)
        VmAddImm = 16, // A := A + imm
        VmNop = 17,
        VmOut = 18,    // OUT := A
        VmStoreProg = 19, // program[B] := A  (self-modifying)
        VmLoadProg = 20,  // A := program[B]
        VmIncA = 21,      // A := A+1
        VmDecA = 22,      // A := A-1 (saturate at 0 for 2CM style)
        VmIncB = 23,
        VmDecB = 24,      // B := B-1 saturate 0; set Z if result 0
        VmOpCount = 25
    };

    // Machine image offsets from base
    static constexpr std::uint16_t VmRegA = 0;
    static constexpr std::uint16_t VmRegB = 1;
    static constexpr std::uint16_t VmRegIP = 2;
    static constexpr std::uint16_t VmRegFLAGS = 3;
    static constexpr std::uint16_t VmRegHALT = 4;
    static constexpr std::uint16_t VmRegOUT = 5;
    static constexpr std::uint16_t VmRegCYC = 6;
    static constexpr std::uint16_t VmProgBase = 16;

    struct VmResult {
        std::uint32_t out = 0;
        std::uint32_t a = 0, b = 0;
        std::uint32_t cycles = 0;
        bool halted = false;
        bool ok = false; // matched expected if provided
    };

    // Load program words into topology; IP=0, regs cleared. Returns base.
    void vm_load(std::uint16_t base, const std::uint32_t* prog, std::uint16_t prog_len,
                 std::uint32_t a0 = 0, std::uint32_t b0 = 0);

    // One instruction cycle via RuleVmCycle (host does not decode)
    bool vm_step(std::uint16_t base); // returns true if still running (!halt)

    // Run until HALT or max cycles
    VmResult vm_run(std::uint16_t base, std::uint32_t max_cycles = 10000);

    // Full program suite: >=10 programs, branching, dual region, schedule sanity
    struct VmSuiteResult {
        std::uint32_t programs = 0, passed = 0;
        bool dual_region_ok = false;
        bool branch_ok = false;
        bool long_prog_ok = false;
    };
    VmSuiteResult experiment_vm_suite();

    // Round 13: universality path + hierarchy + self-mod + async dual
    struct TwoCMResult {
        std::uint32_t out = 0;
        std::uint32_t cycles = 0;
        bool halted = false;
        bool ok = false;
    };
    // Two-counter programs (counters in A,B; DecB sets Z for branch)
    TwoCMResult experiment_twocm_add(std::uint16_t base, std::uint32_t x, std::uint32_t y);
    TwoCMResult experiment_twocm_mul(std::uint16_t base, std::uint32_t x, std::uint32_t y);
    TwoCMResult experiment_twocm_copy(std::uint16_t base, std::uint32_t x);

    struct SelfModResult {
        std::uint32_t out = 0;
        bool patched = false;
        bool ok = false;
    };
    SelfModResult experiment_self_modifying(std::uint16_t base);

    struct HierarchyResult {
        std::uint32_t page0_out = 0, page1_out = 0;
        bool ok = false;
    };
    // Page0 computes XOR, writes portal; page1 reads portal and ADDs 1
    HierarchyResult experiment_hierarchy(std::uint16_t page0, std::uint16_t page1, std::uint16_t portal);

    struct AsyncDualResult {
        std::uint32_t out_a = 0, out_b = 0;
        bool order1_ok = false, order2_ok = false, match = false;
    };
    AsyncDualResult experiment_async_dual_vms(std::uint16_t base_a, std::uint16_t base_b);

    struct AdvantageResult {
        std::uint32_t vm_cycles = 0;
        std::uint32_t host_ref_ops = 0; // naive host loop ops for same 2CM mul
        bool same_answer = false;
    };
    AdvantageResult experiment_resource_compare(std::uint32_t x, std::uint32_t y);

    // ---- Round 14: Cognitive architecture ----
    // Concepts, relations, triples live in topology cells.
    // Dual rail: S+ = general inheritance, S- = exceptions / specific.
    enum Concept : std::uint16_t {
        C_NONE=0, C_BIRD=1, C_EAGLE=2, C_PENGUIN=3, C_WINGS=4, C_FLY=5, C_UNKNOWN=6, C_COUNT=7
    };
    enum Relation : std::uint8_t {
        R_NONE=0, R_ISA=1, R_HAS=2, R_CAN=3, R_CANNOT=4, R_COUNT=5
    };

    struct Triple {
        std::uint16_t s=0, o=0;
        std::uint8_t r=0;
        bool active=false;
    };

    static constexpr std::uint16_t CogKBBase = 0xD000;
    static constexpr std::uint16_t CogMaxTriples = 32;
    static constexpr std::uint16_t CogActBase = 0xD200; // activation cells per concept
    static constexpr std::uint16_t CogScratch = 0xD300;

    void cog_clear();
    const std::vector<Triple>& cog_kb_ref() const { return cog_kb_; }
    std::vector<Triple>& cog_kb_mut() { return cog_kb_; }
    void cog_assert(std::uint16_t s, std::uint8_t r, std::uint16_t o);
    int  cog_triple_count() const;

    // Query: can subject do object via relation? Uses inheritance + exception override.
    // dual=true: S+ general path, S- exception path, then resolve.
    struct CogAnswer {
        bool yes = false;
        bool found = false;
        bool used_inheritance = false;
        bool used_exception = false;
        bool contradiction = false;
        bool resolved = false;
        int steps = 0;
    };
    CogAnswer cog_query(std::uint16_t s, std::uint8_t r, std::uint16_t o, bool dual = true);

    // Associative retrieval: list objects related to s under r (including inherited)
    struct CogAssoc {
        std::uint16_t objects[16]{};
        int n = 0;
    };
    CogAssoc cog_associate(std::uint16_t s, std::uint8_t r);

    // Counterfactual: checkpoint, assert temporary fact, query, restore
    struct CogCounterfactual {
        CogAnswer before{};
        CogAnswer hypothetical{};
        CogAnswer after{};
        bool restored = false;
    };
    CogCounterfactual cog_counterfactual(std::uint16_t s, std::uint8_t r, std::uint16_t o,
                                         std::uint16_t hyp_s, std::uint8_t hyp_r, std::uint16_t hyp_o,
                                         std::uint16_t q_s, std::uint8_t q_r, std::uint16_t q_o);

    // Continual learning: feedback corrects a wrong answer by asserting exception/fact
    struct CogLearn {
        CogAnswer before{};
        CogAnswer after{};
        bool improved = false;
    };
    CogLearn cog_learn_feedback(std::uint16_t s, std::uint8_t r, std::uint16_t o, bool truth);

    // Dual inference: run general-only vs exception-aware, report disagreement resolution
    struct CogDualInf {
        CogAnswer general_only{};
        CogAnswer with_exceptions{};
        bool disagreed = false;
        bool resolved_correctly = false;
    };
    CogDualInf cog_dual_inference(std::uint16_t s, std::uint8_t r, std::uint16_t o);

    // Distributed: two KB pages with portal fact sharing
    struct CogDistributed {
        CogAnswer page0{};
        CogAnswer page1{};
        bool ok = false;
    };
    CogDistributed cog_distributed_query();

    // Full bird/penguin suite
    struct CogSuiteResult {
        int tests = 0, passed = 0;
        bool penguin_fly_ok = false;
        bool eagle_fly_ok = false;
        bool unknown_penguin_ok = false;
        bool dual_ok = false;
        bool counterfactual_ok = false;
        bool learn_ok = false;
        bool distributed_ok = false;
        bool control_single_ok = false;
    };
    CogSuiteResult experiment_cognitive_suite();

    // ---- Round 15: 256 Cognitive Heads + Collective State Space ----
    static constexpr int HeadCount = 256;

    struct HeadMsg {
        std::uint8_t type = 0; // 0=SIGNAL 1=QUERY 2=PROPOSE 3=CHALLENGE 4=ACTIVATE
        std::uint8_t from = 0;
        std::uint16_t payload = 0;
    };

    struct CognitiveHead {
        std::uint8_t id = 0;
        std::uint16_t fixed_addr = 0;   // fixed-point address anchor
        float activation = 0.f;
        float confidence = 0.5f;
        std::uint32_t strategy = 0;
        std::uint32_t version = 0;
        std::uint32_t focus = 0;
        std::uint32_t tasks_seen = 0;
        std::uint32_t successes = 0;
        std::uint32_t special_score[8]{}; // soft specialization bins
        std::uint16_t assoc_key[8]{};
        std::uint16_t assoc_val[8]{};
        int assoc_n = 0;
        HeadMsg inbox[8]{};
        int inbox_n = 0;
        std::uint32_t history_hash = 0;
    };

    void heads_init();                 // bind 256 heads to fixed points
    CognitiveHead& head(int i);
    const CognitiveHead& head(int i) const;
    int head_count() const { return HeadCount; }

    // Feed a task class 0..7 to all heads; they update activation/special_score
    void heads_present_task(int task_class, std::uint16_t input_tag);

    // Head-to-head SIGNAL: from → to with payload
    bool heads_send(std::uint8_t from, std::uint8_t to, std::uint8_t type, std::uint16_t payload);

    // Process one round of pending messages (local)
    int heads_process_inbox();

    // Head-level associative memory
    void head_remember(std::uint8_t id, std::uint16_t key, std::uint16_t val);
    bool head_recall(std::uint8_t id, std::uint16_t key, std::uint16_t& val_out) const;

    // Specialization metric: entropy of special_score distribution (lower = more specialized)
    struct HeadSpecResult {
        double mean_entropy = 0;
        int dominant_heads[8]{}; // head id with max score per class
        bool emergent = false;   // different heads dominate different classes
    };
    HeadSpecResult heads_measure_specialization() const;

    // Full R15 suite
    struct HeadSuiteResult {
        int tests = 0, passed = 0;
        bool init_ok = false;
        bool specialization_ok = false;
        bool communication_ok = false;
        bool memory_ok = false;
        bool dual_with_heads_ok = false;
        bool css_doc_present = false;
    };
    HeadSuiteResult experiment_heads_suite();

    // ---- Round 16: Unity under differentiation ----
    // Collective facts with attribution; heads differentiate without fracturing state.
    struct AttributedFact {
        std::uint16_t subject = 0, object = 0;
        std::uint8_t relation = 0;
        std::uint8_t origin_head = 0;
        std::uint32_t event_id = 0;
        std::uint32_t parent_event = 0;
        bool active = true;
        bool contested = false; // true if opposing fact exists
    };

    void collective_clear();
    // Head proposes a fact into collective state (attributed)
    std::uint32_t collective_propose(std::uint8_t head_id, std::uint16_t s, std::uint8_t r, std::uint16_t o);
    // Query collective (not head-local): returns yes if positive fact active and not overridden
    struct CollectiveQuery {
        bool yes = false;
        bool found = false;
        bool contested = false;
        std::uint8_t origin_head = 0;
        std::uint32_t event_id = 0;
        int supporting = 0, opposing = 0;
    };
    CollectiveQuery collective_query(std::uint16_t s, std::uint8_t r, std::uint16_t o) const;
    int collective_fact_count() const;

    // Shared-fact propagation: head A learns, head B queries collective
    bool experiment_shared_fact_propagation();

    // Two heads assert contradictions; third sees contested provenance
    struct ConflictResult {
        bool both_preserved = false;
        bool contested = false;
        bool third_sees_both = false;
        bool shared_state_intact = false;
    };
    ConflictResult experiment_conflicting_conclusions();

    // Specialization stability across distribution shift
    struct StabResult {
        double entropy_before = 0, entropy_after = 0;
        int same_dominants = 0;
        bool stable = false;
    };
    StabResult experiment_specialization_stability();

    // Transfer: head learns new class without erasing old specialty scores
    struct TransferResult {
        std::uint32_t old_score_before = 0, old_score_after = 0;
        std::uint32_t new_score_after = 0;
        bool retained = false;
        bool acquired = false;
    };
    TransferResult experiment_specialization_transfer();

    // Reset one head; collective facts and other heads survive
    struct FailResult {
        bool head_reset = false;
        bool others_intact = false;
        bool collective_intact = false;
        bool identity_unchanged = false; // same fixed_addr after re-init of that head only
    };
    FailResult experiment_head_failure(std::uint8_t victim);

    // Logical identity independent of "physical" page base offset
    bool experiment_physical_relocation();

    // Schedule consistency: two interleavings of proposes → same collective state hash
    bool experiment_schedule_consistency();

    struct UnitySuiteResult {
        int tests = 0, passed = 0;
        bool shared = false, conflict = false, stability = false, transfer = false;
        bool failure = false, relocation = false, schedule = false;
    };
    UnitySuiteResult experiment_unity_suite();

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
    CognitiveHead heads_[256];
    std::vector<AttributedFact> collective_facts_;
    std::uint32_t next_event_id_ = 1;
    bool heads_ready_ = false;
    std::vector<Triple> cog_kb_;
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
void rule_dual_couple(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_dual_cross(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_nand_pair(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_local_xor(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_local_and(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_ripple_cell(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_op_dispatch(Cell&, const NeighborView*, std::size_t, std::uint64_t);
void rule_vm_cycle(Cell&, const NeighborView*, std::size_t, std::uint64_t);

} // namespace nan16
