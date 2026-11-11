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
