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
constexpr std::uint32_t kContextCreditArgs = 0x7300;
constexpr std::uint32_t kContextVotes = 0x7100;
constexpr std::uint32_t kContextBackoffTable = 0x40000;
constexpr std::uint32_t kContextBackoffTableWords = 32768u * 3u;
constexpr std::uint32_t kContextBackoffHist = 0x58000;
constexpr std::uint32_t kContextBackoffHistWords = 4096u;
constexpr std::uint32_t kContextBackoffCommand = 30;
constexpr std::uint32_t kMaxSteps = 200'000'000;
constexpr std::uint32_t kContextTableBase = 0x100000;
constexpr std::uint32_t kContextWordsPerBucket = 272;
constexpr std::uint32_t kGuestWordCount = 0x400000;

void bump_triad_credit(std::int16_t& value, int delta) {
    const int next = static_cast<int>(value) + delta;
    value = static_cast<std::int16_t>(std::max(-32768, std::min(32767, next)));
}

constexpr std::uint32_t kContextMapBase = 0x60000u;
constexpr std::uint32_t kContextCopyBase = 0x80000u;
constexpr std::uint32_t kContextMapSlots = 16384u;
constexpr std::uint32_t kContextMapWords = kContextMapSlots * 3u;
constexpr std::uint32_t kContextAuxMax = 1024u;

// Keep this byte order and mixing identical to mth_context_copy.nas.
std::uint32_t context_copy_hash(std::uint32_t key) {
    std::uint32_t hash = 2166136261u;
    for (int shift = 24; shift >= 0; shift -= 8) {
        hash = (hash ^ ((key >> shift) & 0xFFu)) * 16777619u;
    }
    return hash;
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



bool RawFieldVM::context_encode(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions,
    const std::vector<std::array<float, kRawFeatureDim>>& word_embeddings,
    const std::array<std::array<float, kRawFeatureDim>, 4>& position_gates,
    const std::array<float, kRawFeatureDim>& bias,
    const std::array<float, kRawFeatureDim>& order, float orientation,
    std::array<float, kRawFeatureDim>& out) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count ||
        word_embeddings.size() < 64) {
        return fail("context encoder dimensions invalid");
    }
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t i = 0; i < token_count; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i])) {
            return fail("cannot write context token");
        }
    }
    for (std::size_t t = 0; t < 64; ++t)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7100u + static_cast<std::uint32_t>(t * 8 + d),
                    word_embeddings[t][d])) return fail("cannot write word embedding");
    for (std::size_t p = 0; p < 4; ++p)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7300u + static_cast<std::uint32_t>(p * 8 + d),
                    position_gates[p][d])) return fail("cannot write position gate");
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        if (!wf(0x7380u + static_cast<std::uint32_t>(d), bias[d]) ||
            !wf(0x7390u + static_cast<std::uint32_t>(d), order[d])) {
            return fail("cannot write context bias");
        }
    }
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 50)) {
        return fail("cannot write context-encode command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != kRawFeatureDim) return fail("context encode count");
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        const std::uint32_t bits = read_word(0x73A0u + static_cast<std::uint32_t>(d));
        std::memcpy(&out[d], &bits, sizeof(bits));
    }
    return true;
}




bool RawFieldVM::sense_step(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions,
    const std::vector<std::array<float, kRawFeatureDim>>& word_embeddings,
    const std::array<std::array<float, kRawFeatureDim>, 4>& position_gates,
    const std::array<float, kRawFeatureDim>& bias,
    const std::array<float, kRawFeatureDim>& order,
    const std::vector<std::array<float, kRawFeatureDim>>& sense_heads,
    const std::vector<float>& sense_bias, std::size_t target,
    float learning_rate, float orientation, float& probability, float& loss) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count || word_embeddings.size() < 64 ||
        sense_heads.empty() || sense_heads.size() > 8 ||
        sense_bias.size() != sense_heads.size() || target >= sense_heads.size()) {
        return fail("sense-step dimensions invalid");
    }
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t i = 0; i < token_count; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i]))
            return fail("cannot write sense tokens");
    for (std::size_t i = 0; i < 64; ++i)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7100u + static_cast<std::uint32_t>(i * 8 + d),
                    word_embeddings[i][d])) return fail("cannot write sense embeddings");
    for (std::size_t p = 0; p < 4; ++p)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7300u + static_cast<std::uint32_t>(p * 8 + d),
                    position_gates[p][d])) return fail("cannot write sense gates");
    for (std::size_t d = 0; d < kRawFeatureDim; ++d)
        if (!wf(0x7380u + static_cast<std::uint32_t>(d), bias[d]) ||
            !wf(0x7390u + static_cast<std::uint32_t>(d), order[d]))
            return fail("cannot write sense vectors");
    for (std::size_t k = 0; k < sense_heads.size(); ++k) {
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7600u + static_cast<std::uint32_t>(k * 8 + d),
                    sense_heads[k][d])) return fail("cannot write sense head");
        if (!wf(0x7700u + static_cast<std::uint32_t>(k), sense_bias[k]))
            return fail("cannot write sense bias");
    }
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!wf(0x7522u, learning_rate) ||
        !write_word(0x4003u, static_cast<std::uint32_t>(sense_heads.size())) ||
        !write_word(0x7523u, static_cast<std::uint32_t>(target)) ||
        !write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 52)) return fail("cannot write sense-step command");
    if (!run_command()) return false;
    const std::uint32_t pbits = read_word(kResultBase);
    const std::uint32_t lbits = read_word(kResultBase + 1);
    std::memcpy(&probability, &pbits, sizeof(pbits));
    std::memcpy(&loss, &lbits, sizeof(lbits));
    return true;
}
bool RawFieldVM::read_sense_state(
    std::size_t count, std::vector<std::array<float, kRawFeatureDim>>& heads,
    std::vector<float>& biases) const {
    if (count == 0 || count > 8) return false;
    heads.assign(count, {});
    biases.assign(count, 0.0f);
    for (std::size_t k = 0; k < count; ++k) {
        for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
            const std::uint32_t bits = read_word(0x7600u + static_cast<std::uint32_t>(k * 8 + d));
            std::memcpy(&heads[k][d], &bits, sizeof(bits));
        }
        const std::uint32_t bits = read_word(0x7700u + static_cast<std::uint32_t>(k));
        std::memcpy(&biases[k], &bits, sizeof(bits));
    }
    return true;
}


bool RawFieldVM::semantic_query(
    const std::vector<std::pair<std::uint8_t, std::uint8_t>>& isa_edges,
    const std::vector<std::pair<std::uint8_t, std::uint8_t>>& negative_isa,
    const std::vector<SemanticAbility>& abilities,
    std::uint8_t query_type, std::uint8_t subject,
    std::uint8_t object_or_action, std::uint8_t& state,
    std::uint8_t& depth) {
    if (isa_edges.size() > 64 || negative_isa.size() > 32 ||
        abilities.size() > 64 || subject >= 32 || object_or_action >= 32) {
        return fail("semantic query bounds invalid");
    }
    for (std::size_t i = 0; i < isa_edges.size(); ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(2 * i), isa_edges[i].first) ||
            !write_word(0x7001u + static_cast<std::uint32_t>(2 * i), isa_edges[i].second))
            return fail("cannot write semantic ISA edges");
    }
    for (std::size_t i = 0; i < negative_isa.size(); ++i) {
        if (!write_word(0x7100u + static_cast<std::uint32_t>(2 * i), negative_isa[i].first) ||
            !write_word(0x7101u + static_cast<std::uint32_t>(2 * i), negative_isa[i].second))
            return fail("cannot write semantic negative edges");
    }
    for (std::size_t i = 0; i < abilities.size(); ++i) {
        if (!write_word(0x7200u + static_cast<std::uint32_t>(3 * i), abilities[i].subject) ||
            !write_word(0x7201u + static_cast<std::uint32_t>(3 * i), abilities[i].action) ||
            !write_word(0x7202u + static_cast<std::uint32_t>(3 * i), abilities[i].positive))
            return fail("cannot write semantic abilities");
    }
    if (!write_word(0x7300u, query_type) ||
        !write_word(0x7301u, subject) ||
        !write_word(0x7302u, object_or_action) ||
        !write_word(0x4001u, static_cast<std::uint32_t>(isa_edges.size())) ||
        !write_word(0x4002u, static_cast<std::uint32_t>(negative_isa.size())) ||
        !write_word(0x4003u, static_cast<std::uint32_t>(abilities.size())) ||
        !write_word(kCommandBase, 53)) return fail("cannot write semantic query command");
    if (!run_command()) return false;
    state = static_cast<std::uint8_t>(read_word(kResultBase) & 3u);
    depth = static_cast<std::uint8_t>(read_word(kResultBase + 1) & 0xFFu);
    return true;
}

bool RawFieldVM::read_role_state(std::array<float, kRawFeatureDim>& relation,
                                 float& relation_bias) const {
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        const std::uint32_t bits = read_word(0x7500u + static_cast<std::uint32_t>(d));
        std::memcpy(&relation[d], &bits, sizeof(bits));
    }
    const std::uint32_t bits = read_word(0x7520u);
    std::memcpy(&relation_bias, &bits, sizeof(bits));
    return true;
}


