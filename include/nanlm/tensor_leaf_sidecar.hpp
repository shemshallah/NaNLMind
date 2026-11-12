// Typed DATA LEAF attachment to the ONE canonical 256^3 mirrored tensor.
// The float32 tensor stores native numerical measurements; leaf attachments
// carry heterogeneous bytes (word/definition/relation/vector/corpus evidence)
// without coercing their meaning into floats or fragmenting the model.
// Indexed by the EXACT SAME directed h,a,b coordinate and generation.
// This header is representation/storage ONLY. Math remains in NaN16 guests.
#pragma once
#include "nanlm/nlhe2.hpp"
#include <cstdint>
#include <string>
#include <vector>

namespace nanlm {
enum class TensorLeafKind : std::uint8_t {
    HeadVector128=1,
    TriheadVector128=2,
    HyperedgeRelation=3,
    LexicalWord=4,
    Definition=5,
    CorpusEvidence=6,
    BooleanTruthTable=7,
    TemporalContext=8,
    MirrorTriangleCurl=9,        // 32 native U32 words + orientation byte
    MirrorTrianglePoincare128=10, // 128 native F32 coordinates
    MirrorTriangleRepair=11,      // candidate ghat,g observed,residual,epoch
    HyperedgeRecordV2=12,         // canonical NLHE2 topology record
};
struct TensorDataLeaf {
    TensorLeafKind kind=TensorLeafKind::CorpusEvidence;
    std::uint64_t logical_leaf_id=0;
    std::uint64_t source_generation=0;
    // Externally authenticated source SHA-256 (checked at boundary).
    // This stored digest is not in itself a signature or provenance proof.
    std::string source_sha256;
    std::vector<std::uint8_t> payload;
    bool operator==(const TensorDataLeaf& x) const {
        return kind==x.kind && logical_leaf_id==x.logical_leaf_id &&
            source_generation==x.source_generation &&
            source_sha256==x.source_sha256 && payload==x.payload;
    }
};
inline bool valid_tensor_leaf_sha256(const std::string& digest) {
    if(digest.size()!=64)return false;
    for(char c:digest) {
        if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')))return false;
    }
    return true;
}
inline bool valid_tensor_leaf_payload(const TensorDataLeaf& leaf) {
    if(!valid_tensor_leaf_sha256(leaf.source_sha256) ||
       leaf.payload.empty()||leaf.payload.size()>65536u)return false;
    const unsigned k=static_cast<unsigned>(leaf.kind);
    if(k<1u||k>12u)return false;
    if(leaf.kind==TensorLeafKind::HyperedgeRecordV2)
        return valid_nlhe2_payload(leaf.payload);
    if((leaf.kind==TensorLeafKind::HeadVector128 ||
        leaf.kind==TensorLeafKind::TriheadVector128 ||
        leaf.kind==TensorLeafKind::MirrorTrianglePoincare128) &&
       leaf.payload.size()!=128u*sizeof(float))return false;
    if(leaf.kind==TensorLeafKind::MirrorTriangleCurl &&
       leaf.payload.size()!=32u*sizeof(std::uint32_t)+1u)return false;
    if(leaf.kind==TensorLeafKind::MirrorTriangleRepair &&
       leaf.payload.size()!=4u*sizeof(std::uint32_t))return false;
    if(leaf.kind==TensorLeafKind::BooleanTruthTable &&
       leaf.payload.size()!=2u)return false;
    return true;
}
} // namespace nanlm
