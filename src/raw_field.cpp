#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <cstring>
#include <numeric>
#include <fstream>
#include <iterator>
#include <vector>

namespace nanlm {
namespace {
constexpr std::uint32_t kCommandBase = 0x4000;
constexpr std::uint32_t kProposalBase = 0x4001;
constexpr std::uint32_t kResultBase = 0x4010;
constexpr std::uint32_t kFieldMasks = 0x5000;
constexpr std::uint32_t kCoherencePhases = 0x6000;
constexpr std::uint32_t kHotCredits = 0x7000;
constexpr std::uint32_t kHotMapping = 0x8000;
constexpr std::uint32_t kMicroX0 = 0x7000;
constexpr std::uint32_t kMicroX1 = 0x7100;
constexpr std::uint32_t kMicroOut = 0x7200;
constexpr std::uint32_t kMaxSteps = 200'000'000;

void bump_triad_credit(std::int16_t& value, int delta) {
    const int next = static_cast<int>(value) + delta;
    value = static_cast<std::int16_t>(std::max(-32768, std::min(32767, next)));
}
} // namespace

RawFieldVM::RawFieldVM(const std::string& driver_image) {
    std::ifstream in(driver_image, std::ios::binary);
    if (!in) {
        fail("cannot open raw field driver: " + driver_image);
        return;
    }
    std::string image((std::istreambuf_iterator<char>(in)),
                      std::istreambuf_iterator<char>());
    vm_ = nan_create();
    if (!vm_) {
        fail("cannot allocate NaN0S VM");
        return;
    }
    if (nan_load_text(vm_, image.data(), image.size()) != 0) {
        fail("cannot load raw field driver line " +
             std::to_string(nan_load_error(vm_)));
        nan_destroy(vm_);
        vm_ = nullptr;
    }
}

RawFieldVM::~RawFieldVM() {
    if (vm_) nan_destroy(vm_);
}

bool RawFieldVM::fail(const std::string& message) {
    error_ = message;
    return false;
}

bool RawFieldVM::write_word(std::uint32_t index, std::uint32_t payload) {
    const std::uint8_t bytes[4] = {
        static_cast<std::uint8_t>(payload & 0xFFu),
        static_cast<std::uint8_t>((payload >> 8) & 0xFFu),
        static_cast<std::uint8_t>((payload >> 16) & 0xFFu),
        static_cast<std::uint8_t>((payload >> 24) & 0xFFu),
    };
    return nan_write_bytes(vm_, index * 4u, bytes, sizeof(bytes)) == 0;
}

std::uint32_t RawFieldVM::read_word(std::uint32_t index) const {
    return static_cast<std::uint32_t>(nan_word(vm_, index) >> 16u);
}

bool RawFieldVM::run_command() {
    if (!vm_) return fail("raw field VM is not loaded");
    nan_set_pc(vm_, 0);
    nan_set_reg(vm_, 13, 1);
    const int rc = nan_run(vm_, kMaxSteps);
    if (rc != NAN_HALTED) {
        return fail("raw field driver did not halt: " +
                    std::string(nan_strerror(rc)));
    }
    const char* trap = nan_trap_text(vm_);
    if (trap && *trap) return fail("raw field driver trap: " + std::string(trap));
    return true;
}

bool RawFieldVM::proposal(std::uint16_t current_mask, std::uint16_t patch,
                          const std::array<std::uint16_t, 3>& members,
                          std::uint32_t a, std::uint32_t b, bool target,
                          RawProposalResult& out) {
    if (!write_word(kCommandBase, 1) ||
        !write_word(kProposalBase + 0, current_mask) ||
        !write_word(kProposalBase + 1, patch) ||
        !write_word(kProposalBase + 2, members[0]) ||
        !write_word(kProposalBase + 3, members[1]) ||
        !write_word(kProposalBase + 4, members[2]) ||
        !write_word(kProposalBase + 5, a) ||
        !write_word(kProposalBase + 6, b) ||
        !write_word(kProposalBase + 7, target ? 1u : 0u)) {
        return fail("cannot write raw proposal command");
    }
    if (!run_command()) return false;
    out.votes = static_cast<std::uint8_t>(read_word(kResultBase + 0) & 7u);
    out.accepted = (read_word(kResultBase + 1) & 1u) != 0;
    out.candidate_mask = static_cast<std::uint16_t>(read_word(kResultBase + 2));
    out.candidate_rule = static_cast<std::uint8_t>(read_word(kResultBase + 3) & 15u);
    return true;
}

bool RawFieldVM::propose(Universe& universe, HeadArray& heads,
                         std::uint8_t proposer, std::uint16_t patch,
                         std::uint32_t a, std::uint32_t b, bool target,
                         RawProposalResult& out) {
    if (proposer >= kTriadMemberCount) return fail("proposer is not a triad head");
    HeadView view = heads.at(proposer);
    const std::uint8_t triad = universe.triad_index(proposer);
    if (triad >= kTriadCount) return fail("proposer has no triad");
    const std::size_t base = static_cast<std::size_t>(triad) * kTriadSize;
    const auto& table = universe.triad_members();
    std::array<std::uint16_t, 3> members = {
        heads.at(table[base]).boolean_mask(),
        heads.at(table[base + 1]).boolean_mask(),
        heads.at(table[base + 2]).boolean_mask(),
    };
    if (!proposal(view.boolean_mask(), patch, members, a, b, target, out))
        return false;
    if (out.accepted) {
        if (!view.self_modify_boolean(patch))
            return fail("raw proposal accepted but head is not writable");
    }
    bump_triad_credit(universe.head_credit()[proposer], out.accepted ? 1 : -1);
    bump_triad_credit(universe.triad_credit()[triad], out.accepted ? 1 : -1);
    if (!field_vote(universe)) return false;
    if (!coherence(universe)) return false;
    return true;
}

bool RawFieldVM::auto_remap(Universe& universe, HeadArray& heads,
                             std::uint32_t seed, std::uint32_t a,
                             std::uint32_t b, bool target,
                             AutoRemapResult& out) {
    std::array<std::uint8_t, kTriadCount> order{};
    std::iota(order.begin(), order.end(), 0);
    std::stable_sort(order.begin(), order.end(), [&](std::uint8_t x,
                                                     std::uint8_t y) {
        return universe.triad_credit()[x] < universe.triad_credit()[y];
    });
    out.triad_a = order[0];
    out.triad_b = order[1];
    out.slot_a = static_cast<std::uint8_t>((seed >> 8) % kTriadSize);
    out.slot_b = static_cast<std::uint8_t>((seed >> 16) % kTriadSize);
    out.attempted = true;
    return remap_chart(universe, heads, out.triad_a, out.slot_a,
                       out.triad_b, out.slot_b, a, b, target,
                       out.improved, out.before, out.after);
}

bool RawFieldVM::field_vote(const std::array<std::uint8_t, kTriadCount>& masks,
                            std::uint16_t& accepted_count,
                            bool& field_accepted) {
    for (std::size_t i = 0; i < masks.size(); ++i) {
        if (!write_word(kFieldMasks + static_cast<std::uint32_t>(i), masks[i])) {
            return fail("cannot write field vote masks");
        }
    }
    if (!write_word(kCommandBase, 2)) return fail("cannot write field vote command");
    if (!run_command()) return false;
    accepted_count = static_cast<std::uint16_t>(read_word(kResultBase + 0));
    field_accepted = (read_word(kResultBase + 1) & 1u) != 0;
    return true;
}

bool RawFieldVM::coherence(
    const std::array<std::uint16_t, kTriadMemberCount>& phases,
    std::int32_t& q16) {
    for (std::size_t i = 0; i < phases.size(); ++i) {
        if (!write_word(kCoherencePhases + static_cast<std::uint32_t>(i),
                        phases[i])) {
            return fail("cannot write coherence phases");
        }
    }
    if (!write_word(kCommandBase, 3)) return fail("cannot write coherence command");
    if (!run_command()) return false;
    q16 = static_cast<std::int32_t>(read_word(kResultBase + 0));
    return true;
}

bool RawFieldVM::cft(std::int32_t e_ab, std::int32_t e_bc,
                     std::int32_t e_ca, std::int32_t error,
                     std::int32_t rate, std::array<std::int32_t, 4>& out) {
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(e_ab)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(e_bc)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(e_ca)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(error)) ||
        !write_word(kProposalBase + 4, static_cast<std::uint32_t>(rate)) ||
        !write_word(kCommandBase, 6)) {
        return fail("cannot write CFT command");
    }
    if (!run_command()) return false;
    for (std::size_t i = 0; i < out.size(); ++i) {
        out[i] = static_cast<std::int32_t>(read_word(kResultBase + i));
    }
    return true;
}

