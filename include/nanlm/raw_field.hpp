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
// One guest command can process at most this many context samples inside the
// driver's 200M-step budget (roughly 3-4K guest steps per sample).
constexpr std::size_t kRawContextBatchMax = 8192;

struct WideTrunkWeights {
    std::size_t dim = 0;
    std::size_t hidden = 0;
    std::vector<float> wq;
    std::vector<float> wk;
    std::vector<float> wv;
    std::vector<float> wout;
    std::vector<float> w1;
    std::vector<float> w2;
};

struct CreditBundleState {
    std::array<std::int32_t, 5> cft{};    // Eab,Ebc,Eca,error,rate
    std::array<std::int32_t, 11> trail{};
    std::array<std::int32_t, 3> holo{};   // phases
    std::int32_t ring_shift = 0;
    std::array<std::uint16_t, kTriadMemberCount> ring_phases{};
    std::array<std::int32_t, 3> leaf{};   // row,mask,counter
    std::array<std::int32_t, 3> tca{};    // local,peerA,peerB
    std::array<std::int32_t, 4> flux{};   // phi_u,phi_v,weight,source
};

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

struct ContextBackoffSelection {
    std::uint32_t exact_count = 0;
    std::uint32_t fallback = 0;
    std::uint32_t threshold = 0;
    std::uint32_t unique = 0;
};

struct ContextBackoffStep {
    bool correct = false;
    float loss = 0.0f;
    std::uint8_t predicted_high = 0;
    std::uint8_t predicted_low = 0;
    bool exact = false;
    std::uint32_t bucket = 0;
};


enum class ContextCreditKind : std::uint8_t {
    None = 0,
    Cft = 1,
    Trail = 2,
};

struct ContextClassInput {
    std::uint32_t high_table = 0x100000;
    std::uint32_t low_table = 0;
    std::size_t buckets = 1;
    std::uint32_t bucket = 0;
    bool direct = false;
    std::uint8_t direct_high = 0;
    std::uint8_t direct_low = 0;
    std::int32_t head_threshold = 0;
};

struct ContextCreditInput {
    ContextCreditKind kind = ContextCreditKind::None;
    std::array<std::int32_t, 5> cft{};
    std::array<std::int32_t, 11> trail{};
};

