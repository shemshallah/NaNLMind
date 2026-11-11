// Head/trihead-to-tensor/typed-leaf transport for the ORIGINAL 48M hybrid.
// Numerical values are guest outputs; host only validates source, routes
// addresses, serializes typed payloads and stages CANDIDATE data.
#pragma once
#include "nanlm/raw_field.hpp"
#include "nanlm/dual_tensor_arena.hpp"
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <limits>
#include <string>
#include <vector>
namespace nanlm {
struct NativeHeadLeafStage {
    std::uint8_t proposer=255;
    std::size_t numerical_writes=0,typed_leaf_attachments=0;
    std::uint64_t generation=0;
};
// One independent head h stores its scalar curl evidence at T[h,h,h]
// (private diagonal slot), and the full 128D measured Poincare vector
// plus candidate Boolean operator truth mask as distinct typed DATA LEAVES
// of precisely that same oriented tensor coordinate.
inline NativeHeadLeafStage stage_native_head_leaf_candidate(
    DualTensor256Arena& arena,const NativeHead16Receipt& measured,
    std::uint64_t vector_leaf_id,const std::string& source_sha256) {
    if(!measured.accepted||measured.head>=255||
       measured.candidate_truth_mask==0u||
       !std::isfinite(measured.signed_curl_feedback)||
       !std::isfinite(measured.radial_distance)||!arena.candidate_open()||
       measured.source_generation!=arena.generation()||
       !arena.candidate_writer_allowed(measured.head))
        throw std::logic_error("head candidate requires native measurement, generation and lease");
    if(!valid_tensor_leaf_sha256(source_sha256))
        throw std::invalid_argument("unverified head source digest encoding");
    TensorDataLeaf vec{};
    vec.kind=TensorLeafKind::HeadVector128;
    vec.logical_leaf_id=vector_leaf_id;
    vec.source_generation=arena.generation();
    vec.source_sha256=source_sha256;
    vec.payload.resize(measured.poincare_vector.size()*sizeof(float));
    std::memcpy(vec.payload.data(),measured.poincare_vector.data(),vec.payload.size());
    TensorDataLeaf rule{};
    rule.kind=TensorLeafKind::BooleanTruthTable;
    rule.logical_leaf_id=vector_leaf_id;
    rule.source_generation=vec.source_generation;
    rule.source_sha256=vec.source_sha256;
    rule.payload={
        static_cast<std::uint8_t>(measured.candidate_truth_mask&0xFFu),
        static_cast<std::uint8_t>(measured.candidate_truth_mask>>8u)};
    const auto h=static_cast<unsigned>(measured.head);
    // Explicit same-coordinate sidecar for MORE than scalar measurements.
    // This is NOT a commit. Caller aborts candidate on any exception.
    const bool fresh_vector=arena.attach_candidate_leaf(h,h,h,h,vec);
    const bool fresh_rule=arena.attach_candidate_leaf(h,h,h,h,rule);
    arena.stage_native_value(h,h,h,h,measured.signed_curl_feedback);
    return {measured.head,1u,
            std::size_t(fresh_vector)+std::size_t(fresh_rule),arena.generation()};
}
// One dynamically mapped 3-head triangle stages SIGNED credit gradient in
// T[h,a,a], native Poincare depth in T[h,b,b], preserving existing numerical
// T[h,a,b] and T[h,b,a] head/temporal measurements. The directed pair carries
// a typed 128D TRIHEAD vector leaf and oriented HYPEREDGE relation record. No scalar
// numerical operation runs on the host; 2/3 and 3/3 votes are guest-owned.
inline NativeHeadLeafStage stage_native_triad_leaf_candidate(
    DualTensor256Arena& arena,const NativeTrihead128Receipt& triad,
    std::uint64_t vector_leaf_id,const std::string& source_sha256) {
    if(!triad.accepted||triad.triad>=85||
       unsigned(triad.hot_count)+unsigned(triad.cold_count)!=3u||
       triad.majority_sign!=(triad.hot_count>=2?1:-1)||
       triad.unanimous_hot!=(triad.hot_count==3)||
       triad.unanimous_cold!=(triad.cold_count==3)||
       !std::isfinite(triad.candidate_credit_gradient)||
       !std::isfinite(triad.radial_distance)||
       !arena.candidate_open()||
       triad.source_generation!=arena.generation())
        throw std::logic_error("native trihead vote/geometry not admissible");
    const auto h=static_cast<unsigned>(triad.members[0]);
    const auto a=static_cast<unsigned>(triad.members[1]);
    const auto b=static_cast<unsigned>(triad.members[2]);
    if(h>=255||a>=255||b>=255||h==a||h==b||a==b||
       !arena.candidate_writer_allowed(h))
        throw std::logic_error("trihead mapping or representative lease invalid");
    if(!valid_tensor_leaf_sha256(source_sha256))
        throw std::invalid_argument("invalid trihead source digest encoding");
    TensorDataLeaf vec{};
    vec.kind=TensorLeafKind::TriheadVector128;
    vec.logical_leaf_id=vector_leaf_id;
    vec.source_generation=arena.generation();
    vec.source_sha256=source_sha256;
    vec.payload.resize(triad.poincare_vector.size()*sizeof(float));
    std::memcpy(vec.payload.data(),triad.poincare_vector.data(),vec.payload.size());
    // Native voted topology and signs are retained as their own typed
    // provenance-bearing leaf, never guessed from a float tensor value.
    TensorDataLeaf edge{};
    edge.kind=TensorLeafKind::HyperedgeRelation;
    edge.logical_leaf_id=vector_leaf_id;
    edge.source_generation=vec.source_generation;
    edge.source_sha256=vec.source_sha256;
    edge.payload={triad.members[0],triad.members[1],triad.members[2],
        triad.hot_count,triad.cold_count,
        static_cast<std::uint8_t>(triad.unanimous_hot?1u:0u),
        static_cast<std::uint8_t>(triad.unanimous_cold?1u:0u)};
    auto append_raw=[&](float value) {
        std::uint32_t bits=0;
        static_assert(sizeof(bits)==sizeof(value));
        std::memcpy(&bits,&value,4);
        for(unsigned shift: {0u,8u,16u,24u})
            edge.payload.push_back(static_cast<std::uint8_t>(bits>>shift));
    };
    append_raw(triad.candidate_credit_gradient);
    append_raw(triad.signed_curl_feedback);
    append_raw(triad.radial_distance);
    const bool fresh_vec=arena.attach_candidate_leaf(h,h,a,b,vec);
    const bool fresh_edge=arena.attach_candidate_leaf(h,h,b,a,edge);
    // Dedicated typed numerical slots: do not erase preexisting CFT,
    // temporal or seven-credit values at the oriented triangle coordinates.
    arena.stage_native_value(h,h,a,a,triad.candidate_credit_gradient);
    arena.stage_native_value(h,h,b,b,triad.radial_distance);
    return {static_cast<std::uint8_t>(h),2u,
            std::size_t(fresh_vec)+std::size_t(fresh_edge),arena.generation()};
}
// One unified candidate-only storage path for the WHOLE native field, not
// 3 heads plus 84 artificial votes. No new model, no second state space.
// Each head's independently measured Boolean truth and Poincare128 vector,
// and each of the 85 trihead geometry/gradient/HOT/COLD records, is stored
// at the ORIGINAL directed rank-3 mirrored tensor's exact data leaf index.
// Real authenticated Hodge/MC0 gates must be supplied by the controller;
// these booleans are admission interfaces, NOT cryptographic attestation.
// True promotion still requires the existing disjoint 48M whole-word NLL
// comparison, source identity and transaction journal outside this helper.
struct NativeFullFieldLeafStage {
    std::size_t head_writes=0,trihead_writes=0,typed_leaf_writes=0;
    std::uint64_t generation=0;
};
inline NativeFullFieldLeafStage stage_native_full_field_candidate_leaves(
    DualTensor256Arena& arena, const NativeFullField128Receipt& field,
    std::uint64_t first_head_leaf_id,std::uint64_t first_triad_leaf_id,
    const std::string& externally_verified_source_sha256,
    bool externally_validated_global_hodge,
    bool externally_validated_committed_meta) {
    if(!arena.candidate_open()||!field.accepted||!field.field_hot||
       field.hot_majority_triads<43u||field.head_count!=255u||
       field.triad_count!=85u||
       field.source_generation!=arena.generation()||
       !externally_validated_global_hodge||
       !externally_validated_committed_meta)
        throw std::logic_error("full-field stage requires live 255/85 guest, quorum, Hodge, meta, epoch");
    if(!valid_tensor_leaf_sha256(externally_verified_source_sha256)||
       !first_head_leaf_id||!first_triad_leaf_id||
       first_head_leaf_id>std::numeric_limits<std::uint64_t>::max()-254u||
       first_triad_leaf_id>std::numeric_limits<std::uint64_t>::max()-84u)
        throw std::invalid_argument("full field requires authenticated digest and bounded leaf IDs");
    // All-or-nothing *validation* before the first 128MiB candidate write.
    // Existing store aborts on any later exception (active remains intact).
    std::array<bool,255> seen{};
    for(std::size_t i=0;i<255u;++i){
        const auto h=field.mapping[i];
        if(h>=255u||seen[h])
            throw std::logic_error("full field mapping repeats or uses VOID255");
        seen[h]=true;
        if(!arena.candidate_writer_allowed(h))
            throw std::logic_error("full field member lacks writer lease");
        const auto& measured=field.heads[h];
        if(!measured.accepted||measured.head!=h||
           measured.source_generation!=arena.generation()||
           measured.hot_vote>1u||measured.candidate_truth_mask==0u||
           !std::isfinite(measured.signed_curl_feedback)||
           !std::isfinite(measured.radial_distance))
            throw std::logic_error("full field has incomplete native head evidence");
    }
    for(std::size_t t=0;t<85u;++t){
        const auto& triad=field.triheads[t];
        if(!triad.accepted||triad.triad!=t||
           triad.source_generation!=arena.generation()||
           triad.members[0]!=field.mapping[3u*t]||
           triad.members[1]!=field.mapping[3u*t+1u]||
           triad.members[2]!=field.mapping[3u*t+2u]||
           triad.hot_count>3u||triad.cold_count>3u||
           triad.hot_count+triad.cold_count!=3u||
           !std::isfinite(triad.candidate_credit_gradient)||
           !std::isfinite(triad.radial_distance))
            throw std::logic_error("full field has incomplete native trihead evidence");
        const auto actual=unsigned(field.heads[triad.members[0]].hot_vote)|
            (unsigned(field.heads[triad.members[1]].hot_vote)<<1u)|
            (unsigned(field.heads[triad.members[2]].hot_vote)<<2u);
        if(actual!=field.native_vote_masks[t])
            throw std::logic_error("full field supplied vote is not measured");
    }
    NativeFullFieldLeafStage result{};
    result.generation=arena.generation();
    try{
        for(unsigned h=0;h<255u;++h){
            const auto staged=stage_native_head_leaf_candidate(
                arena,field.heads[h],first_head_leaf_id+h,
                externally_verified_source_sha256);
            result.head_writes+=staged.numerical_writes;
            result.typed_leaf_writes+=staged.typed_leaf_attachments;
        }
        for(unsigned t=0;t<85u;++t){
            const auto staged=stage_native_triad_leaf_candidate(
                arena,field.triheads[t],first_triad_leaf_id+t,
                externally_verified_source_sha256);
            result.trihead_writes+=staged.numerical_writes;
            result.typed_leaf_writes+=staged.typed_leaf_attachments;
        }
    }catch(...){
        arena.abort_candidate(); // active bank AND data leaves stay unchanged
        throw;
    }
    return result;
}
} // namespace nanlm