bool RawFieldVM::trail(std::int32_t reward, std::int32_t v_minus_next,
                       std::int32_t v_plus, std::int32_t v_plus_prev,
                       std::int32_t v_minus, std::int32_t e_plus,
                       std::int32_t e_minus, std::int32_t grad_plus,
                       std::int32_t grad_minus, std::int32_t gamma,
                       std::int32_t lambda, std::array<std::int32_t, 3>& out) {
    const std::array<std::int32_t, 11> args = {
        reward, v_minus_next, v_plus, v_plus_prev, v_minus, e_plus,
        e_minus, grad_plus, grad_minus, gamma, lambda};
    for (std::size_t i = 0; i < args.size(); ++i) {
        if (!write_word(kProposalBase + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(args[i]))) {
            return fail("cannot write TRAIL command");
        }
    }
    if (!write_word(kCommandBase, 7)) return fail("cannot write TRAIL command");
    if (!run_command()) return false;
    for (std::size_t i = 0; i < out.size(); ++i) {
        out[i] = static_cast<std::int32_t>(read_word(kResultBase + i));
    }
    return true;
}


bool RawFieldVM::hot_triheads(
    const std::array<std::int32_t, kTriadMemberCount>& credits,
    std::int32_t threshold, HotTriheadResult& out) {
    for (std::size_t i = 0; i < credits.size(); ++i) {
        if (!write_word(kHotCredits + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i]))) {
            return fail("cannot write hot-head credits");
        }
    }
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(threshold)) ||
        !write_word(kCommandBase, 8)) {
        return fail("cannot write hot-trihead command");
    }
    if (!run_command()) return false;

    out.hot_heads = static_cast<std::uint16_t>(read_word(kResultBase + 0));
    out.hot_triads = static_cast<std::uint16_t>(read_word(kResultBase + 1));
    out.field_hot = (read_word(kResultBase + 2) & 1u) != 0;
    const std::uint32_t mapped = read_word(kResultBase + 3);
    if (out.hot_heads > kTriadMemberCount || mapped != kTriadMemberCount) {
        return fail("raw hot-trihead result has an invalid count");
    }

    std::array<bool, kTriadMemberCount> seen{};
    for (std::size_t i = 0; i < out.members.size(); ++i) {
        const std::uint32_t value = read_word(
            kHotMapping + static_cast<std::uint32_t>(i));
        if (value >= kTriadMemberCount) {
            return fail("raw hot-trihead mapping contains an invalid head");
        }
        if (seen[value]) return fail("raw hot-trihead mapping repeats a head");
        seen[value] = true;
        out.members[i] = static_cast<std::uint8_t>(value);
    }
    out.mapped = false;
    return true;
}

