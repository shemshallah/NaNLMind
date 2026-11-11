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
    bridge.commit_context(second);
    assert(bridge.history_size()==2u);
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
