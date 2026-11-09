// Host-side orchestration for the raw NaN16 field driver.
//
// The Boolean, triad, field, trig and remap mathematics runs in
// mth/drivers/field_driver.nas on the canonical NaN0S VM. This class only
// writes command words, runs the guest, and reads result words. It does not
// substitute host arithmetic for a kernel.
#pragma once

#include "nanlm/head.hpp"
#include "nanlm/universe.hpp"
#include "nan16.h"

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace nanlm {

struct AutoRemapResult {
    bool attempted = false;
    bool improved = false;
    std::uint8_t triad_a = 0;
    std::uint8_t slot_a = 0;
    std::uint8_t triad_b = 0;
    std::uint8_t slot_b = 0;
    std::int32_t before = 0;
    std::int32_t after = 0;
};

struct RawProposalResult {
    std::uint8_t votes = 0;
    bool accepted = false;
    std::uint16_t candidate_mask = 0;
    std::uint8_t candidate_rule = 0;
};

constexpr std::size_t kRawFeatureDim = 8;
constexpr std::size_t kRawTrunkContext = 256;

struct TrunkWeights {
    std::array<float, 64> wq{};
    std::array<float, 64> wk{};
    std::array<float, 64> wv{};
    std::array<float, 64> wout{};
    std::array<float, 128> w1{};
    std::array<float, 128> w2{};
};

struct HotTriheadResult {
    std::uint16_t hot_heads = 0;
    std::uint16_t hot_triads = 0;
    bool field_hot = false;
    bool mapped = false;
    std::array<std::uint8_t, kTriadMemberCount> members{};
};

class RawFieldVM {
public:
    explicit RawFieldVM(const std::string& driver_image);
    ~RawFieldVM();
    RawFieldVM(const RawFieldVM&) = delete;
    RawFieldVM& operator=(const RawFieldVM&) = delete;

    bool ready() const { return vm_ != nullptr; }
    const std::string& error() const { return error_; }

    bool proposal(std::uint16_t current_mask, std::uint16_t patch,
                  const std::array<std::uint16_t, 3>& members,
                  std::uint32_t a, std::uint32_t b, bool target,
                  RawProposalResult& out);
    // Chart bridge: the raw guest decides; only the proposer's mask changes
    // on acceptance, and the chart's integer credit fields are updated here.
    bool propose(Universe& universe, HeadArray& heads, std::uint8_t proposer,
                 std::uint16_t patch, std::uint32_t a, std::uint32_t b,
                 bool target, RawProposalResult& out);
    bool field_vote(const std::array<std::uint8_t, kTriadCount>& masks,
                    std::uint16_t& accepted_count, bool& field_accepted);
    bool coherence(const std::array<std::uint16_t, kTriadMemberCount>& phases,
                   std::int32_t& q16);
    bool cft(std::int32_t e_ab, std::int32_t e_bc, std::int32_t e_ca,
             std::int32_t error, std::int32_t rate,
             std::array<std::int32_t, 4>& out);
    bool trail(std::int32_t reward, std::int32_t v_minus_next,
               std::int32_t v_plus, std::int32_t v_plus_prev,
               std::int32_t v_minus, std::int32_t e_plus,
               std::int32_t e_minus, std::int32_t grad_plus,
               std::int32_t grad_minus, std::int32_t gamma,
               std::int32_t lambda, std::array<std::int32_t, 3>& out);
    bool field_commit(const std::array<std::int32_t, kTriadCount>& credits,
                      std::int32_t threshold,
                      std::array<std::uint8_t, kTriadCount>& votes,
                      std::uint16_t& accepted_count, bool& committed);
    bool hot_triheads(const std::array<std::int32_t, kTriadMemberCount>& credits,
                      std::int32_t threshold, HotTriheadResult& out);
    // Raw scan/grouping, then commit the unique 85x3 mapping to the chart.
    bool hot_triheads(Universe& universe,
                      const std::array<std::int32_t, kTriadMemberCount>& credits,
                      std::int32_t threshold, HotTriheadResult& out);
    // Raw two-token identity QKV/softmax/tanh feature feed.
    bool micro_feature(const std::array<float, kRawFeatureDim>& x0,
                       const std::array<float, kRawFeatureDim>& x1,
                       std::array<float, kRawFeatureDim>& out);
    // Learned QKV/MLP causal feature block.  Tokens are 8-lane float32
    // vectors; the guest attends causally to the last token.
    bool causal_trunk(const std::vector<std::array<float, kRawFeatureDim>>& tokens,
                      const TrunkWeights& weights,
                      std::array<float, kRawFeatureDim>& out);
    bool readout_train(
        const std::vector<std::array<float, kRawFeatureDim>>& tokens,
        const TrunkWeights& weights, std::uint8_t target, float learning_rate,
        bool& correct, float& target_score, float& best_wrong_score);
    void reset_readout();
    bool remap(const std::array<std::uint16_t, 6>& masks,
               std::uint32_t a, std::uint32_t b, bool target,
               bool& improved, std::int32_t& before, std::int32_t& after);
    bool remap_general(const std::array<std::uint16_t, 6>& masks,
                       std::uint8_t slot_a, std::uint8_t slot_b,
                       std::uint32_t a, std::uint32_t b, bool target,
                       bool& improved, std::int32_t& before,
                       std::int32_t& after);
    // Chart bridge: trial a general member swap and commit the mapping only
    // when the raw guest says the combined majority objective improves.
    bool remap_chart(Universe& universe, HeadArray& heads,
                     std::uint8_t triad_a, std::uint8_t slot_a,
                     std::uint8_t triad_b, std::uint8_t slot_b,
                     std::uint32_t a, std::uint32_t b, bool target,
                     bool& improved, std::int32_t& before,
                     std::int32_t& after);
    // Deterministic local scheduler: try the two lowest-credit triads, with
    // slots derived from the caller's seed. The raw guest still decides.
    bool auto_remap(Universe& universe, HeadArray& heads, std::uint32_t seed,
                    std::uint32_t a, std::uint32_t b, bool target,
                    AutoRemapResult& out);

    // Convenience bridge: run the guest and update the chart's triad voter.
    bool field_vote(Universe& universe);
    bool coherence(Universe& universe);

private:
    bool write_word(std::uint32_t index, std::uint32_t payload);
    std::uint32_t read_word(std::uint32_t index) const;
    bool run_command();
    bool fail(const std::string& message);

    nan_vm* vm_ = nullptr;
    std::string error_;
};

} // namespace nanlm