bool RawFieldVM::init_context24(
    const std::vector<std::array<float, 24>>& word_embeddings,
    const std::array<std::array<float, 24>, 4>& position_gates,
    const std::array<float, 24>& bias,
    const std::array<float, 24>& order) {
    if (word_embeddings.size() < 64) return fail("context24 embeddings short");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t t = 0; t < 64; ++t)
        for (std::size_t d = 0; d < 24; ++d)
            if (!wf(0x8000u + static_cast<std::uint32_t>(t * 24 + d),
                    word_embeddings[t][d])) return fail("init context24 embedding");
    for (std::size_t p = 0; p < 4; ++p)
        for (std::size_t d = 0; d < 24; ++d)
            if (!wf(0x8600u + static_cast<std::uint32_t>(p * 24 + d),
                    position_gates[p][d])) return fail("init context24 gate");
    for (std::size_t d = 0; d < 24; ++d)
        if (!wf(0x8700u + static_cast<std::uint32_t>(d), bias[d]) ||
            !wf(0x8720u + static_cast<std::uint32_t>(d), order[d]))
            return fail("init context24 vector");
    return true;
}

bool RawFieldVM::init_role24(const std::array<float, 24>& relation,
                             float relation_bias) {
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t d = 0; d < 24; ++d)
        if (!wf(0x8760u + static_cast<std::uint32_t>(d), relation[d]))
            return fail("init role24 relation");
    return wf(0x8780u, relation_bias);
}


bool RawFieldVM::init_role24k(
    const std::vector<std::array<float, 24>>& relation_heads,
    const std::vector<float>& relation_bias) {
    if (relation_heads.empty() || relation_heads.size() > 8 ||
        relation_bias.size() != relation_heads.size())
        return fail("role24k init bounds");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t k = 0; k < relation_heads.size(); ++k) {
        for (std::size_t d = 0; d < 24; ++d)
            if (!wf(0x8A00u + static_cast<std::uint32_t>(k * 24 + d),
                    relation_heads[k][d])) return fail("role24k head");
        if (!wf(0x8C00u + static_cast<std::uint32_t>(k), relation_bias[k]))
            return fail("role24k bias");
    }
    return write_word(0x8C08u, static_cast<std::uint32_t>(relation_heads.size()));
}




bool RawFieldVM::read_context24(
    std::vector<std::array<float, 24>>& word_embeddings,
    std::array<std::array<float, 24>, 4>& position_gates,
    std::array<float, 24>& bias, std::array<float, 24>& order) {
    auto rf = [&](std::uint32_t index, float& value) {
        const std::uint32_t bits = read_word(index);
        std::memcpy(&value, &bits, sizeof(value));
    };
    word_embeddings.assign(64, {});
    for (std::size_t t = 0; t < 64; ++t)
        for (std::size_t d = 0; d < 24; ++d)
            rf(0x8000u + static_cast<std::uint32_t>(t * 24 + d),
               word_embeddings[t][d]);
    for (std::size_t p = 0; p < 4; ++p)
        for (std::size_t d = 0; d < 24; ++d)
            rf(0x8600u + static_cast<std::uint32_t>(p * 24 + d),
               position_gates[p][d]);
    for (std::size_t d = 0; d < 24; ++d) {
        rf(0x8700u + static_cast<std::uint32_t>(d), bias[d]);
        rf(0x8720u + static_cast<std::uint32_t>(d), order[d]);
    }
    return true;
}

bool RawFieldVM::read_sense24(
    std::vector<std::array<float, 24>>& heads, std::vector<float>& biases) {
    const std::uint32_t count = read_word(0x4003u);
    if (count == 0 || count > 8) return fail("sense24 state count");
    heads.assign(count, {});
    biases.assign(count, 0.0f);
    for (std::uint32_t k = 0; k < count; ++k) {
        for (std::uint32_t d = 0; d < 24; ++d) {
            const std::uint32_t bits = read_word(0x8800u + k * 24u + d);
            std::memcpy(&heads[k][d], &bits, sizeof(bits));
        }
        const std::uint32_t bits = read_word(0x8900u + k);
        std::memcpy(&biases[k], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::read_role24k_state(
    std::vector<std::array<float, 24>>& heads, std::vector<float>& biases) {
    const std::uint32_t count = read_word(0x8C08u);
    if (count == 0 || count > 8) return fail("role24k state count");
    heads.assign(count, {});
    biases.assign(count, 0.0f);
    for (std::uint32_t k = 0; k < count; ++k) {
        for (std::uint32_t d = 0; d < 24; ++d) {
            const std::uint32_t bits = read_word(0x8A00u + k * 24u + d);
            std::memcpy(&heads[k][d], &bits, sizeof(bits));
        }
        const std::uint32_t bits = read_word(0x8C00u + k);
        std::memcpy(&biases[k], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::role_step24k_cached(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions, std::size_t target_relation,
    float label, float learning_rate, float orientation, float& probability,
    float& delta) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count) return fail("role24k token count");
    for (std::size_t i = 0; i < token_count; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i]))
            return fail("role24k tokens");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!wf(0x8781u, label) || !wf(0x8782u, learning_rate) ||
        !write_word(0x8C09u, static_cast<std::uint32_t>(target_relation)) ||
        !write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 57)) return fail("role24k command");
    if (!run_command()) return false;
    const std::uint32_t pbits = read_word(kResultBase);
    const std::uint32_t dbits = read_word(kResultBase + 1);
    std::memcpy(&probability, &pbits, sizeof(pbits));
    std::memcpy(&delta, &dbits, sizeof(dbits));
    return true;
}

bool RawFieldVM::role_step24_cached(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions, float label,
    float learning_rate, float orientation, float& probability, float& delta) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count) return fail("role24 token count");
    for (std::size_t i = 0; i < token_count; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i]))
            return fail("role24 tokens");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!wf(0x8781u, label) || !wf(0x8782u, learning_rate) ||
        !write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 55)) return fail("role24 command");
    if (!run_command()) return false;
    const std::uint32_t pbits = read_word(kResultBase);
    const std::uint32_t dbits = read_word(kResultBase + 1);
    std::memcpy(&probability, &pbits, sizeof(pbits));
    std::memcpy(&delta, &dbits, sizeof(dbits));
    return true;
}

bool RawFieldVM::init_sense24(
    const std::vector<std::array<float, 24>>& sense_heads,
    const std::vector<float>& sense_bias) {
    if (sense_heads.empty() || sense_heads.size() > 8 ||
        sense_bias.size() != sense_heads.size()) return fail("sense24 init bounds");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t k = 0; k < sense_heads.size(); ++k) {
        for (std::size_t d = 0; d < 24; ++d)
            if (!wf(0x8800u + static_cast<std::uint32_t>(k * 24 + d),
                    sense_heads[k][d])) return fail("sense24 head");
        if (!wf(0x8900u + static_cast<std::uint32_t>(k), sense_bias[k]))
            return fail("sense24 bias");
    }
    return write_word(0x4003u, static_cast<std::uint32_t>(sense_heads.size()));
}

bool RawFieldVM::sense_step24_cached(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions, std::size_t target,
    float learning_rate, float orientation, float& probability, float& loss) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count) return fail("sense24 token count");
    for (std::size_t i = 0; i < token_count; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i]))
            return fail("sense24 tokens");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!wf(0x8782u, learning_rate) ||
        !write_word(0x8783u, static_cast<std::uint32_t>(target)) ||
        !write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 56)) return fail("sense24 command");
    if (!run_command()) return false;
    const std::uint32_t pbits = read_word(kResultBase);
    const std::uint32_t lbits = read_word(kResultBase + 1);
    std::memcpy(&probability, &pbits, sizeof(pbits));
    std::memcpy(&loss, &lbits, sizeof(lbits));
    return true;
}

bool RawFieldVM::role_step(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions,
    const std::vector<std::array<float, kRawFeatureDim>>& word_embeddings,
    const std::array<std::array<float, kRawFeatureDim>, 4>& position_gates,
    const std::array<float, kRawFeatureDim>& bias,
    const std::array<float, kRawFeatureDim>& order,
    const std::array<float, kRawFeatureDim>& relation,
    float relation_bias, float label, float learning_rate,
    float orientation, float& probability, float& delta) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count || word_embeddings.size() < 64) {
        return fail("role-step dimensions invalid");
    }
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t i = 0; i < token_count; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i]))
            return fail("cannot write role tokens");
    }
    for (std::size_t i = 0; i < 64; ++i)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7100u + static_cast<std::uint32_t>(i * 8 + d),
                    word_embeddings[i][d])) return fail("cannot write role embeddings");
    for (std::size_t p = 0; p < 4; ++p)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7300u + static_cast<std::uint32_t>(p * 8 + d),
                    position_gates[p][d])) return fail("cannot write role gates");
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        if (!wf(0x7380u + static_cast<std::uint32_t>(d), bias[d]) ||
            !wf(0x7390u + static_cast<std::uint32_t>(d), order[d]) ||
            !wf(0x7500u + static_cast<std::uint32_t>(d), relation[d])) {
            return fail("cannot write role vectors");
        }
    }
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!wf(0x7520u, relation_bias) || !wf(0x7521u, label) ||
        !wf(0x7522u, learning_rate) ||
        !write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 51)) {
        return fail("cannot write role-step command");
    }
    if (!run_command()) return false;
    const std::uint32_t pbits = read_word(kResultBase);
    const std::uint32_t dbits = read_word(kResultBase + 1);
    std::memcpy(&probability, &pbits, sizeof(pbits));
    std::memcpy(&delta, &dbits, sizeof(dbits));
    return true;
}