bool RawFieldVM::hot_triheads(
    Universe& universe,
    const std::array<std::int32_t, kTriadMemberCount>& credits,
    std::int32_t threshold, HotTriheadResult& out) {
    if (!hot_triheads(credits, threshold, out)) return false;

    for (std::size_t i = 0; i < out.members.size(); ++i) {
        universe.triad_members()[i] = out.members[i];
        const std::size_t t = i / kTriadSize;
        const std::size_t slot = i % kTriadSize;
        universe.triad_of()[out.members[i]] = static_cast<std::uint8_t>(t);
        universe.triad_slot()[out.members[i]] = static_cast<std::uint8_t>(slot);
    }
    universe.triad_votes().fill(0);
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        bump_triad_credit(universe.triad_credit()[t],
                          t < out.hot_triads ? 1 : -1);
    }
    out.mapped = true;
    return true;
}


bool RawFieldVM::micro_feature(
    const std::array<float, kRawFeatureDim>& x0,
    const std::array<float, kRawFeatureDim>& x1,
    std::array<float, kRawFeatureDim>& out) {
    for (std::size_t i = 0; i < kRawFeatureDim; ++i) {
        std::uint32_t a = 0, b = 0;
        std::memcpy(&a, &x0[i], sizeof(a));
        std::memcpy(&b, &x1[i], sizeof(b));
        if (!write_word(kMicroX0 + static_cast<std::uint32_t>(i), a) ||
            !write_word(kMicroX1 + static_cast<std::uint32_t>(i), b)) {
            return fail("cannot write raw micro-feature input");
        }
    }
    if (!write_word(kCommandBase, 9)) return fail("cannot write micro-feature command");
    if (!run_command()) return false;
    if (read_word(kResultBase) != kRawFeatureDim) {
        return fail("raw micro-feature returned the wrong count");
    }
    for (std::size_t i = 0; i < kRawFeatureDim; ++i) {
        const std::uint32_t bits = read_word(kMicroOut + static_cast<std::uint32_t>(i));
        std::memcpy(&out[i], &bits, sizeof(bits));
    }
    return true;
}


