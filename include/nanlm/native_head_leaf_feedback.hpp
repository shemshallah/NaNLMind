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
} // namespace nanlm