bool RawFieldVM::holo(const std::array<std::uint16_t, 3>& phases,
                      std::array<std::int32_t, 2>& out) {
    for (std::size_t i = 0; i < phases.size(); ++i)
        if (!write_word(kProposalBase + static_cast<std::uint32_t>(i), phases[i]))
            return fail("cannot write HOLO phases");
    if (!write_word(kCommandBase, 35)) return fail("cannot write HOLO command");
    if (!run_command()) return false;
    out[0] = static_cast<std::int32_t>(read_word(kResultBase));
    out[1] = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}
bool RawFieldVM::ring(const std::array<std::uint16_t, kTriadMemberCount>& phases,
                      std::uint32_t shift, std::int32_t& correlation) {
    if (shift >= kTriadMemberCount) return fail("RING shift outside ring");
    for (std::size_t i = 0; i < phases.size(); ++i)
        if (!write_word(kCoherencePhases + static_cast<std::uint32_t>(i), phases[i]))
            return fail("cannot write RING phases");
    if (!write_word(kProposalBase, shift) || !write_word(kCommandBase, 36))
        return fail("cannot write RING command");
    if (!run_command()) return false;
    correlation = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}
bool RawFieldVM::leaf(std::uint32_t row_bits, std::uint32_t leaf_mask,
                      std::int32_t counter_q16, std::array<std::int32_t, 2>& out) {
    if (!write_word(kProposalBase, row_bits) ||
        !write_word(kProposalBase + 1, leaf_mask) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(counter_q16)) ||
        !write_word(kCommandBase, 37)) return fail("cannot write LEAF command");
    if (!run_command()) return false;
    out[0] = static_cast<std::int32_t>(read_word(kResultBase));
    out[1] = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}
bool RawFieldVM::tca(std::int32_t local, std::int32_t peer_a, std::int32_t peer_b,
                     std::int32_t& advantage) {
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(local)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(peer_a)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(peer_b)) ||
        !write_word(kCommandBase, 38)) return fail("cannot write TCA command");
    if (!run_command()) return false;
    advantage = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}
bool RawFieldVM::flux(std::int32_t phase_u, std::int32_t phase_v,
                      std::int32_t weight, std::int32_t source,
                      std::array<std::int32_t, 3>& out) {
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(phase_u)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(phase_v)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(weight)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(source)) ||
        !write_word(kCommandBase, 39)) return fail("cannot write FLUX command");
    if (!run_command()) return false;
    for (std::size_t i = 0; i < out.size(); ++i)
        out[i] = static_cast<std::int32_t>(read_word(kResultBase + i));
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

bool RawFieldVM::context_class_map(
    const ContextClassInput& input,
    const std::array<std::int32_t, kTriadMemberCount>& credits,
    ContextClassResult& out) {
    return context_class_credit(input, ContextCreditInput{}, credits, out);
}

bool RawFieldVM::context_class_credit(
    const ContextClassInput& input,
    const ContextCreditInput& credit,
    const std::array<std::int32_t, kTriadMemberCount>& credits,
    ContextClassResult& out) {
    if (input.buckets == 0 || input.buckets > 16384) {
        return fail("context class bucket count outside 1..16384");
    }
    if (!input.direct && input.bucket >= input.buckets) {
        return fail("context class bucket is outside the table");
    }
    if (input.direct &&
        (input.direct_high > 15 || input.direct_low > 15)) {
        return fail("context class direct nibble outside 0..15");
    }
    if (credit.kind != ContextCreditKind::None &&
        credit.kind != ContextCreditKind::Cft &&
        credit.kind != ContextCreditKind::Trail) {
        return fail("unknown context credit kind");
    }
    for (std::size_t i = 0; i < credits.size(); ++i) {
        if (!write_word(kHotCredits + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i]))) {
            return fail("cannot write context class head credits");
        }
    }
    if (!write_word(kProposalBase + 0, input.high_table) ||
        !write_word(kProposalBase + 1,
                    static_cast<std::uint32_t>(input.buckets)) ||
        !write_word(kProposalBase + 2, input.bucket) ||
        !write_word(kProposalBase + 3, input.low_table) ||
        !write_word(kProposalBase + 4, input.direct ? 1u : 0u) ||
        !write_word(kProposalBase + 5, input.direct_high) ||
        !write_word(kProposalBase + 6, input.direct_low) ||
        !write_word(kProposalBase + 7,
                    static_cast<std::uint32_t>(credit.kind)) ||
        !write_word(kProposalBase + 8,
                    static_cast<std::uint32_t>(input.head_threshold))) {
        return fail("cannot write context class mapping command");
    }
    for (std::size_t i = 0; i < credit.cft.size(); ++i) {
        if (!write_word(kProposalBase + 9 + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credit.cft[i]))) {
            return fail("cannot write context CFT arguments");
        }
    }
    if (credit.kind == ContextCreditKind::Trail) {
        for (std::size_t i = 0; i < credit.trail.size(); ++i) {
            if (!write_word(kContextCreditArgs + static_cast<std::uint32_t>(i),
                            static_cast<std::uint32_t>(credit.trail[i]))) {
                return fail("cannot write context TRAIL arguments");
            }
        }
    }
    if (!write_word(kCommandBase, 30)) {
        return fail("cannot write context class command");
    }
    if (!run_command()) return false;

    out.high = static_cast<std::uint8_t>(read_word(kResultBase + 0) & 15u);
    out.low = static_cast<std::uint8_t>(read_word(kResultBase + 1) & 15u);
    out.head = static_cast<std::uint8_t>(read_word(kResultBase + 2) & 255u);
    const std::uint32_t triad = read_word(kResultBase + 3);
    const std::uint32_t member = read_word(kResultBase + 4);
    out.field_head = (read_word(kResultBase + 12) & 1u) != 0;
    if (out.field_head) {
        if (out.head != kFieldHead || triad != 0xFFFFu || member != 0xFFFFu) {
            return fail("context class field head result is inconsistent");
        }
        out.triad = 0xFFFFu;
        out.member = 0xFFFFu;
    } else {
        if (out.head >= kFieldHead || triad >= kTriadCount ||
            member >= kTriadSize) {
            return fail("context class result is outside the triad topology");
        }
        out.triad = static_cast<std::uint16_t>(triad);
        out.member = static_cast<std::uint16_t>(member);
    }
    const std::uint32_t accepted = read_word(kResultBase + 5);
    if (accepted > kTriadCount) {
        return fail("context class accepted-triad count exceeds 85");
    }
    out.accepted_triads = static_cast<std::uint16_t>(accepted);
    out.field_accepted = (read_word(kResultBase + 6) & 1u) != 0;
    out.triad_accepted = (read_word(kResultBase + 7) & 1u) != 0;
    out.head_credit_before =
        static_cast<std::int32_t>(read_word(kResultBase + 8));
    out.head_credit_after =
        static_cast<std::int32_t>(read_word(kResultBase + 9));
    out.credit_applied = (read_word(kResultBase + 10) & 1u) != 0;
    out.credit_delta = static_cast<std::int32_t>(read_word(kResultBase + 11));
    for (std::size_t i = 0; i < out.votes.size(); ++i) {
        out.votes[i] = static_cast<std::uint8_t>(
            read_word(kContextVotes + static_cast<std::uint32_t>(i)) & 1u);
    }
    return true;
}

bool RawFieldVM::context_class_apply(
    Universe& universe,
    const ContextClassInput& input,
    const ContextCreditInput& credit,
    ContextClassResult& out) {
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        for (std::size_t s = 0; s < kTriadSize; ++s) {
            if (universe.triad_members()[t * kTriadSize + s] !=
                static_cast<std::uint8_t>(t * kTriadSize + s)) {
                return fail("context class field link requires the canonical triad mapping");
            }
        }
    }
    std::array<std::int32_t, kTriadMemberCount> credits{};
    for (std::size_t i = 0; i < credits.size(); ++i) {
        credits[i] = universe.head_credit()[i];
    }
    if (!context_class_credit(input, credit, credits, out)) return false;
    if (out.head < kTriadMemberCount) {
        const int next = std::max<int>(
            -32768, std::min<int>(32767, out.head_credit_after));
        universe.head_credit()[out.head] = static_cast<std::int16_t>(next);
    }
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        universe.triad_votes()[t] = out.votes[t];
    }
    universe.triad_field_count() = out.accepted_triads;
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



bool RawFieldVM::read_trunk_weights(TrunkWeights& out) const {
    auto read_float = [&](std::uint32_t base, float* values, std::size_t count) {
        for (std::size_t i = 0; i < count; ++i) {
            const std::uint32_t bits = read_word(base + static_cast<std::uint32_t>(i));
            std::memcpy(&values[i], &bits, sizeof(bits));
        }
    };
    read_float(0x9000, out.wq.data(), out.wq.size());
    read_float(0x9040, out.wk.data(), out.wk.size());
    read_float(0x9080, out.wv.data(), out.wv.size());
    read_float(0x90C0, out.wout.data(), out.wout.size());
    read_float(0x9100, out.w1.data(), out.w1.size());
    read_float(0x9180, out.w2.data(), out.w2.size());
    return true;
}


