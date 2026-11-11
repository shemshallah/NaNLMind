#include "nanlm/native48m_feedback.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
#include <string>
#include <vector>

int main(){
    nanlm::RawFieldVM vm("build/field_driver.nan");
    if(!vm.ready()){std::cerr<<"native VM unavailable: "<<vm.error()<<"\n";return 1;}
    nanlm::DualTensor256Arena arena(std::string(64,'a'),std::string(64,'b'));
    arena.set_writer_permission(3,true);
    arena.begin_candidate();
    nanlm::Native48MFeedbackBridge bridge(vm,arena);
    bridge.reset_native_session();
    std::array<float,32640> initial_flow{};
    auto first=bridge.measure_and_stage(
        {'a','b','c'},{1,2,3,4},3,7,2,3,initial_flow,{});
    assert(first.native_measured);
    assert(first.native_observed_contexts==4u);
    assert(!first.meta_available && !first.candidate_staged);
    assert(first.committed_history_slots==0);
    bridge.commit_context(first);
    assert(bridge.history_size()==1u);

    // The face and its oriented flows are explicit upstream evidence,
    // NOT inferred from a synthetic tensor symmetry.
    std::array<float,32640> measured_flows{};
    measured_flows[0]=1.0f;   // directed 0 -> 1
    measured_flows[255]=1.0f; // directed 1 -> 2
    measured_flows[1]=-1.0f;  // directed 2 -> 0
    auto second=bridge.measure_and_stage(
        {'d','e','f'},{5,6,7,8},3,7,2,3,measured_flows,{{0,1,2}});
    assert(second.native_measured && second.meta_available);
    assert(second.candidate_staged && second.committed_history_slots==1u);
    assert(second.has_admitted_faces && std::fabs(second.curl[0]-3.0f)<1e-5f);
    // Global and trihead measurements enter the actual 20D meta query,
    // not merely unused side diagnostics.
    assert(std::fabs(second.meta_features[19]-3.0f)<1e-5f);
    assert(second.meta_features[18]==second.divergence[7]);
    assert(second.meta_features[16]==static_cast<float>(second.field_q16)/65536.0f);
    assert(second.meta_features[17]==static_cast<float>(second.head_credits[3])/65536.0f);
    assert(second.meta_features[19]!=first.meta_features[19]);
    assert(std::isfinite(second.native_log_weight));
    assert(std::fabs(second.native_log_weight)<=8.0f);
    assert(arena.candidate(7,2,3)==second.native_log_weight);
    assert(arena.active(7,2,3)==0.0f);
    assert(arena.candidate(7,3,2)==0.0f); // opposite mirror is independent
    assert(second.accepted_triads<=85);
    assert(second.native_observed_contexts==4u);
    // Every one of the 255 heads (including head 0) can be leased to write
    // its OWN candidate coordinate. The mirror direction remains untouched.
    arena.set_all_candidate_writer_permissions(true);
    auto triads=nanlm::Native48MFeedbackBridge::canonical_triheads();
    assert(arena.candidate_writer_allowed(0));
    assert(arena.candidate_writer_allowed(254));
    std::size_t actual_nonzero=0;
    for(auto c:second.head_credits)if(c!=0)++actual_nonzero;
    const auto staged=bridge.stage_all_trihead_candidate_credits(second,triads);
    assert(staged==actual_nonzero);
    assert(staged<=255);
    for(std::size_t t=0;t<85;++t)for(std::size_t k=0;k<3;++k){
        const unsigned head=triads[t][k], a=triads[t][(k+1)%3], b=triads[t][(k+2)%3];
        const float expected=static_cast<float>(second.head_credits[head])/65536.0f;
        if(second.head_credits[head]!=0)
            assert(arena.candidate(head,a,b)==expected);
        assert(arena.active(head,a,b)==0.0f);
        assert(arena.candidate(head,b,a)==0.0f);
    }
    auto malformed=triads;
    malformed[84][2]=3;  // duplicate 3, absent head 254
    bool invalid_mapping=false;
    try{bridge.stage_all_trihead_candidate_credits(second,malformed);}
    catch(const std::invalid_argument&){invalid_mapping=true;}
    assert(invalid_mapping);
    // All seven MTH credit methods act through the ORIGINAL guest kernel
    // bundle, with TCA additionally sourced from the frozen decoder's
    // exact-word score difference (signed Q16). Fixture values are NOT
    // training evidence, so the global/heldout commit stays blocked.
    nanlm::CreditBundleState src{};
    src.cft={0,0,0,65536,39321};
    src.trail={0x8000,0x6666,0x4CCC,0x3333,0x1999,
               0x1999,0x3333,0x0CCC,0x051E,0xE666,0xCCCC};
    src.holo={0,8192,8192};
    src.ring_phases.fill(0); src.ring_shift=0;
    src.leaf={15,3,100};
    src.flux={0,65536,32768,0};
    const std::array<std::int32_t,7> coefficients={
        8192,8192,8192,8192,8192,8192,8192};
    const auto seven=bridge.stage_seven_credit_feedback(
        second,src,-65536,-32768,coefficients);
    for(auto c:seven.native_credits_q16)assert(c!=0);
    assert(seven.native_credits_q16[5]==32768);
    assert(std::isfinite(seven.staged_tensor_value));
    assert(arena.candidate(7,2,3)==seven.staged_tensor_value);
    assert(arena.candidate(7,3,2)==0.0f);
    assert(arena.active(7,2,3)==0.0f);
    bridge.commit_context(second);
    assert(bridge.history_size()==2u);
    // The spectral path also runs through the SAME loaded native driver, not
    // a substitute Python/C++ spectral predictor or a second tensor.
    std::array<std::int64_t,256> spectral_credit{};
    spectral_credit[1]=65536;
    std::array<std::uint8_t,85> spectral_votes{};
    spectral_votes.fill(7);
    std::array<std::array<std::uint8_t,2>,255> directed_pairs{};
    directed_pairs[1]={1,2};
    std::array<std::uint8_t,255> capabilities{};
    capabilities[1]=1;
    arena.set_writer_permission(1,true);
    nanlm::NativeSpectralTensorResult spectral_result{};
    assert(vm.native_spectral_tensor_propose(
        spectral_credit,spectral_votes,directed_pairs,capabilities,
        0,0,true,true,spectral_result));
    assert(spectral_result.accepted && spectral_result.accepted_triads==85);
    assert(spectral_result.records.size()==1u);
    const auto record=spectral_result.records.front();
    assert(record.head==1 && record.a==1 && record.b==2);
    assert(record.candidate_byte_offset==
           nanlm::DualTensor256Arena::byte_offset(1,1,2,1));
    assert(record.credit_q16==65536);
    // This is an ABI-only transfer; credit came from the NaN16 guest.
    arena.stage_native_value(record.head,record.head,record.a,record.b,
                             static_cast<float>(record.credit_q16)/65536.0f);
    assert(arena.candidate(1,1,2)==1.0f);
    assert(arena.active(1,1,2)==0.0f);
    assert(arena.candidate(1,2,1)==0.0f);
    nanlm::NativeSpectralTensorResult stale_spectral{};
    assert(vm.native_spectral_tensor_propose(
        spectral_credit,spectral_votes,directed_pairs,capabilities,
        1,0,true,true,stale_spectral));
    assert(!stale_spectral.accepted && stale_spectral.records.empty());
    assert(stale_spectral.rejection_reason==1);
    assert(arena.candidate(1,1,2)==1.0f);
    // This is a real native calculation but not a held-out quality gate:
    // unknown NLL must reject promotion.
    nanlm::TensorMetaGate gate;
    gate.base_sha256=std::string(64,'a');
    gate.overlay_sha256=std::string(64,'b');
    gate.triad_votes=second.triad_votes;
    gate.global_approved=second.has_admitted_faces;
    gate.meta_approved=second.meta_available;
    const auto result=arena.decide(gate);
    assert(!result.promoted && result.generation==0);
    assert(arena.active(7,2,3)==0.0f);
    std::cout<<"PASS native phase -> cumulative triheads -> Hodge -> committed MC0 -> mirrored candidate; no unvalidated promotion\n";
    return 0;
}
