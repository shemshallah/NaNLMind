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

struct Tensor256Address {
    bool valid = false;
    std::uint32_t cell = 0;
    std::uint8_t lane = 0;
    std::uint32_t byte_offset = 0;
};

// ABI-only transport of results measured by native opcode 106.
struct NativeSpectralTensorRecord {
    std::uint8_t head=0,a=0,b=0;
    std::uint32_t candidate_byte_offset=0;
    std::int32_t credit_q16=0;
};
struct NativeSpectralTensorResult {
    bool accepted=false;
    std::uint16_t accepted_triads=0;
    std::uint8_t rejection_reason=0;
    std::vector<NativeSpectralTensorRecord> records;
};

// Native six-neighbor temporal attention / Poincare disk ABI receipt.
// The NOW reference is physical VOID255 and never a candidate writer.
struct NativeContext6Receipt {
    bool accepted=false;
    std::uint8_t valid_count=0, task=0, reason=0;
    float poincare_x=0.0f,poincare_y=0.0f;
    float radius=0.0f, radial_distance=0.0f;
    std::uint8_t mask=0,now_head=255,horizon=0;
    std::uint32_t observed_anchor=0;
};

// Real 128-dimensional guest Poincare-ball hyperedge projection, with
// signed oriented Hodge-curl feedback. No host numerical reconstruction.
// Per-head independent 16-Boolean/phasor/128D measurement from opcode110.
struct NativeHead16Receipt {
    bool accepted=false;
    std::uint8_t head=255,hot_vote=0,rejection_reason=0,rule=0;
    std::uint16_t candidate_truth_mask=0;
    std::uint32_t source_generation=0;
    std::array<float,128> poincare_vector{};
    float radius=0.0f,radial_distance=0.0f,signed_curl_feedback=0.0f;
    std::int32_t phase_cos_q16=0,phase_sin_q16=0;
};
// Per-triad measurement from three independently measured head vectors.
struct NativeTrihead128Receipt {
    bool accepted=false;
    std::uint8_t triad=255,hot_count=0,cold_count=0,rejection_reason=0;
    std::array<std::uint8_t,3> members{};
    bool unanimous_hot=false,unanimous_cold=false;
    std::int32_t majority_sign=0,source_seven_credit_q16=0;
    std::uint32_t source_generation=0;
    std::array<float,128> poincare_vector{};
    float radius=0.0f,radial_distance=0.0f,signed_curl_feedback=0.0f;
    float candidate_credit_gradient=0.0f;
};
// Full FIELD: 255 privately scratched heads and 85 128D triheads in ONE
// canonical NaN16 VM. Each supplied source must be independently authenticated
// by caller; no invented host vector/gradient/curl or synthetic 84 votes.
struct NativeFullFieldHeadSource {
    std::array<float,128> sourced_vector{};
    std::uint16_t truth_mask=0,candidate_xor_patch=0;
    std::uint32_t boolean_a=0,boolean_b=0;
    bool candidate_writer_lease=false;
    std::array<std::uint8_t,3> sourced_oriented_hyperedge{};
    float sourced_native_hodge_curl=0.0f;
    std::uint16_t phase_turns=0;
};
struct NativeFullField128Receipt {
    bool accepted=false,field_hot=false;
    std::uint8_t rejection_reason=0;
    std::uint16_t head_count=0,triad_count=0,hot_heads=0;
    std::uint16_t hot_majority_triads=0,cold_majority_triads=0;
    std::uint16_t unanimous_hot=0,unanimous_cold=0;
    std::uint32_t source_generation=0;
    std::array<std::uint8_t,255> mapping{};
    std::array<std::uint8_t,85> native_vote_masks{};
    std::array<NativeHead16Receipt,255> heads{};
    std::array<NativeTrihead128Receipt,85> triheads{};
};
// One sampled discrete-curl triangle on the actual NaN16 palindrome anchors
// and paired mirror rails. Native guest computes all f32 gradients, masks,
// 16-bit physical addresses, recovery and Poincare; host transports receipts.
struct NativeMirrorTriangleReceipt {
    bool measured=false,projected=false;
    std::uint16_t sample_index=0;
    std::array<std::uint8_t,3> anchors{};
    std::uint8_t family=0,hot_mask=0,cold_mask=0;
    std::uint8_t hot_count=0,cold_count=0;
    std::int32_t majority_sign=0;
    bool unanimous_hot=false,unanimous_cold=false;
    float loop_curl=0.0f;
    std::array<float,3> directed_edges{};
    float native_reconstruction=0.0f,native_residual=0.0f;
    std::array<std::uint16_t,3> palindrome_addresses{};
    std::array<std::uint16_t,6> directed_mirror_addresses{};
    std::uint32_t source_generation=0;
    float poincare_radius=0.0f,poincare_depth=0.0f;
    float signed_curl_radial_feedback=0.0f;
    std::array<float,128> poincare_vector{};
    std::array<std::uint32_t,32> native_record_words{};
};
struct NativeMirrorTriangleRecoveryReceipt {
    bool accepted=false;
    std::uint8_t rejection_reason=0;
    float reconstructed_edge=0.0f,current_edge=0.0f,residual=0.0f;
    std::uint32_t source_generation=0;
};
struct NativeHyperedge128Receipt {
    bool accepted=false;
    std::uint8_t rejection_reason=0;
    std::array<float,128> poincare_vector{};
    float radius=0.0f,radial_distance=0.0f,signed_curl_feedback=0.0f;
    std::int32_t orientation=0;
    std::uint8_t now_head=255;
};
struct NativeShortlistCandidate {
    float poincare_x=0.0f;
    float poincare_y=0.0f;
    float radius=0.0f;
    float radial_distance=0.0f;
    bool accepted=false;
};
struct DualProposalResult {
    RawProposalResult fast;
    RawProposalResult slow;
    bool field_accepted = false;
    bool slow_ok = false;
    bool committed = false;
    std::uint16_t candidate_mask = 0;
    std::uint16_t committed_mask = 0;
    std::int32_t fast_credit = 0;
    std::int32_t slow_credit = 0;
    std::int32_t medium_credit = 0;
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
    // Raw payload-word transport for host-side paged stores.  This writes the
    // 32-bit guest payload; it does not run guest mathematics.
    bool write_payload_word(std::uint32_t index, std::uint32_t payload) {
        return write_word(index, payload);
    }
    std::uint32_t read_payload_word(std::uint32_t index) const {
        return read_word(index);
    }