bool RawFieldVM::read_wide_weights(std::size_t dim, std::size_t hidden,
                                   WideTrunkWeights& out) const {
    if (dim == 0 || dim > 128 || hidden == 0 || hidden > 512) return false;
    out.dim = dim;
    out.hidden = hidden;
    out.wq.resize(dim * dim);
    out.wk.resize(dim * dim);
    out.wv.resize(dim * dim);
    out.wout.resize(dim * dim);
    out.w1.resize(hidden * dim);
    out.w2.resize(dim * hidden);
    auto read_block = [&](std::uint32_t base, std::vector<float>& values) {
        for (std::size_t i = 0; i < values.size(); ++i) {
            const std::uint32_t bits = read_word(base + static_cast<std::uint32_t>(i));
            std::memcpy(&values[i], &bits, sizeof(bits));
        }
    };
    read_block(0x60000u, out.wq);
    read_block(0x60000u + static_cast<std::uint32_t>(dim * dim), out.wk);
    read_block(0x60000u + static_cast<std::uint32_t>(2 * dim * dim), out.wv);
    read_block(0x60000u + static_cast<std::uint32_t>(3 * dim * dim), out.wout);
    read_block(0x60000u + static_cast<std::uint32_t>(4 * dim * dim), out.w1);
    read_block(0x60000u + static_cast<std::uint32_t>(4 * dim * dim + hidden * dim),
               out.w2);
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
    float learning_rate, std::uint32_t salt, bool& correct,
    float& target_score, float& best_wrong_score, float& loss) {
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
        !write_word(kProposalBase + 2, salt) ||
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

bool RawFieldVM::readout_softmax(
    const std::array<float, kRawFeatureDim>& feature, std::uint8_t target,
    float learning_rate, bool& correct, float& loss,
    float& target_probability) {
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &feature[d], sizeof(bits));
        if (!write_word(0xA000u + static_cast<std::uint32_t>(d), bits)) {
            return fail("cannot write softmax readout feature");
        }
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kCommandBase, 19)) {
        return fail("cannot write softmax readout command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ls = read_word(kResultBase + 1);
    const std::uint32_t ps = read_word(kResultBase + 2);
    std::memcpy(&loss, &ls, sizeof(ls));
    std::memcpy(&target_probability, &ps, sizeof(ps));
    return true;
}

bool RawFieldVM::reset_hier_readout(std::size_t dim) {
    if (dim == 0 || dim > 256) return fail("hier readout dim outside 1..256");
    const std::size_t words = 16 * dim + 16 * 16 * dim;
    for (std::size_t i = 0; i < words; ++i) {
        if (!write_word(0xB000u + static_cast<std::uint32_t>(i), 0)) {
            return fail("cannot reset hierarchical readout");
        }
    }
    return true;
}

bool RawFieldVM::readout_hier(const float* feature, std::uint8_t target,
                              float learning_rate, std::size_t dim,
                              bool& correct, float& loss,
                              std::uint8_t& predicted_high,
                              std::uint8_t& predicted_low) {
    if (feature == nullptr || dim == 0 || dim > 256) {
        return fail("invalid hierarchical readout input");
    }
    for (std::size_t d = 0; d < dim; ++d) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &feature[d], sizeof(bits));
        if (!write_word(0xA000u + static_cast<std::uint32_t>(d), bits)) {
            return fail("cannot write hierarchical feature");
        }
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 21)) {
        return fail("cannot write hierarchical readout command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ls = read_word(kResultBase + 1);
    std::memcpy(&loss, &ls, sizeof(ls));
    predicted_high = static_cast<std::uint8_t>(read_word(kResultBase + 2) & 15u);
    predicted_low = static_cast<std::uint8_t>(read_word(kResultBase + 3) & 15u);
    return true;
}

bool RawFieldVM::phase_encode_wide(const std::uint8_t* bytes,
                                   std::size_t count, std::size_t dim,
                                   std::vector<std::int32_t>& out,
                                   std::uint32_t& shard) {
    if (!bytes || count == 0 || count > 64 || dim == 0 || dim > 128) {
        return fail("phase encode requires bytes 1..64 and dim 1..128");
    }
    for (std::size_t i = 0; i < count; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), bytes[i])) {
            return fail("cannot write phase input byte");
        }
    }
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 60)) {
        return fail("cannot write phase encode command");
    }
    if (!run_command()) return false;
    shard = read_word(kResultBase + 0) & 15u;
    out.resize(dim * 2);
    for (std::size_t i = 0; i < out.size(); ++i) {
        out[i] = static_cast<std::int32_t>(
            read_word(0x5200u + static_cast<std::uint32_t>(i)));
    }
    return true;
}


bool RawFieldVM::phase_rotate(const std::vector<std::int32_t>& in,
                              std::uint32_t turn,
                              std::vector<std::int32_t>& out) {
    if (in.size() < 2 || in.size() % 2 != 0 || in.size() / 2 > 128)
        return fail("phase rotate lanes must be 1..128");
    for (std::size_t i = 0; i < in.size(); ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(in[i])))
            return fail("cannot write phase rotate input");
    if (!write_word(kProposalBase + 0, turn) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(in.size() / 2)) ||
        !write_word(kCommandBase, 58)) return fail("cannot write phase rotate command");
    if (!run_command()) return false;
    out.resize(in.size());
    for (std::size_t i = 0; i < out.size(); ++i)
        out[i] = static_cast<std::int32_t>(read_word(0x7200u + static_cast<std::uint32_t>(i)));
    return true;
}

bool RawFieldVM::pq_encode(const std::vector<std::int32_t>& query,
                           const std::vector<std::int32_t>& codebook,
                           std::size_t codewords, std::size_t dim,
                           std::uint32_t& code, std::int32_t& distance) {
    if (codewords == 0 || codewords > 256 || dim == 0 || dim > 128 ||
        query.size() < dim || codebook.size() < codewords * dim)
        return fail("pq encode bounds invalid");
    for (std::size_t i = 0; i < dim; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(query[i])))
            return fail("cannot write pq query");
    for (std::size_t i = 0; i < codewords * dim; ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(codebook[i])))
            return fail("cannot write pq codebook");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(codewords)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 59)) return fail("cannot write pq command");
    if (!run_command()) return false;
    code = read_word(kResultBase + 0);
    distance = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}

bool RawFieldVM::spectral_iter(
    const std::array<std::int32_t, 64>& adjacency,
    const std::array<std::int32_t, 8>& in,
    std::array<std::int32_t, 8>& out) {
    for (std::size_t i = 0; i < adjacency.size(); ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(adjacency[i])))
            return fail("cannot write spectral adjacency");
    for (std::size_t i = 0; i < in.size(); ++i)
        if (!write_word(0x7040u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(in[i])))
            return fail("cannot write spectral input");
    if (!write_word(kCommandBase, 61)) return fail("cannot write spectral command");
    if (!run_command()) return false;
    for (std::size_t i = 0; i < out.size(); ++i)
        out[i] = static_cast<std::int32_t>(read_word(0x7080u + static_cast<std::uint32_t>(i)));
    return true;
}

bool RawFieldVM::sparse_knn(const std::vector<std::int32_t>& query,
                            const std::vector<std::int32_t>& bank,
                            std::size_t count, std::size_t dim, std::size_t k,
                            std::vector<std::uint32_t>& indices,
                            std::vector<std::int32_t>& scores) {
    if (count == 0 || count > 4096 || dim == 0 || dim > 128 || k == 0 || k > 4 ||
        query.size() < dim || bank.size() < count * dim)
        return fail("sparse kNN bounds invalid");
    for (std::size_t i = 0; i < dim; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(query[i])))
            return fail("cannot write kNN query");
    for (std::size_t i = 0; i < count * dim; ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(bank[i])))
            return fail("cannot write kNN bank");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(k)) ||
        !write_word(kCommandBase, 62)) return fail("cannot write kNN command");
    if (!run_command()) return false;
    indices.resize(k);
    scores.resize(k);
    for (std::size_t i = 0; i < k; ++i) {
        indices[i] = read_word(0x7200u + static_cast<std::uint32_t>(i));
        scores[i] = static_cast<std::int32_t>(read_word(0x7240u + static_cast<std::uint32_t>(i)));
    }
    return true;
}

bool RawFieldVM::pq_train(const std::vector<std::int32_t>& samples,
                          std::size_t count, std::size_t dim,
                          std::size_t codewords, std::size_t iterations,
                          std::vector<std::int32_t>& codebook) {
    if (count == 0 || count > 1024 || dim == 0 || dim > 128 ||
        codewords == 0 || codewords > 256 || iterations > 8 ||
        samples.size() < count * dim) {
        return fail("pq train bounds invalid");
    }
    for (std::size_t i = 0; i < count * dim; ++i) {
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(samples[i]))) {
            return fail("cannot write pq training samples");
        }
    }
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(codewords)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(iterations)) ||
        !write_word(kCommandBase, 69)) {
        return fail("cannot write pq training command");
    }
    if (!run_command()) return false;
    codebook.resize(codewords * dim);
    for (std::size_t i = 0; i < codebook.size(); ++i) {
        codebook[i] = static_cast<std::int32_t>(
            read_word(0x50000u + static_cast<std::uint32_t>(i)));
    }
    return true;
}


