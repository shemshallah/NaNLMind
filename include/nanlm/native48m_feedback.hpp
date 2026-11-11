// Original 48M decoder's NaN16 measurement-to-candidate bridge.
// Guest kernels own phase, trihead voting, global Hodge and MC0 attention.
// The host only transports verified guest outputs into the full dual tensor;
// no second decoder, new checkpoint, or host-side model math is introduced.
#pragma once
#include "nanlm/dual_tensor_arena.hpp"
#include "nanlm/raw_field.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <deque>
#include <stdexcept>
#include <string>
#include <vector>

namespace nanlm {
struct Native48MFeedbackReceipt {
    std::uint8_t proposer=0, h=0, a=0, b=0;
    std::uint32_t phase_shard=0;
    std::array<std::int32_t,16> phase_q16{};
    // Direct bridge of four guest-measured layers into the MC0 query/key:
    // phase[0..15], native field, trihead credit, Hodge div and curl.
    std::array<float,20> meta_features{};
    std::array<std::uint8_t,85> triad_votes{};
    std::array<std::int32_t,255> head_credits{};
    HotTriheadResult native_hot{}; // hothead->native dynamically mapped hottriheads
    std::int32_t field_q16=0;
    std::uint16_t accepted_triads=0;
    bool field_accepted=false, has_admitted_faces=false;
    std::array<float,256> divergence{};
    std::array<float,16> curl{};
    bool meta_available=false, candidate_staged=false;
    float native_log_weight=0.0f;
    std::size_t committed_history_slots=0;
    std::size_t native_observed_contexts=0;
    bool native_measured=false;
};
class Native48MFeedbackBridge {
public:
    static constexpr std::size_t kDim=16;
    static constexpr std::size_t kMetaDim=20;
    Native48MFeedbackBridge(RawFieldVM& vm, DualTensor256Arena& arena)
       : vm_(vm),arena_(arena) {}
    void reset_native_session(){
        if(!vm_.meta_trihead_reset())throw std::runtime_error(vm_.error());
        history_.clear();
        initialized_=true;
    }
    // pair_flows and admitted_faces MUST originate in a real, sourced
    // upstream observation. Empty faces are allowed for bootstrap but do
    // not constitute global Hodge evidence for tensor promotion.
    Native48MFeedbackReceipt measure_and_stage(
        const std::vector<std::uint8_t>& bytes,
        const std::vector<std::uint32_t>& guest_word_ids,
        std::uint8_t proposer,std::uint8_t h,std::uint8_t a,std::uint8_t b,
        const std::array<float,32640>& pair_flows,
        const std::vector<std::array<std::uint32_t,3>>& admitted_faces) {
        if(!initialized_)throw std::logic_error("call reset_native_session");
        if(bytes.empty()||bytes.size()>64||guest_word_ids.empty()||
           guest_word_ids.size()>4096 || admitted_faces.size()>16)
            throw std::invalid_argument("invalid native observation envelope");
        // Reject reserved physical heads and coordinates before any guest call.
        DualTensor256Arena::index(h,a,b);
        if(proposer>=255)throw std::out_of_range("reserved proposer");
        Native48MFeedbackReceipt r;
        r.proposer=proposer;r.h=h;r.a=a;r.b=b;
        std::vector<std::int32_t> phase, head_credits, votes;
        if(!vm_.phase_encode_wide(bytes.data(),bytes.size(),8,phase,r.phase_shard))
            throw std::runtime_error("phase guest: "+vm_.error());
        if(phase.size()!=kDim)throw std::runtime_error("phase guest width");
        std::copy(phase.begin(),phase.end(),r.phase_q16.begin());
        if(!vm_.field_perturb(phase,kDim,head_credits,votes,r.field_q16))
            throw std::runtime_error("field guest: "+vm_.error());
        std::size_t contexts=0;
        if(!vm_.meta_trihead_observe_batch(guest_word_ids,contexts))
            throw std::runtime_error("trihead guest: "+vm_.error());
        r.native_observed_contexts=contexts;
        if(!vm_.read_meta_trihead(votes,head_credits))
            throw std::runtime_error("trihead read: "+vm_.error());
        if(votes.size()!=85||head_credits.size()!=255)
            throw std::runtime_error("native vote/credit shape");
        for(std::size_t i=0;i<85;++i){
            if(votes[i]<0||votes[i]>7)throw std::runtime_error("native invalid vote");
            r.triad_votes[i]=static_cast<std::uint8_t>(votes[i]);
        }
        std::copy(head_credits.begin(),head_credits.end(),r.head_credits.begin());
        // Actual native hothead scan and dynamically reordered 85x3 map.
        // It is a measurement, NOT a new independent chart authority:
        // no live trihead remap occurs without a separate authorization.
        if(!vm_.hot_triheads(r.head_credits,0,r.native_hot))
            throw std::runtime_error("hothead->hottrihead guest: "+vm_.error());
        if(!vm_.field_vote(r.triad_votes,r.accepted_triads,r.field_accepted))
            throw std::runtime_error("field vote guest: "+vm_.error());
        if(!vm_.global_hodge(pair_flows,admitted_faces,r.divergence,r.curl))
            throw std::runtime_error("Hodge guest: "+vm_.error());
        r.has_admitted_faces=!admitted_faces.empty();
        r.committed_history_slots=history_.size();
        r.native_measured=true;
        for(std::size_t i=0;i<kDim;++i)
            r.meta_features[i]=static_cast<float>(r.phase_q16[i])/65536.0f;
        r.meta_features[16]=static_cast<float>(r.field_q16)/65536.0f;
        r.meta_features[17]=static_cast<float>(r.head_credits[proposer])/65536.0f;
        r.meta_features[18]=r.divergence[h];
        r.meta_features[19]=r.curl[0];
        for(float v:r.meta_features)
            if(!std::isfinite(v))throw std::runtime_error("nonfinite native meta feature");

        // No future/current slot enters MC0: only explicitly committed past
        // phase observations may provide keys/values.
        if(history_.empty())return r;
        std::vector<float> query,keys,values;
        std::vector<std::uint32_t> mask;
        query.reserve(kMetaDim);
        keys.reserve(history_.size()*kMetaDim);
        values.reserve(history_.size()*kMetaDim);
        for(float x:r.meta_features)query.push_back(x);
        for(const auto& past:history_){
            for(float x:past){keys.push_back(x);values.push_back(x);}
            mask.push_back(1u);
        }
        std::vector<float> guest_meta;
        if(!vm_.meta_attention(query,keys,values,mask,mask.size(),kMetaDim,guest_meta))
            throw std::runtime_error("MC0 guest: "+vm_.error());
        if(guest_meta.size()!=kMetaDim||!std::isfinite(guest_meta[0])||
           std::fabs(guest_meta[0])>8.0f)
            throw std::runtime_error("native MC0 candidate outside finite log-weight contract");
        Tensor256Address native_address{};
        if(!vm_.tensor256_dual_address(h,a,b,1,native_address)||!native_address.valid)
            throw std::runtime_error("native dual tensor mapping rejected");
        if(native_address.byte_offset!=DualTensor256Arena::byte_offset(h,a,b,1))
            throw std::runtime_error("native/host dual tensor map disagrees");
        // Guest MC0 output is the candidate word log-weight and tensor value.
        // Conversion of Q16 phase for ABI transport is not a trained host layer.
        // Native model arithmetic occurred in phase/trihead/Hodge/MC0 guest.
        arena_.stage_native_value(proposer,h,a,b,guest_meta[0]);
        r.native_log_weight=guest_meta[0];
        r.meta_available=true;
        r.candidate_staged=true;
        return r;
    }
    struct LossFeedbackResult {
        std::int32_t guest_tca_credit_q16=0;
        std::int32_t guest_combined_credit_q16=0;
        float candidate_tensor_value=0.0f;
    };
    // Call only after the ORIGINAL R25 decoder has scored a candidate word.
    // The transport passes log P(candidate word|context) from the frozen
    // 48M decoder and the normalized candidate distribution as Q16.16.
    // Native TCA computes their signed advantage; native credit-combine
    // blends it with the earlier guest MC0 response. The C++ side performs
    // only ABI conversion and stages the result in candidate storage.
    // No active tensor or 48M parameter mutation is allowed here.
    LossFeedbackResult stage_decoder_loss_feedback(
        const Native48MFeedbackReceipt& receipt,
        std::int32_t baseline_log_probability_q16,
        std::int32_t candidate_log_probability_q16,
        const std::array<std::int32_t,7>& guest_coefficients_q16) {
        if(!receipt.native_measured||!receipt.meta_available||!receipt.candidate_staged)
            throw std::invalid_argument("requires staged guest feedback receipt");
        if(!arena_.candidate_open())
            throw std::logic_error("candidate bank was closed before loss feedback");
        if(baseline_log_probability_q16>0||candidate_log_probability_q16>0)
            throw std::invalid_argument("invalid log-probability sign");
        std::int32_t advantage=0;
        if(!vm_.tca(candidate_log_probability_q16,
                    baseline_log_probability_q16,
                    baseline_log_probability_q16,advantage))
            throw std::runtime_error("native loss TCA: "+vm_.error());
        const double meta_q16=static_cast<double>(receipt.native_log_weight)*65536.0;
        if(!std::isfinite(meta_q16)||std::fabs(meta_q16)>524288.0)
            throw std::invalid_argument("invalid native meta credit");
        std::array<std::int32_t,7> channels{};
        channels[0]=static_cast<std::int32_t>(std::llround(meta_q16));
        channels[5]=advantage; // TCA, native signed exact-word loss improvement
        std::int32_t guest_combined=0;
        if(!vm_.combine_credits(channels,guest_coefficients_q16,guest_combined))
            throw std::runtime_error("native loss credit combine: "+vm_.error());
        const float candidate_value=static_cast<float>(guest_combined)/65536.0f;
        if(!std::isfinite(candidate_value)||std::fabs(candidate_value)>8.0f)
            throw std::invalid_argument("native candidate credit outside bound");
        arena_.stage_native_value(receipt.proposer,receipt.h,receipt.a,
                                  receipt.b,candidate_value);
        return {advantage,guest_combined,candidate_value};
    }