bool RawFieldVM::write_trunk_weights(const TrunkWeights& weights) {
    auto write_float = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    const struct {
        const float* data;
        std::uint32_t base;
        std::size_t size;
    } blocks[] = {
        {weights.wq.data(), 0x9000, weights.wq.size()},
        {weights.wk.data(), 0x9040, weights.wk.size()},
        {weights.wv.data(), 0x9080, weights.wv.size()},
        {weights.wout.data(), 0x90C0, weights.wout.size()},
        {weights.w1.data(), 0x9100, weights.w1.size()},
        {weights.w2.data(), 0x9180, weights.w2.size()},
    };
    for (const auto& block : blocks) {
        for (std::size_t i = 0; i < block.size; ++i) {
            if (!write_float(block.base + static_cast<std::uint32_t>(i),
                             block.data[i])) {
                return fail("cannot write causal-trunk weights");
            }
        }
    }
    return true;
}

bool RawFieldVM::write_trunk_inputs(
    const std::vector<std::array<float, kRawFeatureDim>>& tokens,
    const TrunkWeights& weights) {
    if (tokens.empty() || tokens.size() > kRawTrunkContext) {
        return fail("causal trunk token count outside 1..256");
    }
    auto write_float = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t tkn = 0; tkn < tokens.size(); ++tkn) {
        for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
            if (!write_float(kMicroX0 + static_cast<std::uint32_t>(tkn * 8 + d),
                             tokens[tkn][d])) {
                return fail("cannot write causal-trunk token");
            }
        }
    }
    return write_trunk_weights(weights);
}