bool RawFieldVM::pq_update(const std::vector<std::int32_t>& samples,
                           std::size_t count, std::size_t dim,
                           std::size_t codewords, std::size_t iterations,
                           std::vector<std::int32_t>& codebook) {
    if (count == 0 || count > 1024 || dim == 0 || dim > 128 ||
        codewords == 0 || codewords > 256 || iterations > 8 ||
        samples.size() < count * dim || codebook.size() < codewords * dim)
        return fail("pq update bounds invalid");
    for (std::size_t i = 0; i < count * dim; ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(samples[i])))
            return fail("cannot write pq update samples");
    for (std::size_t i = 0; i < codewords * dim; ++i)
        if (!write_word(0x50000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(codebook[i])))
            return fail("cannot write pq update codebook");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(codewords)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(iterations)) ||
        !write_word(kCommandBase, 71)) return fail("cannot write pq update command");
    if (!run_command()) return false;
    codebook.resize(codewords * dim);
    for (std::size_t i = 0; i < codebook.size(); ++i)
        codebook[i] = static_cast<std::int32_t>(
            read_word(0x50000u + static_cast<std::uint32_t>(i)));
    return true;
}

bool RawFieldVM::pq_residuals(const std::vector<std::int32_t>& samples,
                              const std::vector<std::uint32_t>& codes,
                              std::size_t count, std::size_t dim,
                              const std::vector<std::int32_t>& codebook,
                              std::vector<std::int32_t>& residuals) {
    if (count == 0 || count > 1024 || dim == 0 || dim > 128 ||
        samples.size() < count * dim || codes.size() < count ||
        codebook.empty()) {
        return fail("pq residual bounds invalid");
    }
    for (std::size_t i = 0; i < count * dim; ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(samples[i])))
            return fail("cannot write pq residual samples");
    for (std::size_t i = 0; i < codebook.size(); ++i)
        if (!write_word(0x50000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(codebook[i])))
            return fail("cannot write pq residual codebook");
    for (std::size_t i = 0; i < count; ++i)
        if (!write_word(0x80000u + static_cast<std::uint32_t>(i), codes[i]))
            return fail("cannot write pq residual codes");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 70))
        return fail("cannot write pq residual command");
    if (!run_command()) return false;
    residuals.resize(count * dim);
    for (std::size_t i = 0; i < residuals.size(); ++i)
        residuals[i] = static_cast<std::int32_t>(
            read_word(0x90000u + static_cast<std::uint32_t>(i)));
    return true;
}


bool RawFieldVM::leaf_verify(const std::vector<std::int32_t>& expected,
                              const std::vector<std::int32_t>& codebook,
                              const std::vector<std::int32_t>& residual,
                              std::uint32_t code, std::size_t dim,
                              std::uint32_t tolerance, bool& accepted,
                              std::int32_t& error) {
    if (dim == 0 || dim > 128 || expected.size() < dim ||
        residual.size() < dim || codebook.size() < (code + 1) * dim)
        return fail("leaf verify bounds invalid");
    for (std::size_t i = 0; i < dim; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(expected[i])) ||
            !write_word(0x30000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(residual[i])))
            return fail("cannot write leaf verify vectors");
    }
    for (std::size_t i = 0; i < codebook.size(); ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(codebook[i])))
            return fail("cannot write leaf verify codebook");
    if (!write_word(kProposalBase + 0, code) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kProposalBase + 2, tolerance) ||
        !write_word(kCommandBase, 72)) return fail("cannot write leaf verify command");
    if (!run_command()) return false;
    accepted = (read_word(kResultBase + 0) & 1u) != 0;
    error = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}


bool RawFieldVM::raw_hash(const std::vector<std::int32_t>& payload,
                          std::uint32_t& digest) {
    if (payload.empty() || payload.size() > 65535)
        return fail("checkpoint hash payload outside 1..65535 words");
    for (std::size_t i = 0; i < payload.size(); ++i)
        if (!write_word(0x350000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(payload[i])))
            return fail("cannot write checkpoint hash payload");
    if (!write_word(kProposalBase + 0, 0x350000u) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(payload.size())) ||
        !write_word(kCommandBase, 73))
        return fail("cannot write checkpoint hash command");
    if (!run_command()) return false;
    digest = read_word(kResultBase);
    return true;
}

bool RawFieldVM::tokenize(const std::string& text, std::size_t max_words,
                          std::vector<std::uint32_t>& words,
                          std::vector<std::uint32_t>& subwords,
                          std::vector<std::uint32_t>& meta,
                          std::size_t& word_count, std::size_t& subword_count) {
    if (text.empty() || text.size() > 0xFF00 || max_words == 0 ||
        max_words > 4096) return fail("tokenizer bounds invalid");
    for (std::size_t i = 0; i < text.size(); ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint8_t>(text[i])))
            return fail("cannot write tokenizer text");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(text.size())) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(max_words)) ||
        !write_word(kCommandBase, 74))
        return fail("cannot write tokenizer command");
    if (!run_command()) return false;
    word_count = read_word(kResultBase + 0);
    subword_count = read_word(kResultBase + 1);
    if (word_count > max_words || subword_count > max_words * 8)
        return fail("tokenizer returned invalid counts");
    words.resize(word_count);
    for (std::size_t i = 0; i < words.size(); ++i)
        words[i] = read_word(0x20000u + static_cast<std::uint32_t>(i));
    subwords.resize(subword_count);
    for (std::size_t i = 0; i < subwords.size(); ++i)
        subwords[i] = read_word(0x30000u + static_cast<std::uint32_t>(i));
    meta.resize(word_count * 4);
    for (std::size_t i = 0; i < meta.size(); ++i)
        meta[i] = read_word(0x40000u + static_cast<std::uint32_t>(i));
    return true;
}

bool RawFieldVM::meta_trihead_reset() {
    if (!write_word(kCommandBase, 75)) return fail("cannot write meta reset");
    return run_command();
}

bool RawFieldVM::meta_trihead_observe_batch(
    const std::vector<std::uint32_t>& words, std::size_t& contexts) {
    if (words.empty() || words.size() > 4096)
        return fail("meta observe bounds invalid");
    for (std::size_t i = 0; i < words.size(); ++i)
        if (!write_word(0x20000u + static_cast<std::uint32_t>(i), words[i]))
            return fail("cannot write meta words");
    if (!write_word(kProposalBase + 0,
                    static_cast<std::uint32_t>(words.size())) ||
        !write_word(kCommandBase, 76))
        return fail("cannot write meta observe command");
    if (!run_command()) return false;
    contexts = read_word(kResultBase + 0);
    return contexts == words.size();
}

bool RawFieldVM::read_meta_trihead(std::vector<std::int32_t>& votes,
                                   std::vector<std::int32_t>& credits) {
    votes.resize(85);
    credits.resize(255);
    for (std::size_t i = 0; i < votes.size(); ++i)
        votes[i] = static_cast<std::int32_t>(
            read_word(0x220000u + static_cast<std::uint32_t>(i)));
    for (std::size_t i = 0; i < credits.size(); ++i)
        credits[i] = static_cast<std::int32_t>(
            read_word(0x220100u + static_cast<std::uint32_t>(i)));
    return true;
}

bool RawFieldVM::temporal_slots_reset() {
    if (!write_word(kCommandBase, 77)) return fail("cannot write temporal reset");
    return run_command();
}

bool RawFieldVM::temporal_slots_observe_batch(
    const std::vector<std::uint32_t>& words, std::size_t& contexts) {
    if (words.empty() || words.size() > 4096)
        return fail("temporal observe bounds invalid");
    for (std::size_t i = 0; i < words.size(); ++i)
        if (!write_word(0x20000u + static_cast<std::uint32_t>(i), words[i]))
            return fail("cannot write temporal words");
    if (!write_word(kProposalBase + 0,
                    static_cast<std::uint32_t>(words.size())) ||
        !write_word(kCommandBase, 78))
        return fail("cannot write temporal observe");
    if (!run_command()) return false;
    contexts = read_word(kResultBase + 0);
    return contexts == words.size();
}

bool RawFieldVM::temporal_slots_project() {
    if (!write_word(kCommandBase, 79)) return fail("cannot write temporal project");
    return run_command();
}

bool RawFieldVM::read_temporal_slots(
    std::size_t count, std::vector<std::int32_t>& past_votes,
    std::vector<std::int32_t>& past_credits,
    std::vector<std::int32_t>& future_votes,
    std::vector<std::int32_t>& future_credits,
    std::vector<std::uint32_t>& current_words,
    std::array<std::int32_t, 4>& head255,
    std::vector<std::int32_t>& slots) {
    if (count == 0 || count > 4096) return fail("temporal read bounds");
    past_votes.resize(85); past_credits.resize(255);
    future_votes.resize(85); future_credits.resize(255);
    current_words.resize(count); slots.resize(count * 3);
    for (std::size_t i = 0; i < 85; ++i) {
        past_votes[i] = static_cast<std::int32_t>(read_word(0x230000u + i));
        future_votes[i] = static_cast<std::int32_t>(read_word(0x231000u + i));
    }
    for (std::size_t i = 0; i < 255; ++i) {
        past_credits[i] = static_cast<std::int32_t>(read_word(0x230100u + i));
        future_credits[i] = static_cast<std::int32_t>(read_word(0x231100u + i));
    }
    for (std::size_t i = 0; i < count; ++i) {
        current_words[i] = read_word(0x232000u + static_cast<std::uint32_t>(i));
        slots[i * 3 + 0] = static_cast<std::int32_t>(read_word(
            0x234000u + static_cast<std::uint32_t>(i * 3)));
        slots[i * 3 + 1] = static_cast<std::int32_t>(read_word(
            0x234001u + static_cast<std::uint32_t>(i * 3)));
        slots[i * 3 + 2] = static_cast<std::int32_t>(read_word(
            0x234002u + static_cast<std::uint32_t>(i * 3)));
    }
    for (std::size_t i = 0; i < 4; ++i)
        head255[i] = static_cast<std::int32_t>(read_word(0x233000u + i));
    return true;
}