    struct SevenCreditFeedbackResult {
        // Order: CFT, TRAIL, HOLO, RING, LEAF, TCA, FLUX.
        std::array<std::int32_t,7> native_credits_q16{};
        std::int32_t native_combined_q16=0;
        float staged_tensor_value=0.0f;
    };
    // All seven paths MUST be evaluated by the existing NaN16 MTH guest.
    // The caller supplies real CFT/TRAIL/HOLO/RING/LEAF/FLUX observations
    // from the current native session; the TCA peer comparison is replaced
    // with the ORIGINAL 48M exact-word decoder's scored log probabilities.
    // None of these fixture/state arguments authorizes production promotion.
    SevenCreditFeedbackResult stage_seven_credit_feedback(
        const Native48MFeedbackReceipt& receipt,
        CreditBundleState sourced_state,
        std::int32_t baseline_log_probability_q16,
        std::int32_t candidate_log_probability_q16,
        const std::array<std::int32_t,7>& coefficients_q16) {
        if(!receipt.native_measured||!receipt.meta_available||
           !receipt.candidate_staged||!arena_.candidate_open())
            throw std::logic_error("seven-credit update needs staged native candidate");
        if(baseline_log_probability_q16>0 || candidate_log_probability_q16>0)
            throw std::invalid_argument("exact-word log probability must be <= 0");
        sourced_state.tca={
            candidate_log_probability_q16,
            baseline_log_probability_q16,
            baseline_log_probability_q16};
        SevenCreditFeedbackResult result;
        if(!vm_.credit_bundle(sourced_state,result.native_credits_q16))
            throw std::runtime_error("NaN16 seven-credit bundle: "+vm_.error());
        if(!vm_.combine_credits(result.native_credits_q16,coefficients_q16,
                                 result.native_combined_q16))
            throw std::runtime_error("NaN16 seven-credit combine: "+vm_.error());
        result.staged_tensor_value=
            static_cast<float>(result.native_combined_q16)/65536.0f;
        if(!std::isfinite(result.staged_tensor_value)||
           std::fabs(result.staged_tensor_value)>8.0f)
            throw std::invalid_argument("native seven-credit output exceeds safe candidate range");
        arena_.stage_native_value(receipt.proposer,receipt.h,receipt.a,
                                  receipt.b,result.staged_tensor_value);
        return result;
    }