bool RawFieldVM::trunk_feature(
    const std::vector<std::array<float, kRawFeatureDim>>& tokens,
    std::array<float, kRawFeatureDim>& out) {
    if (tokens.empty() || tokens.size() > kRawTrunkContext) {
        return fail("causal trunk token count outside 1..256");
    }
    auto write_float = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t tkn = 0; tkn < tokens.size(); ++tkn) {
        for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
            if (!write_float(kMicroX0 + static_cast<std::uint32_t>(tkn * 8 + d),
                             tokens[tkn][d])) {
                return fail("cannot write causal-trunk token");
            }
        }
    }
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(tokens.size())) ||
        !write_word(kCommandBase, 10)) {
        return fail("cannot write causal-trunk command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != kRawFeatureDim) {
        return fail("raw causal trunk returned the wrong feature count");
    }
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        const std::uint32_t bits = read_word(0xA000u + static_cast<std::uint32_t>(d));
        std::memcpy(&out[d], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::causal_trunk(
    const std::vector<std::array<float, kRawFeatureDim>>& tokens,
    const TrunkWeights& weights,
    std::array<float, kRawFeatureDim>& out) {
    if (!write_trunk_inputs(tokens, weights)) return false;
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(tokens.size())) ||
        !write_word(kCommandBase, 10)) {
        return fail("cannot write causal-trunk command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != kRawFeatureDim) {
        return fail("raw causal trunk returned the wrong feature count");
    }
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        const std::uint32_t bits = read_word(0xA000u + static_cast<std::uint32_t>(d));
        std::memcpy(&out[d], &bits, sizeof(bits));
    }
    return true;
}



bool RawFieldVM::causal_trunk_cached(
    const std::vector<std::array<float, kRawFeatureDim>>& tokens,
    std::array<float, kRawFeatureDim>& out) {
    if (tokens.empty() || tokens.size() > kRawTrunkContext) {
        return fail("cached causal trunk token count outside 1..256");
    }
    for (std::size_t tkn = 0; tkn < tokens.size(); ++tkn) {
        for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
            std::uint32_t bits = 0;
            std::memcpy(&bits, &tokens[tkn][d], sizeof(bits));
            if (!write_word(kMicroX0 + static_cast<std::uint32_t>(tkn * 8 + d),
                            bits)) {
                return fail("cannot write cached trunk token");
            }
        }
    }
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(tokens.size())) ||
        !write_word(kCommandBase, 10)) {
        return fail("cannot write cached causal-trunk command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != kRawFeatureDim) {
        return fail("cached causal trunk returned the wrong feature count");
    }
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        const std::uint32_t bits = read_word(0xA000u + static_cast<std::uint32_t>(d));
        std::memcpy(&out[d], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::readout_train(
    const std::vector<std::array<float, kRawFeatureDim>>& tokens,
    const TrunkWeights& weights, std::uint8_t target, float learning_rate,
    bool& correct, float& target_score, float& best_wrong_score,
    float& loss) {
    // Load tokens/weights once; the readout weights at 0xB000 persist.
    if (!write_trunk_inputs(tokens, weights)) return false;
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(tokens.size())) ||
        !write_word(kProposalBase + 1, target) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kCommandBase, 12)) {
        return fail("cannot write readout-train command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ts = read_word(kResultBase + 1);
    const std::uint32_t bs = read_word(kResultBase + 2);
    const std::uint32_t ls = read_word(kResultBase + 3);
    std::memcpy(&target_score, &ts, sizeof(ts));
    std::memcpy(&best_wrong_score, &bs, sizeof(bs));
    std::memcpy(&loss, &ls, sizeof(ls));
    return true;
}

bool RawFieldVM::readout_only(
    const std::array<float, kRawFeatureDim>& feature, std::uint8_t target,
    float learning_rate, bool& correct, float& target_score,
    float& best_wrong_score, float& loss) {
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &feature[d], sizeof(bits));
        if (!write_word(0xA000u + static_cast<std::uint32_t>(d), bits)) {
            return fail("cannot write readout feature");
        }
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kCommandBase, 16)) {
        return fail("cannot write readout-only command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ts = read_word(kResultBase + 1);
    const std::uint32_t bs = read_word(kResultBase + 2);
    const std::uint32_t ls = read_word(kResultBase + 3);
    std::memcpy(&target_score, &ts, sizeof(ts));
    std::memcpy(&best_wrong_score, &bs, sizeof(bs));
    std::memcpy(&loss, &ls, sizeof(ls));
    return true;
}


bool RawFieldVM::set_readout_row(
    std::uint8_t row, const std::array<float, kRawFeatureDim>& values) {
    if (row >= 255) return fail("readout row outside 0..254");
    for (std::size_t i = 0; i < values.size(); ++i) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &values[i], sizeof(bits));
        if (!write_word(0xB000u + static_cast<std::uint32_t>(row * 8 + i),
                        bits)) {
            return fail("cannot write readout row");
        }
    }
    return true;
}