bool RawFieldVM::ngram_reset() {
    if (!write_word(kCommandBase, 80)) return fail("cannot write ngram reset");
    return run_command();
}

bool RawFieldVM::ngram_train(const std::string& bytes, std::size_t& processed,
                              std::size_t skip) {
    if (bytes.empty() || bytes.size() > 0x10000 || skip > bytes.size())
        return fail("ngram train chunk 1..65536 bytes");
    for (std::size_t i = 0; i < bytes.size(); ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint8_t>(bytes[i])))
            return fail("cannot write ngram bytes");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(bytes.size())) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(skip)) ||
        !write_word(kCommandBase, 81))
        return fail("cannot write ngram train");
    if (!run_command()) return false;
    processed = read_word(kResultBase + 0);
    return processed == bytes.size();
}

bool RawFieldVM::ngram_topk(
    std::array<std::vector<std::uint32_t>, 4>& keys,
    std::array<std::vector<std::uint32_t>, 4>& counts) {
    if (!write_word(kCommandBase, 82)) return fail("cannot write ngram topk");
    if (!run_command()) return false;
    for (std::size_t order = 0; order < 4; ++order) {
        keys[order].resize(64);
        counts[order].resize(64);
        for (std::size_t i = 0; i < 64; ++i) {
            keys[order][i] = read_word(0x2D0000u +
                static_cast<std::uint32_t>(order * 0x100 + i));
            counts[order][i] = read_word(0x2D1000u +
                static_cast<std::uint32_t>(order * 0x100 + i));
        }
    }
    return true;
}

bool RawFieldVM::phase_table_init() {
    if (!write_word(kCommandBase, 64)) return fail("cannot write phase table init");
    if (!run_command()) return false;
    phase_table_ready_ = true;
    return true;
}

bool RawFieldVM::phase_encode_batch(const std::uint8_t* bytes,
                                    std::size_t windows, std::size_t window,
                                    std::size_t dim,
                                    std::vector<std::int32_t>& out) {
    if (!bytes || windows == 0 || windows > 1024 || window == 0 ||
        window > 8 || dim == 0 || dim > 128) {
        return fail("phase batch requires 1..1024 windows, W<=8, D<=128");
    }
    if (!phase_table_ready_ && !phase_table_init()) return false;
    for (std::size_t i = 0; i < windows * window; ++i) {
        if (!write_word(0x60000u + static_cast<std::uint32_t>(i), bytes[i])) {
            return fail("cannot write phase batch input");
        }
    }
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(windows)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(window)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 63)) {
        return fail("cannot write phase batch command");
    }
    if (!run_command()) return false;
    out.resize(windows * dim * 2);
    for (std::size_t i = 0; i < out.size(); ++i) {
        out[i] = static_cast<std::int32_t>(
            read_word(0x70000u + static_cast<std::uint32_t>(i)));
    }
    return true;
}


bool RawFieldVM::vector_matrix_reset() {
    if (!write_word(kCommandBase, 65)) return fail("cannot write vector matrix reset");
    return run_command();
}

bool RawFieldVM::vector_matrix_accumulate(std::uint8_t a, std::uint8_t b,
                                          std::int32_t delta,
                                          std::uint32_t& index,
                                          std::int32_t& value) {
    if (!write_word(kProposalBase + 0, a) ||
        !write_word(kProposalBase + 1, b) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(delta)) ||
        !write_word(kCommandBase, 66))
        return fail("cannot write vector matrix accumulate");
    if (!run_command()) return false;
    index = read_word(kResultBase + 0);
    value = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}

bool RawFieldVM::vector_matrix_probe(std::uint8_t a, std::int32_t threshold,
                                     std::int32_t& best_head,
                                     std::int32_t& score) {
    if (!write_word(kProposalBase + 0, a) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(threshold)) ||
        !write_word(kCommandBase, 67))
        return fail("cannot write vector matrix probe");
    if (!run_command()) return false;
    best_head = static_cast<std::int32_t>(read_word(kResultBase + 0));
    score = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}

bool RawFieldVM::read_vector_matrix(std::vector<std::int32_t>& cells) {
    cells.resize(32640);
    for (std::size_t i = 0; i < cells.size(); ++i)
        cells[i] = static_cast<std::int32_t>(read_word(0x300000u + static_cast<std::uint32_t>(i)));
    return true;
}


bool RawFieldVM::vector_matrix_credits(std::vector<std::int32_t>& credits) {
    if (!write_word(kCommandBase, 68))
        return fail("cannot write vector matrix credits");
    if (!run_command()) return false;
    credits.resize(255);
    for (std::size_t i = 0; i < credits.size(); ++i)
        credits[i] = static_cast<std::int32_t>(
            read_word(0x7000u + static_cast<std::uint32_t>(i)));
    return true;
}


bool RawFieldVM::load_vector_matrix(const std::vector<std::int32_t>& cells) {
    if (cells.size() != 32640) return fail("vector matrix needs 32640 cells");
    for (std::size_t i = 0; i < cells.size(); ++i)
        if (!write_word(0x300000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(cells[i])))
            return fail("cannot load vector matrix");
    return true;
}

bool RawFieldVM::reset_context_readout(std::size_t buckets) {
    if (buckets == 0 || buckets > 16384) {
        return fail("context bucket count outside 1..16384");
    }
    const std::size_t words = 16 * buckets + 16 * 16 * buckets;
    for (std::size_t i = 0; i < words; ++i) {
        if (!write_word(0x100000u + static_cast<std::uint32_t>(i), 0)) {
            return fail("cannot reset context readout");
        }
    }
    return true;
}


bool RawFieldVM::load_context_readout(const std::string& path,
                                      std::size_t buckets) {
    const std::size_t words = 272 * buckets;
    std::ifstream in(path, std::ios::binary);
    if (!in) return fail("cannot open context checkpoint: " + path);
    in.seekg(0, std::ios::end);
    const std::streamoff bytes = in.tellg();
    if (bytes < 0 || static_cast<std::size_t>(bytes) != words * 4) {
        return fail("context checkpoint size mismatch");
    }
    in.seekg(0, std::ios::beg);
    std::array<std::uint8_t, 4> raw{};
    for (std::size_t i = 0; i < words; ++i) {
        if (!in.read(reinterpret_cast<char*>(raw.data()), raw.size())) {
            return fail("cannot read context checkpoint");
        }
        const std::uint32_t bits = static_cast<std::uint32_t>(raw[0]) |
            (static_cast<std::uint32_t>(raw[1]) << 8) |
            (static_cast<std::uint32_t>(raw[2]) << 16) |
            (static_cast<std::uint32_t>(raw[3]) << 24);
        if (!write_word(0x100000u + static_cast<std::uint32_t>(i), bits)) {
            return fail("cannot write context checkpoint");
        }
    }
    return true;
}

bool RawFieldVM::save_context_readout(const std::string& path,
                                      std::size_t buckets) {
    const std::size_t words = 272 * buckets;
    std::ofstream out(path, std::ios::binary);
    if (!out) return fail("cannot create context checkpoint: " + path);
    for (std::size_t i = 0; i < words; ++i) {
        const std::uint32_t bits = read_word(0x100000u + static_cast<std::uint32_t>(i));
        const std::array<std::uint8_t, 4> raw = {
            static_cast<std::uint8_t>(bits & 0xFFu),
            static_cast<std::uint8_t>((bits >> 8) & 0xFFu),
            static_cast<std::uint8_t>((bits >> 16) & 0xFFu),
            static_cast<std::uint8_t>((bits >> 24) & 0xFFu)};
        out.write(reinterpret_cast<const char*>(raw.data()), raw.size());
    }
    return static_cast<bool>(out);
}