    // Make every trihead member (all 255 eligible heads) an independent
    // candidate tensor proposer when the coordinator grants the capability.
    // The mapping may be the canonical triples or a runtime remap, but it
    // must be a genuine partition of heads 0..254: no void255 or duplicates.
    // Only one ordered mirror orientation is modified for each head; the
    // reverse direction is NOT inferred from a single scalar credit.
    static std::array<std::array<std::uint8_t,3>,85> canonical_triheads(){
        std::array<std::array<std::uint8_t,3>,85> partition{};
        for(std::size_t t=0;t<85;++t)
            for(std::size_t k=0;k<3;++k)
                partition[t][k]=static_cast<std::uint8_t>(3*t+k);
        return partition;
    }
    std::size_t stage_all_trihead_candidate_credits(
        const Native48MFeedbackReceipt& receipt,
        const std::array<std::array<std::uint8_t,3>,85>& triheads){
        if(!receipt.native_measured || !arena_.candidate_open())
            throw std::logic_error("requires real native observation and candidate bank");
        std::array<bool,255> seen{};
        // Prevalidate the ENTIRE partition and every needed writer capability
        // before applying the first write, so malformed remaps are atomic.
        for(const auto& trio:triheads){
            for(auto h:trio){
                if(h>=255 || seen[h])
                    throw std::invalid_argument("invalid/duplicated trihead member");
                seen[h]=true;
                if(receipt.head_credits[h]!=0 && !arena_.candidate_writer_allowed(h))
                    throw std::logic_error("trihead member lacks candidate writer lease");
            }
        }
        for(bool member:seen)
            if(!member)throw std::invalid_argument("trihead mapping omitted head");
        std::size_t writes=0;
        for(const auto& trio:triheads){
            for(std::size_t k=0;k<3;++k){
                const unsigned h=trio[k];
                const auto signed_credit=receipt.head_credits[h];
                if(signed_credit==0)continue; // do not zero learned tensor.
                const float native_q16_credit=
                    static_cast<float>(signed_credit)/65536.0f;
                arena_.stage_native_value(h,h,trio[(k+1)%3],
                                          trio[(k+2)%3],native_q16_credit);
                ++writes;
            }
        }
        return writes;
    }