bool RawFieldVM::readout_sample(
    const std::array<float, kRawFeatureDim>& feature, std::uint8_t target,
    float learning_rate, bool& correct, float& target_score,
    float& best_wrong_score, float& loss) {
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &feature[d], sizeof(bits));
        if (!write_word(0xA000u + static_cast<std::uint32_t>(d), bits)) {
            return fail("cannot write sampled readout feature");
        }
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kCommandBase, 17)) {
        return fail("cannot write sampled readout command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ts = read_word(kResultBase + 1);
    const std::uint32_t bs = read_word(kResultBase + 2);
    const std::uint32_t ls = read_word(kResultBase + 3);
    std::memcpy(&target_score, &ts, sizeof(ts));
    std::memcpy(&best_wrong_score, &bs, sizeof(bs));
    std::memcpy(&loss, &ls, sizeof(ls));
    return true;
}

void RawFieldVM::reset_readout() {
    for (std::uint32_t i = 0; i < 255u * 8u; ++i) {
        (void)write_word(0xB000u + i, 0);
    }
}

bool RawFieldVM::field_commit(
    const std::array<std::int32_t, kTriadCount>& credits,
    std::int32_t threshold,
    std::array<std::uint8_t, kTriadCount>& votes,
    std::uint16_t& accepted_count, bool& committed) {
    for (std::size_t i = 0; i < credits.size(); ++i) {
        if (!write_word(0x7000 + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i])) ||
            !write_word(0x7100 + static_cast<std::uint32_t>(i), 0)) {
            return fail("cannot write field commit credits");
        }
    }
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(threshold)) ||
        !write_word(kCommandBase, 11)) {
        return fail("cannot write field commit command");
    }
    if (!run_command()) return false;
    accepted_count = static_cast<std::uint16_t>(read_word(kResultBase + 0));
    committed = (read_word(kResultBase + 1) & 1u) != 0;
    for (std::size_t i = 0; i < votes.size(); ++i) {
        votes[i] = static_cast<std::uint8_t>(read_word(0x7100 +
                                                      static_cast<std::uint32_t>(i)) & 1u);
    }
    return true;
}