bool RawFieldVM::readout_context(std::uint8_t target, float learning_rate,
                                 std::uint32_t bucket, std::size_t buckets,
                                 bool& correct, float& loss,
                                 std::uint8_t& predicted_high,
                                 std::uint8_t& predicted_low) {
    if (buckets == 0 || buckets > 16384 || bucket >= buckets) {
        return fail("invalid context readout bucket");
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kProposalBase + 2, bucket) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(buckets)) ||
        !write_word(kCommandBase, 25)) {
        return fail("cannot write context readout command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ls = read_word(kResultBase + 1);
    std::memcpy(&loss, &ls, sizeof(ls));
    predicted_high = static_cast<std::uint8_t>(read_word(kResultBase + 2) & 15u);
    predicted_low = static_cast<std::uint8_t>(read_word(kResultBase + 3) & 15u);
    return true;
}

bool RawFieldVM::reset_context_backoff() {
    for (std::uint32_t i = 0; i < kContextBackoffTableWords; ++i) {
        if (!write_word(kContextBackoffTable + i, 0)) {
            return fail("cannot reset context backoff table");
        }
    }
    for (std::uint32_t i = 0; i < kContextBackoffHistWords; ++i) {
        if (!write_word(kContextBackoffHist + i, 0)) {
            return fail("cannot reset context backoff histogram");
        }
    }
    if (!write_word(kProposalBase + 0, 5) ||
        !write_word(kCommandBase, kContextBackoffCommand)) {
        return fail("cannot reset context backoff state");
    }
    return run_command();
}

bool RawFieldVM::context_backoff_build(std::uint32_t key,
                                       bool* inserted) {
    if (!write_word(kProposalBase + 0, 1) ||
        !write_word(kProposalBase + 1, key) ||
        !write_word(kCommandBase, kContextBackoffCommand)) {
        return fail("cannot write context backoff build command");
    }
    if (!run_command()) return false;
    if (inserted) *inserted = (read_word(kResultBase + 0) & 1u) != 0;
    return true;
}

bool RawFieldVM::context_backoff_build_batch(const std::uint32_t* keys,
                                             std::size_t count,
                                             std::size_t& inserted) {
    constexpr std::uint32_t kKeyBuffer = 0x60000;
    constexpr std::size_t kChunk = 4096;
    inserted = 0;
    if (!keys && count) return fail("context backoff keys are null");
    for (std::size_t base = 0; base < count; base += kChunk) {
        const std::size_t n = std::min(kChunk, count - base);
        for (std::size_t i = 0; i < n; ++i) {
            if (!write_word(kKeyBuffer + static_cast<std::uint32_t>(i), keys[base + i])) {
                return fail("cannot write context backoff key batch");
            }
        }
        if (!write_word(kProposalBase + 0, 4) ||
            !write_word(kProposalBase + 1, static_cast<std::uint32_t>(n)) ||
            !write_word(kProposalBase + 2, kKeyBuffer) ||
            !write_word(kCommandBase, kContextBackoffCommand)) {
            return fail("cannot write context backoff batch command");
        }
        if (!run_command()) return false;
        inserted += read_word(kResultBase + 0);
    }
    return true;
}

bool RawFieldVM::context_backoff_select(std::size_t buckets,
                                        std::size_t exact_limit,
                                        ContextBackoffSelection& out) {
    if (buckets < 2 || buckets > 16384 ||
        exact_limit > 16384) {
        return fail("context backoff buckets 2..16384, exact limit <= 16384");
    }
    if (!write_word(kProposalBase + 0, 2) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(buckets)) ||
        !write_word(kProposalBase + 2,
                    static_cast<std::uint32_t>(exact_limit)) ||
        !write_word(kCommandBase, kContextBackoffCommand)) {
        return fail("cannot write context backoff select command");
    }
    if (!run_command()) return false;
    out.exact_count = read_word(kResultBase + 0);
    out.fallback = read_word(kResultBase + 1);
    out.threshold = read_word(kResultBase + 2);
    out.unique = read_word(kResultBase + 3);
    return true;
}

bool RawFieldVM::readout_context_backoff(std::uint8_t target,
                                         float learning_rate,
                                         std::uint32_t key,
                                         std::size_t buckets,
                                         ContextBackoffStep& out) {
    if (buckets < 2 || buckets > 16384) {
        return fail("context backoff buckets outside 2..16384");
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, 3) ||
        !write_word(kProposalBase + 1, target) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kProposalBase + 3, key) ||
        !write_word(kProposalBase + 4, static_cast<std::uint32_t>(buckets)) ||
        !write_word(kCommandBase, kContextBackoffCommand)) {
        return fail("cannot write context backoff step command");
    }
    if (!run_command()) return false;
    out.correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t loss_bits = read_word(kResultBase + 1);
    std::memcpy(&out.loss, &loss_bits, sizeof(loss_bits));
    out.predicted_high = static_cast<std::uint8_t>(read_word(kResultBase + 2) & 15u);
    out.predicted_low = static_cast<std::uint8_t>(read_word(kResultBase + 3) & 15u);
    out.exact = (read_word(kResultBase + 4) & 1u) != 0;
    out.bucket = read_word(kResultBase + 5);
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


bool RawFieldVM::causal_trunk_wide_cached(const std::vector<float>& tokens,
                                          std::size_t count, std::size_t dim,
                                          std::vector<float>& out) {
    if (count == 0 || count > 1024 || dim == 0 || dim > 128 ||
        tokens.size() != count * dim) {
        return fail("wide cached trunk dimensions are invalid");
    }
    for (std::size_t i = 0; i < tokens.size(); ++i) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &tokens[i], sizeof(bits));
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i), bits)) {
            return fail("cannot write cached wide tokens");
        }
    }
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(4 * dim)) ||
        !write_word(kCommandBase, 13)) {
        return fail("cannot write cached wide command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != dim) {
        return fail("cached wide trunk returned the wrong feature count");
    }
    out.assign(dim, 0.0f);
    for (std::size_t i = 0; i < dim; ++i) {
        const std::uint32_t bits = read_word(0x200000u + static_cast<std::uint32_t>(i));
        std::memcpy(&out[i], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::set_wide_readout_row(std::uint8_t row, const float* values,
                                      std::size_t dim) {
    if (row >= 255 || dim == 0 || dim > 128) return fail("wide readout row invalid");
    for (std::size_t i = 0; i < dim; ++i) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &values[i], sizeof(bits));
        if (!write_word(0x180000u + static_cast<std::uint32_t>(row * dim + i),
                        bits)) return fail("cannot write wide readout row");
    }
    return true;
}

bool RawFieldVM::qkv_credit_wide(std::uint8_t target, std::uint8_t best_wrong,
                                 float learning_rate) {
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kCommandBase, 18)) {
        return fail("cannot write wide QKV-credit command");
    }
    if (!run_command()) return false;
    if ((read_word(kResultBase) & 1u) == 0) {
        return fail("raw wide QKV credit did not complete");
    }
    return true;
}


bool RawFieldVM::trunk_credit_wide(std::uint8_t target,
                                   std::uint8_t best_wrong,
                                   float learning_rate) {
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kCommandBase, 20)) {
        return fail("cannot write wide trunk-credit command");
    }
    if (!run_command()) return false;
    if ((read_word(kResultBase) & 1u) == 0) {
        return fail("raw wide trunk credit did not complete");
    }
    return true;
}



bool RawFieldVM::combine_credits(const std::array<std::int32_t, 7>& credits,
                                 const std::array<std::int32_t, 7>& coefficients,
                                 std::int32_t& combined) {
    for (std::size_t i = 0; i < 7; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i])) ||
            !write_word(0x7100u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(coefficients[i]))) {
            return fail("cannot write credit-combine args");
        }
    }
    if (!write_word(kCommandBase, 25)) {
        return fail("cannot write credit-combine command");
    }
    if (!run_command()) return false;
    combined = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}



bool RawFieldVM::credit_bundle(const CreditBundleState& state,
                               std::array<std::int32_t, 7>& credits) {
    auto w = [&](std::uint32_t index, std::int32_t value) {
        return write_word(index, static_cast<std::uint32_t>(value));
    };
    for (std::size_t i = 0; i < state.cft.size(); ++i)
        if (!w(0x8000u + i, state.cft[i])) return fail("cannot write CFT bundle");
    for (std::size_t i = 0; i < state.trail.size(); ++i)
        if (!w(0x8010u + i, state.trail[i])) return fail("cannot write TRAIL bundle");
    for (std::size_t i = 0; i < state.holo.size(); ++i)
        if (!w(0x8020u + i, state.holo[i])) return fail("cannot write HOLO bundle");
    if (!w(0x8030u, state.ring_shift)) return fail("cannot write RING shift");
    for (std::size_t i = 0; i < state.ring_phases.size(); ++i)
        if (!write_word(0x7500u + static_cast<std::uint32_t>(i),
                        state.ring_phases[i])) return fail("cannot write RING phases");
    for (std::size_t i = 0; i < state.leaf.size(); ++i)
        if (!w(0x8040u + i, state.leaf[i])) return fail("cannot write LEAF bundle");
    for (std::size_t i = 0; i < state.tca.size(); ++i)
        if (!w(0x8050u + i, state.tca[i])) return fail("cannot write TCA bundle");
    for (std::size_t i = 0; i < state.flux.size(); ++i)
        if (!w(0x8060u + i, state.flux[i])) return fail("cannot write FLUX bundle");
    if (!write_word(kCommandBase, 29)) return fail("cannot write credit-bundle command");
    if (!run_command()) return false;
    for (std::size_t i = 0; i < credits.size(); ++i) {
        credits[i] = static_cast<std::int32_t>(read_word(0x7200u +
                                                        static_cast<std::uint32_t>(i)));
    }
    return true;
}

bool RawFieldVM::credit_ablation(
    const CreditBundleState& state,
    const std::array<std::int32_t, 7>& base_coefficients,
    std::array<std::int32_t, 8>& combined) {
    std::array<std::int32_t, 7> credits{};
    if (!credit_bundle(state, credits)) return false;
    std::int32_t value = 0;
    if (!combine_credits(credits, base_coefficients, value)) return false;
    combined[0] = value;
    for (std::size_t ablate = 0; ablate < 7; ++ablate) {
        std::array<std::int32_t, 7> coefficients = base_coefficients;
        coefficients[ablate] = 0;
        if (!combine_credits(credits, coefficients, value)) return false;
        combined[ablate + 1] = value;
    }
    return true;
}

bool RawFieldVM::combined_trunk_credit(
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t threshold_q16,
    const std::array<std::int32_t, 7>& credits,
    const std::array<std::int32_t, 7>& coefficients, bool& applied) {
    for (std::size_t i = 0; i < 7; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i])) ||
            !write_word(0x7100u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(coefficients[i]))) {
            return fail("cannot write combined-credit args");
        }
    }
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(base_lr_q16)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(threshold_q16)) ||
        !write_word(kCommandBase, 26)) {
        return fail("cannot write combined-credit command");
    }
    if (!run_command()) return false;
    applied = (read_word(kResultBase) & 1u) != 0;
    return true;
}