    // Host transports authenticated observations/leases into the raw guest.
    // No spectral arithmetic, quorum scoring or mirror offsets happen here.
    // Six slots are ordered [-3,-2,-1,+1,+2,+3].
    // task0 strictly rejects future words; task1 is for MASKED INFILL only.
    // Native opcode107 does ALL CORDIC/attention/Poincare arithmetic.
    // One native fused request: actual stream IDs -> no-target-read six-slot
    // selection -> Q16 CORDIC -> masked MC0 -> Poincare NOW disk.
    // In mode0 target_index MUST equal source.size().
    // In mode1 source[target_index] is never read by the guest.
    bool native_stream6_attention(
        const std::vector<std::uint32_t>& source_word_ids,
        std::uint32_t target_index, std::uint8_t task,
        std::uint32_t masked_query_anchor,
        std::uint32_t expected_generation,
        std::uint32_t current_generation,
        NativeContext6Receipt& receipt);
    // Native opcode112, one fresh causal horizon at a time. The caller
    // passes only its earlier decoder-generated words, never gold future.
    // All temporal selection, trig/attention/Poincare mathematics is guest.
    bool native_future3_causal_attention(
        const std::vector<std::uint32_t>& observed_word_ids,
        const std::array<std::uint32_t,3>& generated_prefix,
        std::uint8_t generated_count,
        std::uint32_t expected_generation, std::uint32_t current_generation,
        NativeContext6Receipt& receipt);
    bool native_context6_attention(
        std::uint32_t observed_anchor,
        const std::array<std::uint32_t,6>& neighbors,
        std::uint8_t valid_mask, std::uint8_t task,
        std::uint32_t expected_generation, std::uint32_t current_generation,
        NativeContext6Receipt& receipt);
    // Native opcode108: full 128D ball, actual Hodge curl supplied by
    // the already verified global Hodge result; host only transports.
    // Each head carries independent scratch, 16 operator mask, CORDIC
    // phase and measured 128D vector. Source/provenance must be verified
    // upstream; the host only writes/reads the raw guest ABI.
    bool native_head16_vector(
        std::uint8_t head,const std::array<float,128>& source_vector,
        std::uint16_t learned_truth_mask,std::uint16_t xor_candidate_patch,
        std::uint32_t bool_operand_a,std::uint32_t bool_operand_b,
        bool authorized_candidate_writer,
        const std::array<std::uint8_t,3>& sourced_oriented_hyperedge,
        float native_hodge_curl,std::uint16_t phase_turns,
        std::uint32_t expected_generation,std::uint32_t current_generation,
        NativeHead16Receipt& receipt);
    // One 85x3 global permutation, but independent trihead VECTOR scratch.
    bool native_triad_hotcold_vector(
        std::uint8_t triad,const std::array<std::uint8_t,255>& mapping,
        float native_hodge_curl,std::int32_t native_seven_credit_q16,
        std::uint32_t expected_generation,std::uint32_t current_generation,
        NativeTrihead128Receipt& receipt);
    // Native opcode113: one measurement pass for ALL 255 heads and ALL
    // 85 128D triheads. Inputs are externally sourced NaN16 observation
    // frames; exact 2/3 field masks and HOT/COLD gradients originate in guest.
    // It does not grant candidate leases or commit a tensor/model update.
    bool native_full_field_255_85(
        const std::array<NativeFullFieldHeadSource,255>& head_sources,
        const std::array<std::uint8_t,255>& mapping,
        const std::array<float,85>& sourced_trihead_hodge_curls,
        const std::array<std::int32_t,85>& sourced_seven_credits_q16,
        std::uint32_t expected_epoch, std::uint32_t current_epoch,
        NativeFullField128Receipt& receipt);
    // Native opcode120: construct the SAME Hodge edge 1-form directly
    // from the TWO independent physical S+/S- rails. Host transports
    // authenticated snapshot bytes but does not subtract mirror weights.
    bool native_mirror_pair_rail_gradient(
        const std::array<float,65280>& sourced_mirror_rails,
        std::uint32_t expected_epoch,std::uint32_t current_epoch,
        std::array<float,32640>& directed_gradients,
        std::uint32_t& hot_pairs,std::uint32_t& cold_pairs,
        std::uint32_t& flat_pairs,bool& accepted,std::uint8_t& reason);
    // Guest opcode114 freezes 255 local and 255 seeded long-distance
    // mirror triangles. A second call rejects silent topology resampling.
    bool native_mirror_triangle_boot(std::uint32_t seed,
        std::uint32_t epoch,bool& accepted,std::uint8_t& reason);
    // Guest opcode115 reads 32,640 canonical directed S+/S- pair
    // gradients, records HOT/COLD and oriented triangle curls for 510
    // samples. No host Hodge/trig/mirror maths or active write.
    bool native_mirror_triangle_measure(
        const std::array<float,32640>& sourced_pair_flows,
        std::uint32_t expected_epoch,std::uint32_t current_epoch,
        std::vector<NativeMirrorTriangleReceipt>& measured,
        std::uint16_t& hot_majority,bool& accepted,std::uint8_t& reason);
    // Guest opcode116 couples selected measured loop curl to SAME
    // 128D Poincare hyperedge kernel and existing private head vectors.
    bool native_mirror_triangle_project(std::uint16_t sample_index,
        std::uint32_t source_epoch,NativeMirrorTriangleReceipt& receipt);
    // Guest opcode117 returns candidate repair from RETAINED nonzero
    // L and the other two current edges, never updates ACTIVE mirror rails.
    bool native_mirror_triangle_recover(std::uint16_t sample_index,
        std::uint32_t epoch,
        const std::array<float,32640>& current_sourced_pair_flows,
        NativeMirrorTriangleRecoveryReceipt& receipt);
    // Native opcode122: one 128D three-layer bf16 head block on a resident
    // page slot 0..19. The host only transports the input vector and the page
    // bytes; LayerNorm, bf16 matvec, attention and residual updates are guest.
    // The current block is single-token, so its local attention is exactly V.
    bool native_head_block(
        const std::array<float,128>& input, std::uint8_t slot,
        std::array<float,128>& output, std::uint8_t& reason);
    // Dedicated head-worker opcode122: T tokens (1..6), 128D each.  The
    // worker image performs full six-token Q/K/V softmax attention and MLP.
    bool native_head_block6(
        const std::array<float, 6 * 128>& input, std::uint8_t token_count,
        std::uint8_t slot, std::array<float, 6 * 128>& output,
        std::uint8_t& reason);
    // Opcode135: 64-token local attention head block (same page layout).
    bool native_head_block64(
        const std::array<float, 64 * 128>& input, std::uint8_t token_count,
        std::uint8_t slot, std::array<float, 64 * 128>& output,
        std::uint8_t& reason, bool last_token_only = false);
    // Dedicated head-worker opcode123: guest-side linear readout of a
    // 128D state against 1..64 transported candidate vectors. This does not
    // claim trained logits or a promotion decision.
    bool native_head_state_readout(
        const std::array<float, 128>& state,
        const std::vector<std::array<float, 128>>& candidates,
        std::vector<float>& scores, std::uint8_t& reason);
    // Dedicated head-worker opcode124: one guest-side softmax SGD step for
    // the transported candidate vectors. The host reads back the updated
    // vectors; no host gradient or loss arithmetic is performed.
    bool native_head_state_train(
        const std::array<float, 128>& state,
        const std::vector<std::array<float, 128>>& candidates,
        std::uint8_t target, float learning_rate,
        std::vector<float>& probabilities,
        std::vector<std::array<float, 128>>& updated_candidates,
        float& loss, std::uint8_t& predicted, std::uint8_t& reason);
    // Dedicated head-worker opcode125: forward the six-token context, then
    // apply one local final-W2 error-corrective update in guest memory.
    // The caller must export the modified page slot afterwards.
    bool native_head_page_train(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        float learning_rate, std::array<float, 6 * 128>& output,
        float& error_norm, std::uint8_t& reason,
        bool update_output_projection = false);
    // Opcode127: local W1 update through the final W2 gradient.
    bool native_head_page_train_w1(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        float learning_rate, std::array<float, 6 * 128>& output,
        float& error_norm, std::uint8_t& reason);
    // Opcode128: local Wv update through final Wo.
    bool native_head_page_train_wv(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        float learning_rate, std::array<float, 6 * 128>& output,
        float& error_norm, std::uint8_t& reason);
    // Opcode129: local final-layer Wq/Wk update via softmax attention.
    bool native_head_page_train_qk(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        float learning_rate, std::array<float, 6 * 128>& output,
        float& error_norm, std::uint8_t& reason);
    // Opcode130: local layer-1 W2 update using the final output error.
    bool native_head_page_train_l1w2(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        float learning_rate, std::array<float, 6 * 128>& output,
        float& error_norm, std::uint8_t& reason);
    // Opcode131: local layer-1 W1 update through layer-1 W2.
    bool native_head_page_train_l1w1(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        float learning_rate, std::array<float, 6 * 128>& output,
        float& error_norm, std::uint8_t& reason);
    // Opcode132: local layer-1 Wo update from the final error.
    bool native_head_page_train_l1wo(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        float learning_rate, std::array<float, 6 * 128>& output,
        float& error_norm, std::uint8_t& reason);
    // Opcode133: local layer-1 Wv update through layer-1 Wo.
    bool native_head_page_train_l1wv(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        float learning_rate, std::array<float, 6 * 128>& output,
        float& error_norm, std::uint8_t& reason);
    // Opcode134: local layer-1 Wq/Wk update through layer-1 softmax.
    bool native_head_page_train_l1qk(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        float learning_rate, std::array<float, 6 * 128>& output,
        float& error_norm, std::uint8_t& reason);
    // Opcode137: exact layer-2 dX2 reverse for T=1 (compatibility overload).
    bool native_head_page_train_dx2(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        std::array<float, 128>& output, std::array<float, 128>& dx2,
        float& error_norm, std::uint8_t& reason);
    // Opcode137: exact layer-2 dX2 reverse for T=1..2. The context, output
    // and dx2 arrays carry T*128 values; loss is last-token only.
    bool native_head_page_train_dx2(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        std::array<float, 6 * 128>& output, std::array<float, 6 * 128>& dx2,
        float& error_norm, std::uint8_t& reason);
    // Opcode138: exact full input dX0 reverse for T=1..2. It runs the same
    // forward captures as opcode137, then reverses layers 2, 1 and 0 with each
    // layer's own page weights. Loss is last-token only; no page mutation.
    bool native_head_page_train_dx0(
        const std::array<float, 6 * 128>& context, std::uint8_t token_count,
        std::uint8_t slot, const std::array<float, 128>& target,
        std::array<float, 6 * 128>& dx0, float& error_norm,
        std::uint8_t& reason);
    bool native_shortlist_batch(
        const std::array<std::uint32_t,6>& context_words,
        std::uint8_t valid_mask, std::uint8_t task,
        std::uint32_t expected_generation, std::uint32_t current_generation,
        const std::vector<std::uint32_t>& candidate_word_ids,
        std::vector<NativeShortlistCandidate>& out,
        std::size_t& accepted);
    bool native_hyperedge128_depth(
        const std::array<float,128>& sourced_vector,
        const std::array<std::uint8_t,3>& ordered_hyperedge,
        float native_hodge_curl, std::uint32_t expected_generation,
        std::uint32_t current_generation,
        NativeHyperedge128Receipt& receipt);
    bool native_spectral_tensor_propose(
        const std::array<std::int64_t,256>& spectral_q16_i64,
        const std::array<std::uint8_t,85>& trihead_masks,
        const std::array<std::array<std::uint8_t,2>,255>& directed_pairs,
        const std::array<std::uint8_t,255>& writer_capabilities,
        std::uint32_t expected_generation, std::uint32_t current_generation,
        bool global_approved, bool meta_approved,
        NativeSpectralTensorResult& result);