struct ContextClassResult {
    std::uint8_t high = 0;
    std::uint8_t low = 0;
    std::uint8_t head = 0;
    std::uint16_t triad = 0xFFFFu;
    std::uint16_t member = 0xFFFFu;
    bool field_head = false;
    std::uint16_t accepted_triads = 0;
    bool field_accepted = false;
    bool triad_accepted = false;
    std::int32_t head_credit_before = 0;
    std::int32_t head_credit_after = 0;
    std::int32_t credit_delta = 0;
    bool credit_applied = false;
    std::array<std::uint8_t, kTriadCount> votes{};
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
    bool context_encode(
        std::size_t token_count,
        const std::vector<std::uint8_t>& tokens,
        const std::vector<std::uint8_t>& positions,
        const std::vector<std::array<float, kRawFeatureDim>>& word_embeddings,
        const std::array<std::array<float, kRawFeatureDim>, 4>& position_gates,
        const std::array<float, kRawFeatureDim>& bias,
        const std::array<float, kRawFeatureDim>& order,
        float orientation,
        std::array<float, kRawFeatureDim>& out);
    bool role_step(
        std::size_t token_count, const std::vector<std::uint8_t>& tokens,
        const std::vector<std::uint8_t>& positions,
        const std::vector<std::array<float, kRawFeatureDim>>& word_embeddings,
        const std::array<std::array<float, kRawFeatureDim>, 4>& position_gates,
        const std::array<float, kRawFeatureDim>& bias,
        const std::array<float, kRawFeatureDim>& order,
        const std::array<float, kRawFeatureDim>& relation,
        float relation_bias, float label, float learning_rate,
        float orientation, float& probability, float& delta);
    struct SemanticAbility {
        std::uint8_t subject = 0;
        std::uint8_t action = 0;
        std::uint8_t positive = 0;
    };
    bool semantic_query(
        const std::vector<std::pair<std::uint8_t, std::uint8_t>>& isa_edges,
        const std::vector<std::pair<std::uint8_t, std::uint8_t>>& negative_isa,
        const std::vector<SemanticAbility>& abilities,
        std::uint8_t query_type, std::uint8_t subject,
        std::uint8_t object_or_action, std::uint8_t& state,
        std::uint8_t& depth);
    bool read_role_state(std::array<float, kRawFeatureDim>& relation,
                         float& relation_bias) const;
    bool sense_step(
        std::size_t token_count, const std::vector<std::uint8_t>& tokens,
        const std::vector<std::uint8_t>& positions,
        const std::vector<std::array<float, kRawFeatureDim>>& word_embeddings,
        const std::array<std::array<float, kRawFeatureDim>, 4>& position_gates,
        const std::array<float, kRawFeatureDim>& bias,
        const std::array<float, kRawFeatureDim>& order,
        const std::vector<std::array<float, kRawFeatureDim>>& sense_heads,
        const std::vector<float>& sense_bias, std::size_t target,
        float learning_rate, float orientation, float& probability,
        float& loss);
    bool read_sense_state(std::size_t count,
                          std::vector<std::array<float, kRawFeatureDim>>& heads,
                          std::vector<float>& biases) const;
    bool holo(const std::array<std::uint16_t, 3>& phases,
              std::array<std::int32_t, 2>& out);
    bool ring(const std::array<std::uint16_t, kTriadMemberCount>& phases,
              std::uint32_t shift, std::int32_t& correlation);
    bool leaf(std::uint32_t row_bits, std::uint32_t leaf_mask,
              std::int32_t counter_q16, std::array<std::int32_t, 2>& out);
    bool tca(std::int32_t local_log_probability,
             std::int32_t peer_a_log_probability,
             std::int32_t peer_b_log_probability, std::int32_t& advantage);
    bool flux(std::int32_t phase_u_q16, std::int32_t phase_v_q16,
              std::int32_t weight_q16, std::int32_t source_q16,
              std::array<std::int32_t, 3>& out);
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
    // Context-table/class -> canonical head/triad/field link. The guest reads
    // the high and conditional-low scores (or direct predictions), computes
    // class head = high*16+low, triad = head/3, then turns the 255 head
    // credits into 85 2-of-3 triad votes and the 43/85 field decision.
    bool context_class_map(
        const ContextClassInput& input,
        const std::array<std::int32_t, kTriadMemberCount>& credits,
        ContextClassResult& out);
    // Same mapping with a native CFT or TRAIL credit applied to the selected
    // class head before the triad/field vote. All credit and vote arithmetic
    // remains in the guest.
    bool context_class_credit(
        const ContextClassInput& input,
        const ContextCreditInput& credit,
        const std::array<std::int32_t, kTriadMemberCount>& credits,
        ContextClassResult& out);
    // Chart bridge: run the context class link from the chart's head credits,
    // then copy the guest's 85 triad votes, field count and updated selected
    // head credit into the chart. The chart must still hold the canonical
    // 3t+s triad partition; adaptive remaps are not overwritten.
    bool context_class_apply(Universe& universe,
                             const ContextClassInput& input,
                             const ContextCreditInput& credit,
                             ContextClassResult& out);
    // Raw two-token identity QKV/softmax/tanh feature feed.
    bool micro_feature(const std::array<float, kRawFeatureDim>& x0,
                       const std::array<float, kRawFeatureDim>& x1,
                       std::array<float, kRawFeatureDim>& out);
    // Learned QKV/MLP causal feature block.  Tokens are 8-lane float32
    // vectors; the guest attends causally to the last token.
    bool write_trunk_inputs(
        const std::vector<std::array<float, kRawFeatureDim>>& tokens,
        const TrunkWeights& weights);
    bool write_trunk_weights(const TrunkWeights& weights);
    bool trunk_feature(
        const std::vector<std::array<float, kRawFeatureDim>>& tokens,
        std::array<float, kRawFeatureDim>& out);
    bool causal_trunk(const std::vector<std::array<float, kRawFeatureDim>>& tokens,
                      const TrunkWeights& weights,
                      std::array<float, kRawFeatureDim>& out);
    // Forward using the trunk weights already resident in the guest.  This is
    // the training-loop path: local credit updates are not overwritten.
    bool causal_trunk_cached(
        const std::vector<std::array<float, kRawFeatureDim>>& tokens,
        std::array<float, kRawFeatureDim>& out);
    // Same block with runtime width D<=128, hidden H<=512 and T<=1024.
    bool causal_trunk_wide(const std::vector<float>& tokens, std::size_t count,
                           const WideTrunkWeights& weights,
                           std::vector<float>& out);
    bool causal_trunk_wide_cached(const std::vector<float>& tokens,
                                  std::size_t count, std::size_t dim,
                                  std::vector<float>& out);
    bool set_wide_readout_row(std::uint8_t row, const float* values,
                              std::size_t dim);
    bool qkv_credit_wide(std::uint8_t target, std::uint8_t best_wrong,
                         float learning_rate);
    bool trunk_credit_wide(std::uint8_t target, std::uint8_t best_wrong,
                           float learning_rate);
    bool combine_credits(const std::array<std::int32_t, 7>& credits,
                         const std::array<std::int32_t, 7>& coefficients,
                         std::int32_t& combined);
    bool credit_bundle(const CreditBundleState& state,
                       std::array<std::int32_t, 7>& credits);
    bool credit_ablation(
        const CreditBundleState& state,
        const std::array<std::int32_t, 7>& base_coefficients,
        std::array<std::int32_t, 8>& combined);
    bool combined_trunk_credit(
        std::uint8_t target, std::uint8_t best_wrong,
        std::int32_t base_lr_q16, std::int32_t threshold_q16,
        const std::array<std::int32_t, 7>& credits,
        const std::array<std::int32_t, 7>& coefficients, bool& applied);
    bool combined_trunk_credit_all(
        std::uint8_t target, std::uint8_t best_wrong,
        std::int32_t base_lr_q16, std::int32_t threshold_q16,
        const std::array<std::int32_t, 7>& credits,
        const std::array<std::int32_t, 7>& coefficients, bool& applied);
    bool write_wide_weights(const WideTrunkWeights& weights);
    bool combined_trunk_credit_wide(
        std::uint8_t target, std::uint8_t best_wrong,
        std::int32_t base_lr_q16, std::int32_t threshold_q16,
        const std::array<std::int32_t, 7>& credits,
        const std::array<std::int32_t, 7>& coefficients, bool& applied);
    bool commit_combined_credit(
        std::uint8_t target, std::uint8_t best_wrong,
        std::int32_t base_lr_q16, std::int32_t threshold_q16,
        const std::array<std::int32_t, 7>& credits,
        const std::array<std::int32_t, 7>& coefficients,
        const std::array<std::int32_t, kTriadMemberCount>& head_credits,
        std::int32_t head_threshold_q16,
        bool& field_accepted, bool& committed);
    bool commit_combined_credit_wide(
        std::size_t dim, std::size_t hidden,
        std::uint8_t target, std::uint8_t best_wrong,
        std::int32_t base_lr_q16, std::int32_t threshold_q16,
        const std::array<std::int32_t, 7>& credits,
        const std::array<std::int32_t, 7>& coefficients,
        const std::array<std::int32_t, kTriadMemberCount>& head_credits,
        std::int32_t head_threshold_q16,
        bool& field_accepted, bool& committed);
    bool cft_trunk_credit(std::uint8_t target, std::uint8_t best_wrong,
                          std::int32_t base_lr_q16, std::int32_t threshold_q16,
                          std::int32_t e_ab, std::int32_t e_bc,
                          std::int32_t e_ca, std::int32_t error,
                          std::int32_t rate, bool& applied);
    bool commit_cft_credit(
        std::uint8_t target, std::uint8_t best_wrong,
        std::int32_t base_lr_q16, std::int32_t cft_threshold_q16,
        std::int32_t e_ab, std::int32_t e_bc, std::int32_t e_ca,
        std::int32_t error, std::int32_t rate,
        const std::array<std::int32_t, kTriadMemberCount>& head_credits,
        std::int32_t head_threshold_q16,
        bool& field_accepted, bool& committed);
    bool credit_field_vote(
        const std::array<std::int32_t, kTriadMemberCount>& credits,
        std::int32_t threshold,
        std::array<std::uint8_t, kTriadCount>& votes,
        std::uint16_t& accepted_count, bool& field_accepted);
    // Raw local credit update for the fixed 8-wide output/MLP layers.
    bool trunk_credit(std::uint8_t target, std::uint8_t best_wrong,
                      float learning_rate);
    // Raw QKV local-credit update using the last fixed-trunk forward's alpha,
    // q/k/v and output/MLP activation state.
    bool qkv_credit(std::uint8_t target, std::uint8_t best_wrong,
                    float learning_rate);
    bool readout_train(
        const std::vector<std::array<float, kRawFeatureDim>>& tokens,
        const TrunkWeights& weights, std::uint8_t target, float learning_rate,
        bool& correct, float& target_score, float& best_wrong_score,
        float& loss);
    bool readout_only(const std::array<float, kRawFeatureDim>& feature,
                      std::uint8_t target, float learning_rate,
                      bool& correct, float& target_score,
                      float& best_wrong_score, float& loss);
    bool readout_sample(const std::array<float, kRawFeatureDim>& feature,
                        std::uint8_t target, float learning_rate,
                        std::uint32_t salt, bool& correct,
                        float& target_score, float& best_wrong_score,
                        float& loss);
    bool readout_softmax(const std::array<float, kRawFeatureDim>& feature,
                         std::uint8_t target, float learning_rate,
                         bool& correct, float& loss, float& target_probability);
    bool reset_hier_readout(std::size_t dim);
    bool readout_hier(const float* feature, std::uint8_t target,
                      float learning_rate, std::size_t dim, bool& correct,
                      float& loss, std::uint8_t& predicted_high,
                      std::uint8_t& predicted_low);
    bool reset_context_readout(std::size_t buckets);
    bool load_context_readout(const std::string& path, std::size_t buckets);
    bool save_context_readout(const std::string& path, std::size_t buckets);
    bool readout_context(std::uint8_t target, float learning_rate,
                         std::uint32_t bucket, std::size_t buckets,
                         bool& correct, float& loss,
                         std::uint8_t& predicted_high,
                         std::uint8_t& predicted_low);
    // Multi-order raw route: the guest owns the exact k=4 hash table, its
    // frequency selection, and the k=3 fallback hash.
    bool reset_context_backoff();
    bool context_backoff_build(std::uint32_t key, bool* inserted = nullptr);
    bool context_backoff_build_batch(const std::uint32_t* keys,
                                     std::size_t count,
                                     std::size_t& inserted);
    bool context_backoff_select(std::size_t buckets, std::size_t exact_limit,
                                ContextBackoffSelection& out);
    bool readout_context_backoff(std::uint8_t target, float learning_rate,
                                 std::uint32_t key, std::size_t buckets,
                                 ContextBackoffStep& out);
    void reset_readout();
    bool set_readout_row(std::uint8_t row,
                         const std::array<float, kRawFeatureDim>& values);
    bool read_trunk_weights(TrunkWeights& out) const;
    bool read_wide_weights(std::size_t dim, std::size_t hidden,
                           WideTrunkWeights& out) const;
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