bool RawFieldVM::combined_trunk_credit_all(
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t threshold_q16,
    const std::array<std::int32_t, 7>& credits,
    const std::array<std::int32_t, 7>& coefficients, bool& applied) {
    for (std::size_t i = 0; i < 7; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i])) ||
            !write_word(0x7100u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(coefficients[i]))) {
            return fail("cannot write combined-all args");
        }
    }
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(base_lr_q16)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(threshold_q16)) ||
        !write_word(kCommandBase, 27)) {
        return fail("cannot write combined-all command");
    }
    if (!run_command()) return false;
    applied = (read_word(kResultBase) & 1u) != 0;
    return true;
}

bool RawFieldVM::write_wide_weights(const WideTrunkWeights& weights) {
    const std::size_t d = weights.dim;
    const std::size_t h = weights.hidden;
    if (d == 0 || d > 128 || h == 0 || h > 512) return false;
    const std::uint32_t bases[6] = {
        0x60000u,
        0x60000u + static_cast<std::uint32_t>(d * d),
        0x60000u + static_cast<std::uint32_t>(2 * d * d),
        0x60000u + static_cast<std::uint32_t>(3 * d * d),
        0x60000u + static_cast<std::uint32_t>(4 * d * d),
        0x60000u + static_cast<std::uint32_t>(4 * d * d + h * d)};
    const std::vector<float>* blocks[6] = {
        &weights.wq, &weights.wk, &weights.wv,
        &weights.wout, &weights.w1, &weights.w2};
    for (std::size_t b = 0; b < 6; ++b) {
        for (std::size_t i = 0; i < blocks[b]->size(); ++i) {
            std::uint32_t bits = 0;
            std::memcpy(&bits, &(*blocks[b])[i], sizeof(bits));
            if (!write_word(bases[b] + static_cast<std::uint32_t>(i), bits)) {
                return fail("cannot write wide weights");
            }
        }
    }
    return true;
}

bool RawFieldVM::combined_trunk_credit_wide(
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t threshold_q16,
    const std::array<std::int32_t, 7>& credits,
    const std::array<std::int32_t, 7>& coefficients, bool& applied) {
    for (std::size_t i = 0; i < 7; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i])) ||
            !write_word(0x7100u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(coefficients[i]))) {
            return fail("cannot write combined-wide args");
        }
    }
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(base_lr_q16)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(threshold_q16)) ||
        !write_word(kCommandBase, 28)) {
        return fail("cannot write combined-wide command");
    }
    if (!run_command()) return false;
    applied = (read_word(kResultBase) & 1u) != 0;
    return true;
}

bool RawFieldVM::commit_combined_credit(
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t threshold_q16,
    const std::array<std::int32_t, 7>& credits,
    const std::array<std::int32_t, 7>& coefficients,
    const std::array<std::int32_t, kTriadMemberCount>& head_credits,
    std::int32_t head_threshold_q16,
    bool& field_accepted, bool& committed) {
    TrunkWeights snapshot{};
    if (!read_trunk_weights(snapshot)) return fail("cannot snapshot trunk");
    std::array<std::uint8_t, kTriadCount> votes{};
    std::uint16_t accepted = 0;
    if (!credit_field_vote(head_credits, head_threshold_q16, votes,
                           accepted, field_accepted)) return false;
    committed = false;
    if (!field_accepted) return true;
    bool applied = false;
    if (!combined_trunk_credit_all(target, best_wrong, base_lr_q16,
                                   threshold_q16, credits, coefficients,
                                   applied)) {
        (void)write_trunk_weights(snapshot);
        return false;
    }
    if (!applied) {
        (void)write_trunk_weights(snapshot);
        return true;
    }
    committed = true;
    return true;
}


bool RawFieldVM::commit_combined_credit_wide(
    std::size_t dim, std::size_t hidden,
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t threshold_q16,
    const std::array<std::int32_t, 7>& credits,
    const std::array<std::int32_t, 7>& coefficients,
    const std::array<std::int32_t, kTriadMemberCount>& head_credits,
    std::int32_t head_threshold_q16,
    bool& field_accepted, bool& committed) {
    WideTrunkWeights snapshot{};
    if (!read_wide_weights(dim, hidden, snapshot)) return fail("cannot snapshot wide trunk");
    std::array<std::uint8_t, kTriadCount> votes{};
    std::uint16_t accepted = 0;
    if (!credit_field_vote(head_credits, head_threshold_q16, votes,
                           accepted, field_accepted)) return false;
    committed = false;
    if (!field_accepted) return true;
    bool applied = false;
    if (!combined_trunk_credit_wide(target, best_wrong, base_lr_q16,
                                    threshold_q16, credits, coefficients,
                                    applied)) {
        (void)write_wide_weights(snapshot);
        return false;
    }
    if (!applied) {
        (void)write_wide_weights(snapshot);
        return true;
    }
    committed = true;
    return true;
}

bool RawFieldVM::cft_trunk_credit(std::uint8_t target, std::uint8_t best_wrong,
                                  std::int32_t base_lr_q16,
                                  std::int32_t threshold_q16,
                                  std::int32_t e_ab, std::int32_t e_bc,
                                  std::int32_t e_ca, std::int32_t error,
                                  std::int32_t rate, bool& applied) {
    const std::uint32_t args[9] = {
        target, best_wrong, static_cast<std::uint32_t>(base_lr_q16),
        static_cast<std::uint32_t>(threshold_q16), static_cast<std::uint32_t>(e_ab),
        static_cast<std::uint32_t>(e_bc), static_cast<std::uint32_t>(e_ca),
        static_cast<std::uint32_t>(error), static_cast<std::uint32_t>(rate)};
    for (std::size_t i = 0; i < 9; ++i) {
        if (!write_word(kProposalBase + static_cast<std::uint32_t>(i), args[i])) {
            return fail("cannot write CFT trunk-credit args");
        }
    }
    if (!write_word(kCommandBase, 22)) {
        return fail("cannot write CFT trunk-credit command");
    }
    if (!run_command()) return false;
    applied = (read_word(kResultBase) & 1u) != 0;
    return true;
}


bool RawFieldVM::credit_field_vote(
    const std::array<std::int32_t, kTriadMemberCount>& credits,
    std::int32_t threshold,
    std::array<std::uint8_t, kTriadCount>& votes,
    std::uint16_t& accepted_count, bool& field_accepted) {
    for (std::size_t i = 0; i < credits.size(); ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i]))) {
            return fail("cannot write credit-field credits");
        }
    }
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(threshold)) ||
        !write_word(kCommandBase, 24)) {
        return fail("cannot write credit-field command");
    }
    if (!run_command()) return false;
    accepted_count = static_cast<std::uint16_t>(read_word(kResultBase + 0));
    field_accepted = (read_word(kResultBase + 1) & 1u) != 0;
    for (std::size_t i = 0; i < votes.size(); ++i) {
        votes[i] = static_cast<std::uint8_t>(read_word(0x7100u +
                                                      static_cast<std::uint32_t>(i)) & 1u);
    }
    return true;
}


bool RawFieldVM::write_trunk_weights(const TrunkWeights& weights) {
    auto write_block = [&](std::uint32_t base, const float* data,
                           std::size_t count) {
        for (std::size_t i = 0; i < count; ++i) {
            std::uint32_t bits = 0;
            std::memcpy(&bits, &data[i], sizeof(bits));
            if (!write_word(base + static_cast<std::uint32_t>(i), bits)) {
                return false;
            }
        }
        return true;
    };
    return write_block(0x9000, weights.wq.data(), weights.wq.size()) &&
           write_block(0x9040, weights.wk.data(), weights.wk.size()) &&
           write_block(0x9080, weights.wv.data(), weights.wv.size()) &&
           write_block(0x90C0, weights.wout.data(), weights.wout.size()) &&
           write_block(0x9100, weights.w1.data(), weights.w1.size()) &&
           write_block(0x9180, weights.w2.data(), weights.w2.size());
}

bool RawFieldVM::commit_cft_credit(
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t cft_threshold_q16,
    std::int32_t e_ab, std::int32_t e_bc, std::int32_t e_ca,
    std::int32_t error, std::int32_t rate,
    const std::array<std::int32_t, kTriadMemberCount>& head_credits,
    std::int32_t head_threshold_q16,
    bool& field_accepted, bool& committed) {
    TrunkWeights snapshot{};
    if (!read_trunk_weights(snapshot)) return fail("cannot snapshot trunk weights");
    std::array<std::uint8_t, kTriadCount> votes{};
    std::uint16_t accepted = 0;
    if (!credit_field_vote(head_credits, head_threshold_q16, votes,
                           accepted, field_accepted)) {
        return false;
    }
    committed = false;
    if (!field_accepted) return true;
    bool applied = false;
    if (!cft_trunk_credit(target, best_wrong, base_lr_q16, cft_threshold_q16,
                          e_ab, e_bc, e_ca, error, rate, applied)) {
        (void)write_trunk_weights(snapshot);
        return false;
    }
    if (!applied) {
        (void)write_trunk_weights(snapshot);
        return true;
    }
    committed = true;
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