    bool triad_score(std::uint16_t m0, std::uint16_t m1, std::uint16_t m2,
                     std::uint32_t a, std::uint32_t b, bool target,
                     std::int32_t& score);
    bool proposal(std::uint16_t current_mask, std::uint16_t patch,
                  const std::array<std::uint16_t, 3>& members,
                  std::uint32_t a, std::uint32_t b, bool target,
                  RawProposalResult& out);
    // Chart bridge: the raw guest decides; only the proposer's mask changes
    // on acceptance, and the chart's integer credit fields are updated here.
    bool propose(Universe& universe, HeadArray& heads, std::uint8_t proposer,
                 std::uint16_t patch, std::uint32_t a, std::uint32_t b,
                 bool target, RawProposalResult& out);
    bool dual_gate(bool fast_accepted, bool slow_accepted, bool field_accepted,
                   std::int32_t coherence, std::int32_t threshold,
                   std::uint16_t current_mask, std::uint16_t patch,
                   DualProposalResult& out);
    bool propose_dual(Universe& universe, HeadArray& heads,
                      std::uint8_t fast_head, std::uint8_t slow_head,
                      std::uint16_t patch, std::uint32_t a, std::uint32_t b,
                      bool target, std::int32_t coherence_threshold,
                      DualProposalResult& out);
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
    using Feature24 = std::array<float, 24>;
    bool init_context24(
        const std::vector<std::array<float, 24>>& word_embeddings,
        const std::array<std::array<float, 24>, 4>& position_gates,
        const std::array<float, 24>& bias,
        const std::array<float, 24>& order);
    bool init_role24(const std::array<float, 24>& relation, float relation_bias);
    bool init_role24k(const std::vector<std::array<float, 24>>& relation_heads,
                      const std::vector<float>& relation_bias);
    bool role_step24k_cached(std::size_t token_count,
                             const std::vector<std::uint8_t>& tokens,
                             const std::vector<std::uint8_t>& positions,
                             std::size_t target_relation, float label,
                             float learning_rate, float orientation,
                             float& probability, float& delta);
    bool read_context24(std::vector<std::array<float, 24>>& word_embeddings,
                        std::array<std::array<float, 24>, 4>& position_gates,
                        std::array<float, 24>& bias,
                        std::array<float, 24>& order);
    bool read_role24k_state(std::vector<std::array<float, 24>>& heads,
                            std::vector<float>& biases);
    bool read_sense24(std::vector<std::array<float, 24>>& heads,
                      std::vector<float>& biases);
    bool role_step24_cached(std::size_t token_count,
                            const std::vector<std::uint8_t>& tokens,
                            const std::vector<std::uint8_t>& positions,
                            float label, float learning_rate, float orientation,
                            float& probability, float& delta);
    bool init_sense24(
        const std::vector<std::array<float, 24>>& sense_heads,
        const std::vector<float>& sense_bias);
    bool sense_step24_cached(std::size_t token_count,
                             const std::vector<std::uint8_t>& tokens,
                             const std::vector<std::uint8_t>& positions,
                             std::size_t target, float learning_rate,
                             float orientation, float& probability, float& loss);
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
    bool phase_encode_wide(const std::uint8_t* bytes, std::size_t count,
                           std::size_t dim, std::vector<std::int32_t>& out,
                           std::uint32_t& shard);
    bool phase_encode_batch(const std::uint8_t* bytes, std::size_t windows,
                            std::size_t window, std::size_t dim,
                            std::vector<std::int32_t>& out);
    bool phase_table_init();
    bool tokenize(const std::string& text, std::size_t max_words,
                  std::vector<std::uint32_t>& words,
                  std::vector<std::uint32_t>& subwords,
                  std::vector<std::uint32_t>& meta,
                  std::size_t& word_count, std::size_t& subword_count);
    bool meta_trihead_reset();
    bool meta_trihead_observe_batch(const std::vector<std::uint32_t>& words,
                                    std::size_t& contexts);
    bool read_meta_trihead(std::vector<std::int32_t>& votes,
                           std::vector<std::int32_t>& credits);
    bool temporal_slots_reset();
    bool temporal_slots_observe_batch(const std::vector<std::uint32_t>& words,
                                      std::size_t& contexts);
    bool temporal_slots_project();
    bool read_temporal_slots(std::size_t count,
                             std::vector<std::int32_t>& past_votes,
                             std::vector<std::int32_t>& past_credits,
                             std::vector<std::int32_t>& future_votes,
                             std::vector<std::int32_t>& future_credits,
                             std::vector<std::uint32_t>& current_words,
                             std::array<std::int32_t, 4>& head255,
                             std::vector<std::int32_t>& slots);
    bool ngram_reset();
    bool ngram_train(const std::string& bytes, std::size_t& processed,
                     std::size_t skip = 0);
    bool ngram_topk(std::array<std::vector<std::uint32_t>, 4>& keys,
                    std::array<std::vector<std::uint32_t>, 4>& counts);
    bool hyperbolic_measure(const std::vector<std::int32_t>& vector,
                            std::size_t dim, std::int32_t& mean,
                            std::int32_t& radial);
    bool path_geometry(const std::vector<std::int32_t>& bank,
                       std::size_t count, std::size_t dim,
                       std::int32_t& length, std::int32_t& closure,
                       std::int32_t& turn, std::int32_t& curvature);
    bool triangle_geometry(const std::vector<std::int32_t>& vectors,
                           std::size_t dim, std::array<std::int32_t, 3>& sides,
                           std::int32_t& area_proxy, std::int32_t& tightness,
                           std::int32_t& orientation,
                           std::int32_t* stretch = nullptr);
    bool field_perturb(const std::vector<std::int32_t>& vector,
                       std::size_t dim, std::vector<std::int32_t>& credits,
                       std::vector<std::int32_t>& votes,
                       std::int32_t& field_value);
    bool phase_hyperbolic(const std::vector<std::int32_t>& phase_vector,
                          std::size_t lanes, std::int32_t& mean_energy,
                          std::int32_t& radial);
    bool meta_attention(const std::vector<float>& query,
                        const std::vector<float>& keys,
                        const std::vector<float>& values,
                        const std::vector<std::uint32_t>& mask,
                        std::size_t slots, std::size_t dim,
                        std::vector<float>& out);
    bool shape_field_reset();
    bool shape_field_observe(std::uint32_t triad, std::int32_t tightness,
                             std::int32_t orientation, std::int32_t area);
    bool shape_field_gate(std::int32_t closure, std::int32_t path_length,
                          std::int32_t threshold, std::uint16_t& accepted,
                          bool& field_hot, std::int32_t& mean_quality);
    bool global_hodge(
        const std::array<float, 32640>& pair_flows,
        const std::vector<std::array<std::uint32_t, 3>>& triangles,
        std::array<float, 256>& divergence,
        std::array<float, 16>& curl);
    bool global_hodge_q16(
        const std::vector<std::int32_t>& pair_flows_q16,
        const std::vector<std::array<std::uint32_t, 3>>& triangles,
        std::array<float, 256>& divergence,
        std::array<float, 16>& curl);
    bool tensor256_address(std::uint8_t h, std::uint8_t a, std::uint8_t b,
                           Tensor256Address& out);
    bool tensor256_dual_address(std::uint8_t h, std::uint8_t a,
                                std::uint8_t b, std::uint8_t bank,
                                Tensor256Address& out);
    bool build_triangle_flow(
        const std::array<std::array<std::uint32_t, 3>, 16>& triads,
        std::size_t triad_count);
    bool global_hodge_from_triads(
        const std::array<std::array<std::uint32_t, 3>, 16>& triads,
        std::size_t triad_count, std::vector<float>& divergence,
        std::vector<float>& curl);
    bool triangle_model_reset();
    bool triangle_model_observe(const std::array<std::int32_t, 3>& sides,
                                std::int32_t area, std::int32_t tightness,
                                std::int32_t orientation, std::int32_t& count);
    bool triangle_model_score(const std::array<std::int32_t, 3>& sides,
                              std::int32_t area, std::int32_t tightness,
                              std::int32_t& score);
    bool triangle_model_observe_negative(
        const std::array<std::int32_t, 3>& sides, std::int32_t area,
        std::int32_t tightness, std::int32_t orientation, std::int32_t& count);
    bool triangle_model_score_contrastive(
        const std::array<std::int32_t, 3>& sides, std::int32_t area,
        std::int32_t tightness, std::int32_t& score);
    bool read_triangle_model(std::array<std::int32_t, 3>& shape_stats,
                             std::array<std::int32_t, 2>& orientation_counts);
    bool read_triangle_model_negative(
        std::array<std::int32_t, 3>& shape_stats,
        std::array<std::int32_t, 2>& orientation_counts);
    bool phase_rotate(const std::vector<std::int32_t>& in, std::uint32_t turn,
                      std::vector<std::int32_t>& out);
    bool pq_encode(const std::vector<std::int32_t>& query,
                   const std::vector<std::int32_t>& codebook,
                   std::size_t codewords, std::size_t dim,
                   std::uint32_t& code, std::int32_t& distance);
    bool pq_train(const std::vector<std::int32_t>& samples,
                  std::size_t count, std::size_t dim, std::size_t codewords,
                  std::size_t iterations, std::vector<std::int32_t>& codebook);
    bool pq_update(const std::vector<std::int32_t>& samples,
                   std::size_t count, std::size_t dim, std::size_t codewords,
                   std::size_t iterations, std::vector<std::int32_t>& codebook,
                   std::size_t prior_count = 0);
    bool pq_residuals(const std::vector<std::int32_t>& samples,
                      const std::vector<std::uint32_t>& codes,
                      std::size_t count, std::size_t dim,
                      const std::vector<std::int32_t>& codebook,
                      std::vector<std::int32_t>& residuals);
    bool leaf_verify(const std::vector<std::int32_t>& expected,
                     const std::vector<std::int32_t>& codebook,
                     const std::vector<std::int32_t>& residual,
                     std::uint32_t code, std::size_t dim,
                     std::uint32_t tolerance, bool& accepted,
                     std::int32_t& error);
    bool raw_hash(const std::vector<std::int32_t>& payload,
                  std::uint32_t& digest);
    bool spectral_iter(const std::array<std::int32_t, 64>& adjacency,
                       const std::array<std::int32_t, 8>& in,
                       std::array<std::int32_t, 8>& out);
    bool sparse_knn(const std::vector<std::int32_t>& query,
                    const std::vector<std::int32_t>& bank, std::size_t count,
                    std::size_t dim, std::size_t k,
                    std::vector<std::uint32_t>& indices,
                    std::vector<std::int32_t>& scores);
    bool vector_matrix_reset();
    bool vector_matrix_accumulate(std::uint8_t a, std::uint8_t b,
                                  std::int32_t delta, std::uint32_t& index,
                                  std::int32_t& value);
    bool vector_matrix_probe(std::uint8_t a, std::int32_t threshold,
                             std::int32_t& best_head, std::int32_t& score);
    bool read_vector_matrix(std::vector<std::int32_t>& cells);
    bool load_vector_matrix(const std::vector<std::int32_t>& cells);
    bool vector_matrix_credits(std::vector<std::int32_t>& credits);
    bool reset_context_readout(std::size_t buckets);
    bool load_context_readout(const std::string& path, std::size_t buckets);
    bool save_context_readout(const std::string& path, std::size_t buckets);
    bool reset_context_copy(const std::vector<std::uint32_t>& exact_contexts,
                            std::size_t buckets, std::size_t aux_buckets);
    bool readout_context_copy(std::uint8_t target, float learning_rate,
                              std::uint32_t context_key,
                              std::size_t buckets, std::size_t exact_count,
                              std::size_t aux_buckets, float gate_weight,
                              bool& correct, float& loss,
                              std::uint8_t& predicted_class);
    bool readout_context(std::uint8_t target, float learning_rate,
                         std::uint32_t bucket, std::size_t buckets,
                         bool& correct, float& loss,
                         std::uint8_t& predicted_high,
                         std::uint8_t& predicted_low);
    bool readout_context_joint(std::uint8_t target, float learning_rate,
                               std::uint32_t bucket, std::size_t buckets,
                               bool& correct, float& loss,
                               std::uint8_t& predicted_high,
                               std::uint8_t& predicted_low);
    bool set_context_high(std::size_t bucket, std::size_t high_class,
                          float value, std::size_t buckets);
    bool set_context_low(std::size_t bucket, std::size_t high_class,
                         std::size_t low_class, float value,
                         std::size_t buckets);
    // Multi-order raw route: the guest owns the exact k=4 hash table, its
    // frequency selection, and the k=3 fallback hash.
    bool reset_context_backoff();
    bool context_backoff_build(std::uint32_t key, bool* inserted = nullptr);
    bool context_backoff_build_batch(const std::uint32_t* keys,
                                     std::size_t count,
                                     std::size_t& inserted);
    bool context_backoff_select(std::size_t buckets, std::size_t exact_limit,
                                ContextBackoffSelection& out);
    // Read back the exact-context keys selected by the guest, ordered by the
    // compact slot the guest assigned.  This only transports guest state; no
    // key selection or hashing is repeated on the host.
    bool context_backoff_exact_keys(std::size_t exact_count,
                                    std::vector<std::uint32_t>& keys);
    bool readout_context_backoff(std::uint8_t target, float learning_rate,
                                 std::uint32_t key, std::size_t buckets,
                                 ContextBackoffStep& out);
    // Native full 256-class top-5 over the same exact/fallback context route.
    // The guest returns the ranked byte classes and the target natural-log loss.
    bool readout_context_top5(std::uint8_t target, std::uint32_t key,
                              std::size_t buckets,
                              std::array<std::uint8_t, 5>& top,
                              float& loss);
    // Direct 256-bin context histogram (mode 7 step, mode 8 top-5).
    bool reset_context_direct(std::size_t exact_count,
                              std::size_t fallback_count);
    bool context_direct_step(std::uint8_t target, std::uint32_t key,
                             std::size_t exact_count,
                             std::size_t fallback_count,
                             std::uint32_t& bucket, bool& exact);
    bool readout_context_direct_top5(
        std::uint8_t target, std::uint32_t key,
        std::size_t exact_count, std::size_t fallback_count,
        std::array<std::uint8_t, 5>& top, float& loss);
    // Native full-vocabulary word projection (unified field driver).
    bool word_projection_clear(std::size_t vocabulary);
    // Full-vocabulary token projection with top context rows.
    bool token_projection_clear(std::size_t vocabulary, std::size_t rows);
    bool token_projection_write_rowmap(
        const std::array<std::uint16_t, 65536>& rowmap);
    // Unified field-driver projection layer (command 124).
    bool unified_word_build(const std::vector<std::uint32_t>& ids,
                            std::size_t vocabulary);
    bool unified_word_batch(const std::vector<std::uint32_t>& ids,
                            std::size_t vocabulary,
                            std::uint32_t previous);
    bool unified_word_top5(std::uint32_t target, std::uint32_t context,
                           std::size_t vocabulary, std::uint32_t token_count,
                           std::array<std::uint32_t, 5>& top, float& loss);
    bool unified_token_build(const std::vector<std::uint32_t>& ids,
                             std::size_t vocabulary, std::size_t rows,
                             std::uint32_t previous);
    bool unified_token_top5(std::uint32_t target, std::uint32_t row,
                            std::size_t vocabulary,
                            std::uint32_t token_count,
                            std::array<std::uint32_t, 5>& top, float& loss);
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
    bool phase_table_ready_ = false;
    std::string error_;
};

} // namespace nanlm
