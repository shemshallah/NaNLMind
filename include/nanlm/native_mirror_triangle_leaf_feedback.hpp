// Typed candidate-only persistence for native NaN16 palindromic/mirror curl.
// Same DualTensor256Arena, same oriented rank-3 coordinates, same source
// provenance and promotion gate as the 48M head/trihead/global/meta loop.
// This file computes NO native curls, Poincare geometry or repair predictions:
// all numeric content is copied byte-for-byte from guest receipts.
#pragma once
#include "nanlm/dual_tensor_arena.hpp"
#include "nanlm/raw_field.hpp"
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace nanlm {
struct NativeMirrorTriangleLeafStage {
    std::size_t oriented_curl_leaves=0,poincare_vector_leaves=0;
    std::uint64_t tensor_generation=0;
    std::uint16_t hot_majority=0,cold_majority=0;
    std::uint16_t unanimous_hot=0,unanimous_cold=0;
};

inline NativeMirrorTriangleLeafStage stage_native_mirror_triangle_leaves(
    DualTensor256Arena& arena,
    const std::vector<NativeMirrorTriangleReceipt>& measured,
    std::uint64_t first_logical_leaf_id,
    const std::string& externally_authenticated_source_sha256,
    bool sourced_head_triad_field_present,
    bool native_global_hodge_approved,
    bool committed_native_meta_approved) {
    if(!arena.candidate_open()||measured.size()!=510u||
       !sourced_head_triad_field_present||!native_global_hodge_approved||
       !committed_native_meta_approved)
        throw std::logic_error("mirror field requires all 510 native samples, head/trihead, Hodge, committed meta");
    if(!valid_tensor_leaf_sha256(externally_authenticated_source_sha256)||
       !first_logical_leaf_id||
       first_logical_leaf_id>std::numeric_limits<std::uint64_t>::max()-509u)
        throw std::invalid_argument("mirror triangle requires authenticated source digest and leaf range");
    // Check EVERY sample and writer capability before first leaf is staged.
    // No host rebuilds the curl or computes HOT/COLD votes.
    for(unsigned t=0;t<510u;++t){
        const auto& x=measured[t];
        const unsigned a=x.anchors[0],b=x.anchors[1],c=x.anchors[2];
        if(!x.measured||x.sample_index!=t||x.source_generation!=arena.generation()||
           x.family!=(t>=255u?1u:0u)||
           a>=255u||b>=255u||c>=255u||a==b||a==c||b==c||
           !arena.candidate_writer_allowed(a)||
           (x.hot_mask&x.cold_mask)!=0u||x.hot_mask>7u||x.cold_mask>7u||
           unsigned(x.hot_count)+unsigned(x.cold_count)>3u||
           x.majority_sign!=(x.hot_count>=2u?1:x.cold_count>=2u?-1:0)||
           x.unanimous_hot!=(x.hot_count==3u)||
           x.unanimous_cold!=(x.cold_count==3u)||
           !std::isfinite(x.loop_curl)||
           !std::isfinite(x.native_reconstruction)||
           !std::isfinite(x.native_residual)||
           x.native_record_words[0]!=a||x.native_record_words[1]!=b||
           x.native_record_words[2]!=c||x.native_record_words[26]!=arena.generation()||
           x.native_record_words[27]!=255u)
            throw std::logic_error("mirror triangle native geometry/vote/address/provenance invalid");
        if(x.projected){
            if(x.native_record_words[31]!=1u||
               !std::isfinite(x.poincare_radius)||x.poincare_radius<0.0f||
               x.poincare_radius>=1.0f||!std::isfinite(x.poincare_depth)||
               x.poincare_depth<0.0f||
               !std::isfinite(x.signed_curl_radial_feedback))
                throw std::logic_error("native mirror projected record has invalid depth or curl");
            for(float v:x.poincare_vector)
                if(!std::isfinite(v)||std::fabs(v)>1.0f)
                    throw std::logic_error("native mirror projected 128D coordinate nonfinite");
        }
    }
    NativeMirrorTriangleLeafStage result{};
    result.tensor_generation=arena.generation();
    try{
        for(unsigned t=0;t<510u;++t){
            const auto& x=measured[t];
            const unsigned a=x.anchors[0],b=x.anchors[1],c=x.anchors[2];
            TensorDataLeaf curl{};
            curl.kind=TensorLeafKind::MirrorTriangleCurl;
            curl.logical_leaf_id=first_logical_leaf_id+t;
            curl.source_generation=arena.generation();
            curl.source_sha256=externally_authenticated_source_sha256;
            curl.payload.reserve(32u*4u+1u);
            for(const std::uint32_t word:x.native_record_words)
                for(unsigned shift:{0u,8u,16u,24u})
                    curl.payload.push_back(static_cast<std::uint8_t>(word>>shift));
            curl.payload.push_back(0u); // original (a,b,c) orientation
            const bool forward=arena.attach_candidate_leaf(a,a,b,c,curl);
            curl.payload.back()=1u; // reversed (a,c,b): reorient stored L
            const bool reverse=arena.attach_candidate_leaf(a,a,c,b,curl);
            result.oriented_curl_leaves+=std::size_t(forward)+std::size_t(reverse);
            if(x.projected){
                TensorDataLeaf geometry{};
                geometry.kind=TensorLeafKind::MirrorTrianglePoincare128;
                geometry.logical_leaf_id=first_logical_leaf_id+t;
                geometry.source_generation=arena.generation();
                geometry.source_sha256=externally_authenticated_source_sha256;
                geometry.payload.resize(128u*sizeof(float));
                std::memcpy(geometry.payload.data(),x.poincare_vector.data(),
                            geometry.payload.size());
                const bool vecf=arena.attach_candidate_leaf(a,a,b,c,geometry);
                const bool vecr=arena.attach_candidate_leaf(a,a,c,b,geometry);
                result.poincare_vector_leaves+=std::size_t(vecf)+std::size_t(vecr);
            }
            result.hot_majority+=x.hot_count>=2u?1u:0u;
            result.cold_majority+=x.cold_count>=2u?1u:0u;
            result.unanimous_hot+=x.unanimous_hot?1u:0u;
            result.unanimous_cold+=x.unanimous_cold?1u:0u;
        }
    }catch(...){
        arena.abort_candidate(); // candidate leaves discarded; active intact
        throw;
    }
    return result;
}

inline bool stage_native_mirror_edge_recovery_leaf(
    DualTensor256Arena& arena,
    const NativeMirrorTriangleReceipt& original,
    const NativeMirrorTriangleRecoveryReceipt& recovered,
    std::uint64_t repair_logical_leaf_id,
    const std::string& externally_authenticated_source_sha256) {
    if(!arena.candidate_open()||!original.measured||
       !recovered.accepted||!repair_logical_leaf_id||
       original.source_generation!=arena.generation()||
       recovered.source_generation!=arena.generation()||
       !valid_tensor_leaf_sha256(externally_authenticated_source_sha256)||
       !std::isfinite(recovered.reconstructed_edge)||
       !std::isfinite(recovered.current_edge)||
       !std::isfinite(recovered.residual))
        throw std::logic_error("candidate repair must be a native current-epoch observation");
    const unsigned a=original.anchors[0],b=original.anchors[1],c=original.anchors[2];
    if(a>=255u||b>=255u||c>=255u||a==b||a==c||b==c||
       !arena.candidate_writer_allowed(a))
        throw std::logic_error("mirror candidate repair writer/address invalid");
    TensorDataLeaf leaf{};
    leaf.kind=TensorLeafKind::MirrorTriangleRepair;
    leaf.logical_leaf_id=repair_logical_leaf_id;
    leaf.source_generation=arena.generation();
    leaf.source_sha256=externally_authenticated_source_sha256;
    const auto append=[&](std::uint32_t word){
        for(unsigned shift:{0u,8u,16u,24u})
            leaf.payload.push_back(static_cast<std::uint8_t>(word>>shift));
    };
    for(float value:{recovered.reconstructed_edge,recovered.current_edge,
                     recovered.residual}){
        std::uint32_t bits=0;std::memcpy(&bits,&value,sizeof(bits));append(bits);
    }
    append(recovered.source_generation);
    // REPAIR RECORD only; never write the active mirrored edge directly.
    return arena.attach_candidate_leaf(a,a,b,c,leaf);
}
} // namespace nanlm