    // Additional closed-loop path:
    // Native six-position temporal attention -> Poincare disk (2D) ->
    // the SAME candidate mirrored tensor. Existing global Hodge/curl,
    // trihead votes and committed MC0 context must already be observed.
    // The guest's two signed phasor coordinates occupy independent directed
    // mirror lanes. Host does not compute trigonometry, attention or depth.
    // Strict whole-word NLL and quorum still decide eventual promotion.
    std::size_t stage_native_temporal_poincare_feedback(
        const Native48MFeedbackReceipt& head,
        const NativeContext6Receipt& temporal) {
        if (!head.native_measured || !head.meta_available ||
            !head.has_admitted_faces || !head.candidate_staged ||
            !temporal.accepted || temporal.now_head!=255 ||
            !arena_.candidate_open())
            throw std::logic_error("requires Hodge and MC0 guest evidence and temporal NOW");
        if (head.h>=255 || head.a>=255 || head.b>=255 ||
            head.a==head.b || head.proposer>=255 ||
            !arena_.candidate_writer_allowed(head.proposer))
            throw std::logic_error("unauthorized mirror-lane feedback");
        if (temporal.task==0 && (temporal.mask & 0x38u)!=0)
            throw std::logic_error("future leakage in causal feedback");
        if (!std::isfinite(temporal.poincare_x) ||
            !std::isfinite(temporal.poincare_y) ||
            !std::isfinite(temporal.radius) ||
            !std::isfinite(temporal.radial_distance) ||
            temporal.radius<0.0f || temporal.radius>=1.0f)
            throw std::logic_error("invalid native Poincare output");
        // Independent native address confirmations, both banks protected.
        Tensor256Address fwd{},rev{};
        if (!vm_.tensor256_dual_address(head.h,head.a,head.b,1,fwd) ||
            !vm_.tensor256_dual_address(head.h,head.b,head.a,1,rev) ||
            !fwd.valid || !rev.valid ||
            fwd.byte_offset!=DualTensor256Arena::byte_offset(
                head.h,head.a,head.b,1) ||
            rev.byte_offset!=DualTensor256Arena::byte_offset(
                head.h,head.b,head.a,1) ||
            fwd.byte_offset==rev.byte_offset)
            throw std::runtime_error("directed mirror mapping is inconsistent");
        arena_.stage_native_value(head.proposer,head.h,head.a,head.b,
                                  temporal.poincare_x);
        arena_.stage_native_value(head.proposer,head.h,head.b,head.a,
                                  temporal.poincare_y);
        return 2;
    }

