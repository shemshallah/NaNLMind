// One real NaN0S/NaN16 VM and ONE canonical 128MiB active/candidate tensor.
// Full native 510 sampled palindrome/mirror triangles, 128D Poincare
// coupling, HOT/COLD 2/3 and 3/3, erasure recovery, typed data leaves.
// The fixture's source flows/leases and Hodge/meta booleans are CONTROLLED
// TEST inputs, not evidence of a learned or authenticated corpus update.
#include "nanlm/native_mirror_triangle_leaf_feedback.hpp"
#include "nanlm/native_head_leaf_feedback.hpp"
#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>
using namespace nanlm;

int main(){
    RawFieldVM vm("build/field_driver.nan");
    if(!vm.ready()){std::cerr<<"NaN16 native mirror driver unavailable: "<<vm.error()<<"\n";return 1;}
    bool booted=false;std::uint8_t reason=0;
    assert(vm.native_mirror_triangle_boot(0xD00Du,0,booted,reason));
    assert(booted && reason==0);
    booted=true;reason=0;
    assert(vm.native_mirror_triangle_boot(42u,0,booted,reason));
    assert(!booted && reason==2); // same guest cannot resample at runtime

    std::array<float,32640> pair_flows{};
    pair_flows[0]=1.0f;pair_flows[1]=-3.0f;pair_flows[255]=2.0f;
    pair_flows[256]=2.0f;pair_flows[509]=-1.0f;
    pair_flows[2505]=-1.0f;pair_flows[2750]=-1.0f;
    pair_flows[2506]=2.0f;
    std::vector<NativeMirrorTriangleReceipt> triangles;
    std::uint16_t hot_field=0;
    bool measured=false;reason=0;
    assert(vm.native_mirror_triangle_measure(pair_flows,0,0,triangles,
                                            hot_field,measured,reason));
    assert(measured && reason==0 && triangles.size()==510u);
    assert(triangles[0].anchors==(
        std::array<std::uint8_t,3>{0,1,2}));
    assert(triangles[0].hot_count==3 && triangles[0].cold_count==0);
    assert(triangles[0].hot_mask==7 && triangles[0].cold_mask==0);
    assert(triangles[0].unanimous_hot && !triangles[0].unanimous_cold);
    assert(triangles[0].loop_curl==6.0f);
    assert(triangles[0].palindrome_addresses[0]==0x0000u);
    assert(triangles[0].palindrome_addresses[1]==0x8001u);
    assert(triangles[0].palindrome_addresses[2]==0x4002u);
    assert(triangles[0].directed_mirror_addresses==(
        std::array<std::uint16_t,6>{0x0001u,0x8000u,0x8002u,
                                    0x4001u,0x4000u,0x0002u}));
    assert(triangles[1].hot_count==1 && triangles[1].cold_count==2);
    assert(triangles[1].majority_sign==-1);
    assert(triangles[10].unanimous_cold);
    assert(triangles[254].anchors==(
        std::array<std::uint8_t,3>{254,0,1}));
    assert(triangles[255].family==1 && triangles[255].anchors[0]==0);
    assert(triangles[255].anchors[1]>=32 && triangles[255].anchors[1]<=95);
    assert(triangles[255].anchors[2]>=128 && triangles[255].anchors[2]<=191);
    assert(hot_field>=1);

    // Use the SAME independently scratched NaN16 head16 Poincare kernel
    // whose vectors feed the native 85-trihead field in production.
    std::array<float,128> head_source{};
    head_source[0]=1.0f;head_source[127]=0.5f;
    for(unsigned h=0;h<3;++h){
        NativeHead16Receipt head{};
        assert(vm.native_head16_vector(static_cast<std::uint8_t>(h),
            head_source,64,0,1,0,true,{0,1,2},0.5f,1024,0,0,head));
        assert(head.accepted && head.head==h && head.radius>0.0f);
    }
    assert(vm.native_mirror_triangle_project(0,0,triangles[0]));
    assert(triangles[0].projected && triangles[0].poincare_radius>0.0f);
    assert(triangles[0].poincare_radius<1.0f);
    assert(triangles[0].poincare_depth>0.0f);
    assert(triangles[0].signed_curl_radial_feedback>0.0f);
    assert(triangles[0].native_record_words[31]==1u);

    DualTensor256Arena arena(std::string(64,'a'),std::string(64,'b'));
    arena.set_all_candidate_writer_permissions(true);
    arena.begin_candidate();
    const std::string fixture_digest(64,'c');
    const auto staged=stage_native_mirror_triangle_leaves(
        arena,triangles,100000u,fixture_digest,
        true,true,true); // mock admission flags, no production authentication
    assert(staged.oriented_curl_leaves==1020u);
    assert(staged.poincare_vector_leaves==2u);
    assert(staged.unanimous_hot>=1u && staged.unanimous_cold>=1u);
    assert(staged.hot_majority==hot_field);
    assert(arena.candidate_leaves(0,1,2).size()==2u);
    assert(arena.candidate_leaves(0,2,1).size()==2u);
    assert(arena.candidate_leaves(0,1,2)[0].kind==TensorLeafKind::MirrorTriangleCurl);
    assert(arena.candidate_leaves(0,1,2)[0].payload.back()==0);
    assert(arena.candidate_leaves(0,2,1)[0].payload.back()==1);
    assert(arena.candidate_leaves(0,1,2)[1].kind==TensorLeafKind::MirrorTrianglePoincare128);
    assert(arena.active_leaves(0,1,2).empty());
    assert(arena.active_leaves(0,2,1).empty());
    assert(arena.active(0,1,2)==0.0f);

    // Deliberate directed S+/- corruption: initial g01=1, current=4.
    // Keep previously learned L=6 and two trusted other edges.
    pair_flows[0]=4.0f;
    NativeMirrorTriangleRecoveryReceipt recovered{};
    assert(vm.native_mirror_triangle_recover(0,0,pair_flows,recovered));
    assert(recovered.accepted && recovered.source_generation==0);
    assert(recovered.reconstructed_edge==1.0f);
    assert(recovered.current_edge==4.0f);
    assert(recovered.residual==3.0f);
    assert(stage_native_mirror_edge_recovery_leaf(
        arena,triangles[0],recovered,200000u,fixture_digest));
    assert(arena.candidate_leaves(0,1,2).size()==3u);
    assert(arena.active(0,1,2)==0.0f);

    NativeMirrorTriangleRecoveryReceipt stale{};
    assert(vm.native_mirror_triangle_recover(0,1,pair_flows,stale));
    assert(!stale.accepted && stale.rejection_reason==2);
    assert(arena.candidate_leaves(0,1,2).size()==3u);
    std::vector<NativeMirrorTriangleReceipt> rejected;
    bool stale_field=true;reason=0;
    assert(vm.native_mirror_triangle_measure(pair_flows,0,1,rejected,
                                            hot_field,stale_field,reason));
    assert(!stale_field && rejected.empty() && reason==2);

    // Without sourced held-out whole-word NLL, no ACTIVE tensor or
    // leaves may be promoted, irrespective of fixture geometry/quorum.
    TensorMetaGate gate{};
    gate.base_sha256=std::string(64,'a');
    gate.overlay_sha256=std::string(64,'b');
    gate.global_approved=true;gate.meta_approved=true;
    gate.triad_votes.fill(7); // FIXTURE votes, never production evidence
    const auto decision=arena.decide(gate); // NLL remains unknown
    assert(!decision.promoted && decision.generation==0);
    assert(arena.active(0,1,2)==0.0f);
    assert(arena.active_leaves(0,1,2).empty());
    std::cout<<"PASS native palindromic mirror curvature -> Poincare128 -> "
               "typed candidate tensor -> recovered edge; ACTIVE untouched\n";
}