bool RawFieldVM::causal_trunk_wide(
    const std::vector<float>& tokens, std::size_t count,
    const WideTrunkWeights& weights, std::vector<float>& out) {
    const std::size_t d = weights.dim;
    const std::size_t h = weights.hidden;
    if (count == 0 || count > 1024 || d == 0 || d > 128 || h == 0 || h > 512 ||
        tokens.size() != count * d ||
        weights.wq.size() != d * d || weights.wk.size() != d * d ||
        weights.wv.size() != d * d || weights.wout.size() != d * d ||
        weights.w1.size() != h * d || weights.w2.size() != d * h) {
        return fail("wide causal trunk dimensions are invalid");
    }
    auto write_float = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t i = 0; i < tokens.size(); ++i) {
        if (!write_float(0x10000u + static_cast<std::uint32_t>(i), tokens[i])) {
            return fail("cannot write wide-trunk tokens");
        }
    }
    const struct {
        const std::vector<float>* values;
        std::uint32_t base;
    } blocks[] = {
        {&weights.wq, 0x60000u},
        {&weights.wk, 0x60000u + static_cast<std::uint32_t>(d * d)},
        {&weights.wv, 0x60000u + static_cast<std::uint32_t>(2 * d * d)},
        {&weights.wout, 0x60000u + static_cast<std::uint32_t>(3 * d * d)},
        {&weights.w1, 0x60000u + static_cast<std::uint32_t>(4 * d * d)},
        {&weights.w2, 0x60000u + static_cast<std::uint32_t>(4 * d * d + h * d)},
    };
    for (const auto& block : blocks) {
        for (std::size_t i = 0; i < block.values->size(); ++i) {
            if (!write_float(block.base + static_cast<std::uint32_t>(i),
                             (*block.values)[i])) {
                return fail("cannot write wide-trunk weights");
            }
        }
    }
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(d)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(h)) ||
        !write_word(kCommandBase, 13)) {
        return fail("cannot write wide-trunk command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != d) {
        return fail("raw wide trunk returned the wrong feature count " +
                    std::to_string(read_word(kResultBase)));
    }
    out.assign(d, 0.0f);
    for (std::size_t i = 0; i < d; ++i) {
        const std::uint32_t bits = read_word(0x200000u + static_cast<std::uint32_t>(i));
        std::memcpy(&out[i], &bits, sizeof(bits));
    }
    return true;
}


bool RawFieldVM::trunk_credit(std::uint8_t target, std::uint8_t best_wrong,
                              float learning_rate) {
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kCommandBase, 14)) {
        return fail("cannot write trunk-credit command");
    }
    if (!run_command()) return false;
    if ((read_word(kResultBase) & 1u) == 0) {
        return fail("raw trunk credit did not complete");
    }
    return true;
}


bool RawFieldVM::qkv_credit(std::uint8_t target, std::uint8_t best_wrong,
                            float learning_rate) {
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kCommandBase, 15)) {
        return fail("cannot write QKV-credit command");
    }
    if (!run_command()) return false;
    if ((read_word(kResultBase) & 1u) == 0) {
        return fail("raw QKV credit did not complete");
    }
    return true;
}

bool RawFieldVM::remap(const std::array<std::uint16_t, 6>& masks,
                       std::uint32_t a, std::uint32_t b, bool target,
                       bool& improved, std::int32_t& before,
                       std::int32_t& after) {
    for (std::size_t i = 0; i < masks.size(); ++i) {
        if (!write_word(kProposalBase + static_cast<std::uint32_t>(i), masks[i])) {
            return fail("cannot write remap masks");
        }
    }
    if (!write_word(kProposalBase + 6, a) ||
        !write_word(kProposalBase + 7, b) ||
        !write_word(kProposalBase + 8, target ? 1u : 0u) ||
        !write_word(kCommandBase, 4)) {
        return fail("cannot write remap command");
    }
    if (!run_command()) return false;
    improved = (read_word(kResultBase + 0) & 1u) != 0;
    before = static_cast<std::int32_t>(read_word(kResultBase + 1));
    after = static_cast<std::int32_t>(read_word(kResultBase + 2));
    return true;
}

bool RawFieldVM::remap_general(const std::array<std::uint16_t, 6>& masks,
                                std::uint8_t slot_a, std::uint8_t slot_b,
                                std::uint32_t a, std::uint32_t b, bool target,
                                bool& improved, std::int32_t& before,
                                std::int32_t& after) {
    if (slot_a >= kTriadSize || slot_b >= kTriadSize)
        return fail("remap slot outside 0..2");
    for (std::size_t i = 0; i < masks.size(); ++i) {
        if (!write_word(kProposalBase + static_cast<std::uint32_t>(i), masks[i]))
            return fail("cannot write general remap masks");
    }
    if (!write_word(kProposalBase + 6, a) ||
        !write_word(kProposalBase + 7, b) ||
        !write_word(kProposalBase + 8, target ? 1u : 0u) ||
        !write_word(kProposalBase + 9, slot_a) ||
        !write_word(kProposalBase + 10, slot_b) ||
        !write_word(kCommandBase, 5)) {
        return fail("cannot write general remap command");
    }
    if (!run_command()) return false;
    improved = (read_word(kResultBase + 0) & 1u) != 0;
    before = static_cast<std::int32_t>(read_word(kResultBase + 1));
    after = static_cast<std::int32_t>(read_word(kResultBase + 2));
    return true;
}