    // Three-step causal prediction remains a SINGLE original frozen-48M
    // decoder. A new guest measurement is required after EVERY generated
    // word; the caller may pass only the decoder's own previous predictions.
    // Native NaN16 opcode112 performs window selection, CORDIC, masked MC0,
    // Poincare geometry; this transport stores ALL three snapshots as typed
    // TemporalContext leaves at the SAME directed candidate tensor address.
    // Tensor scalar x/y lanes show the most recent proposal, while uniquely
    // keyed horizon leaves preserve earlier native observations. Real Hodge,
    // 2/3 triad votes and committed-history MC0 must already have been
    // sourced: fixture-only evidence never authorizes ACTIVE promotion.
    bool measure_stage_native_future3_horizon(
        const Native48MFeedbackReceipt& measured_field,
        const std::vector<std::uint32_t>& observed_word_ids,
        const std::array<std::uint32_t,3>& decoder_generated_prefix,
        std::uint8_t generated_count,
        std::uint32_t expected_source_epoch,
        std::uint32_t actual_source_epoch,
        std::uint64_t expected_tensor_generation,
        std::uint64_t first_logical_leaf_id,
        const std::string& source_sha256,
        NativeContext6Receipt& horizon) {
        horizon={};
        if (!valid_tensor_leaf_sha256(source_sha256) ||
            first_logical_leaf_id==0u ||
            first_logical_leaf_id>std::numeric_limits<std::uint64_t>::max()-2u)
            throw std::invalid_argument("future3 requires authenticated source digest and leaf ID range");
        if (!arena_.candidate_open() ||
            arena_.generation()!=expected_tensor_generation)
            throw std::logic_error("future3 candidate generation stale or closed");
        if (!measured_field.native_measured ||
            !measured_field.has_admitted_faces ||
            !measured_field.meta_available ||
            !measured_field.candidate_staged ||
            measured_field.proposer>=255u ||
            !arena_.candidate_writer_allowed(measured_field.proposer))
            throw std::logic_error("future3 requires sourced head/trihead Hodge and meta evidence");
        if (!vm_.native_future3_causal_attention(
                observed_word_ids,decoder_generated_prefix,generated_count,
                expected_source_epoch,actual_source_epoch,horizon))
            throw std::runtime_error("native future3 guest: "+vm_.error());
        if (!horizon.accepted) return false; // guest denied; no candidate mutation
        if (horizon.horizon!=generated_count+1u || horizon.task!=0u ||
            horizon.now_head!=255u || horizon.mask==0u ||
            (horizon.mask&0x38u)!=0u)
            throw std::logic_error("native future3 horizon/cause contract violated");
        TensorDataLeaf leaf{};
        leaf.kind=TensorLeafKind::TemporalContext;
        leaf.logical_leaf_id=first_logical_leaf_id+horizon.horizon-1u;
        leaf.source_generation=expected_tensor_generation;
        leaf.source_sha256=source_sha256;
        // Transport the GUEST measurement without independently recomputing
        // trig, hyperbolic depth, Hodge curl or MC0. Portable little-endian
        // storage: 'NF31', horizon/mask/NOW/count, anchor, x/y/r/depth,
        // native curl, divergence, MC0 credit, triad quorum, source epoch.
        leaf.payload={'N','F','3','1',horizon.horizon,horizon.mask,
                      horizon.now_head,horizon.valid_count};
        const auto append_u32=[&](std::uint32_t word){
            for(unsigned i=0;i<4u;++i)
                leaf.payload.push_back(static_cast<std::uint8_t>(word>>(8u*i)));
        };
        const auto append_f32=[&](float native_word){
            std::uint32_t bits=0u;
            static_assert(sizeof(bits)==sizeof(native_word));
            std::memcpy(&bits,&native_word,sizeof(bits));
            append_u32(bits);
        };
        append_u32(horizon.observed_anchor);
        append_f32(horizon.poincare_x);
        append_f32(horizon.poincare_y);
        append_f32(horizon.radius);
        append_f32(horizon.radial_distance);
        append_f32(measured_field.curl[0]);
        append_f32(measured_field.divergence[measured_field.h]);
        append_f32(measured_field.native_log_weight);
        append_u32(measured_field.accepted_triads);
        append_u32(expected_source_epoch);
        // A failed data-leaf attach must also discard newly staged scalars,
        // rather than leaving a candidate with incomplete provenance.
        try {
            stage_native_temporal_poincare_feedback(measured_field,horizon);
            if(!arena_.attach_candidate_leaf(
                   measured_field.proposer,measured_field.h,
                   measured_field.a,measured_field.b,leaf))
                throw std::logic_error("future3 duplicate horizon leaf identity");
        } catch (...) {
            arena_.abort_candidate(); // ACTIVE bank remains unchanged
            throw;
        }
        return true;
    }

