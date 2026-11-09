#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <cstring>
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
constexpr std::uint32_t kMaxSteps = 5'000'000;
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
    auto bump = [](std::int16_t& value, int delta) {
        const int next = static_cast<int>(value) + delta;
        value = static_cast<std::int16_t>(std::max(-32768, std::min(32767, next)));
    };
    bump(universe.head_credit()[proposer], out.accepted ? 1 : -1);
    bump(universe.triad_credit()[triad], out.accepted ? 1 : -1);
    if (!field_vote(universe)) return false;
    if (!coherence(universe)) return false;
    return true;
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