bool RawFieldVM::remap_chart(Universe& universe, HeadArray& heads,
                             std::uint8_t triad_a, std::uint8_t slot_a,
                             std::uint8_t triad_b, std::uint8_t slot_b,
                             std::uint32_t a, std::uint32_t b, bool target,
                             bool& improved, std::int32_t& before,
                             std::int32_t& after) {
    if (triad_a >= kTriadCount || triad_b >= kTriadCount ||
        triad_a == triad_b || slot_a >= kTriadSize || slot_b >= kTriadSize) {
        return fail("invalid general remap triad/slot");
    }
    const auto& table = universe.triad_members();
    const std::size_t base_a = static_cast<std::size_t>(triad_a) * kTriadSize;
    const std::size_t base_b = static_cast<std::size_t>(triad_b) * kTriadSize;
    std::array<std::uint16_t, 6> masks = {
        heads.at(table[base_a + 0]).boolean_mask(),
        heads.at(table[base_a + 1]).boolean_mask(),
        heads.at(table[base_a + 2]).boolean_mask(),
        heads.at(table[base_b + 0]).boolean_mask(),
        heads.at(table[base_b + 1]).boolean_mask(),
        heads.at(table[base_b + 2]).boolean_mask(),
    };
    if (!remap_general(masks, slot_a, slot_b, a, b, target,
                       improved, before, after)) return false;
    if (!improved) {
        bump_triad_credit(universe.triad_credit()[triad_a], -1);
        bump_triad_credit(universe.triad_credit()[triad_b], -1);
        return true;
    }
    const std::uint8_t head_a = table[base_a + slot_a];
    const std::uint8_t head_b = table[base_b + slot_b];
    universe.triad_members()[base_a + slot_a] = head_b;
    universe.triad_members()[base_b + slot_b] = head_a;
    universe.triad_of()[head_b] = triad_a;
    universe.triad_slot()[head_b] = slot_a;
    universe.triad_of()[head_a] = triad_b;
    universe.triad_slot()[head_a] = slot_b;
    universe.triad_votes()[triad_a] = 0;
    universe.triad_votes()[triad_b] = 0;
    bump_triad_credit(universe.triad_credit()[triad_a], 1);
    bump_triad_credit(universe.triad_credit()[triad_b], 1);
    if (!field_vote(universe)) return false;
    if (!coherence(universe)) return false;
    return true;
}

bool RawFieldVM::field_vote(Universe& universe) {
    std::uint16_t accepted = 0;
    bool field_ok = false;
    if (!field_vote(universe.triad_votes(), accepted, field_ok)) return false;
    universe.triad_field_count() = accepted;
    return true;
}

bool RawFieldVM::coherence(Universe& universe) {
    std::array<std::uint16_t, kTriadMemberCount> phases{};
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        for (std::size_t s = 0; s < kTriadSize; ++s) {
            const std::uint8_t h = universe.triad_members()[t * kTriadSize + s];
            phases[t * kTriadSize + s] =
                static_cast<std::uint16_t>(universe.head(h).phase & 0xFFFFu);
        }
    }
    std::int32_t q16 = 0;
    if (!coherence(phases, q16)) return false;
    universe.field_coherence() = q16;
    return true;
}

} // namespace nanlm