    // Allow the dynamic hottrihead map to propose from all 255 heads
    // only after its OWN native quorum and the sourced Hodge/MC0 gates.
    // No remap of active chart state and no active tensor mutation.
    std::size_t stage_native_hottrihead_feedback(
        const Native48MFeedbackReceipt& receipt) {
        if (!receipt.native_measured || !receipt.native_hot.field_hot ||
            !receipt.has_admitted_faces || !receipt.meta_available ||
            !arena_.candidate_open())
            throw std::logic_error("native hottrihead quorum/Hodge/MC0 not met");
        if (receipt.native_hot.hot_triads<43u ||
            receipt.native_hot.hot_heads<129u)
            throw std::logic_error("invalid native hottrihead majority");
        std::array<std::array<std::uint8_t,3>,85> triads{};
        for (std::size_t t=0;t<85;++t)
            for (std::size_t slot=0;slot<3;++slot)
                triads[t][slot]=receipt.native_hot.members[3*t+slot];
        return stage_all_trihead_candidate_credits(receipt,triads);
    }

    // Hodge curl -> 128D native Poincare hyperedge depth -> a separate
    // physical mirror pair in the same 128MiB candidate arena. The
    // temporal phase at (a,b) remains intact: (h,a) and (a,h) encode
    // native signed curvature feedback and native radial distance.
    // Only the controller can promote after *real* held-out 48M NLL.
    NativeHyperedge128Receipt stage_native_hyperedge128_feedback(
        const Native48MFeedbackReceipt& head,
        const std::array<float,128>& sourced_native_vector,
        std::uint32_t expected_generation,
        std::uint32_t current_generation) {
        if (!head.native_measured || !head.meta_available ||
            !head.has_admitted_faces || !head.candidate_staged ||
            !arena_.candidate_open() || !std::isfinite(head.curl[0]))
            throw std::logic_error("hyperedge must have native Hodge and MC0 evidence");
        if (head.h>=255 || head.a>=255 || head.b>=255 ||
            head.h==head.a || head.h==head.b || head.a==head.b ||
            head.proposer>=255 || !arena_.candidate_writer_allowed(head.proposer) ||
            static_cast<std::uint64_t>(expected_generation)!=arena_.generation())
            throw std::logic_error("invalid hyperedge identity or stale owner epoch");
        NativeHyperedge128Receipt result{};
        const std::array<std::uint8_t,3> edge={head.h,head.a,head.b};
        if (!vm_.native_hyperedge128_depth(
                sourced_native_vector,edge,head.curl[0],
                expected_generation,current_generation,result))
            throw std::runtime_error("native Poincare128 guest: "+vm_.error());
        if (!result.accepted || result.now_head!=255)
            return result;
        if (!std::isfinite(result.signed_curl_feedback) ||
            !std::isfinite(result.radial_distance) ||
            std::fabs(result.signed_curl_feedback)>8.0f ||
            result.radial_distance>8.0f)
            throw std::logic_error("out-of-contract hyperedge feedback");
        Tensor256Address direction{},reverse{};
        if (!vm_.tensor256_dual_address(head.h,head.a,head.h,1,direction) ||
            !vm_.tensor256_dual_address(head.h,head.h,head.a,1,reverse) ||
            !direction.valid || !reverse.valid ||
            direction.byte_offset!=DualTensor256Arena::byte_offset(
                head.h,head.a,head.h,1) ||
            reverse.byte_offset!=DualTensor256Arena::byte_offset(
                head.h,head.h,head.a,1) ||
            direction.byte_offset==reverse.byte_offset)
            throw std::logic_error("native hyperedge mirror map mismatch");
        arena_.stage_native_value(head.proposer,head.h,head.a,head.h,
                                  result.signed_curl_feedback);
        arena_.stage_native_value(head.proposer,head.h,head.h,head.a,
                                  result.radial_distance);
        return result;
    }

    // Caller commits only sourced past context. Not a 48M model-weight commit.
    void commit_context(const Native48MFeedbackReceipt& receipt){
        if(!receipt.native_measured)throw std::invalid_argument("not guest measured");
        const std::array<float,kMetaDim> v=receipt.meta_features;
        if(history_.size()==16)history_.pop_front();
        history_.push_back(v);
    }
    std::size_t history_size()const noexcept{return history_.size();}
private:
    RawFieldVM& vm_;
    DualTensor256Arena& arena_;
    std::deque<std::array<float,kMetaDim>> history_;
    bool initialized_=false;
};
} // namespace nanlm
