// Candidate-only typed child data leaves share the EXACT directed
// 256^3 tensor index. No second universe or ersatz language model.
#include "nanlm/dual_tensor_arena.hpp"
#include <cassert>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>
using namespace nanlm;
int main() {
    const std::string base(64,'a'),overlay(64,'b'),source(64,'c');
    DualTensor256Arena arena(base,overlay);
    arena.set_writer_permission(3,true);
    TensorDataLeaf head{};
    head.kind=TensorLeafKind::HeadVector128;
    head.logical_leaf_id=41;
    head.source_generation=0;
    head.source_sha256=source;
    head.payload=std::vector<std::uint8_t>(128u*sizeof(float),0);
    head.payload[0]=12;

    arena.begin_candidate();
    assert(arena.attach_candidate_leaf(3,7,2,3,head));
    assert(!arena.attach_candidate_leaf(3,7,2,3,head));
    assert(arena.candidate_leaves(7,2,3).size()==1u);
    assert(arena.candidate_leaves(7,3,2).empty()); // mirror separate
    assert(arena.active_leaves(7,2,3).empty());
    auto conflict=head;
    conflict.payload[0]=13;
    bool rejected=false;
    try {arena.attach_candidate_leaf(3,7,2,3,conflict);}
    catch(const std::logic_error&){rejected=true;}
    assert(rejected);
    rejected=false;
    try {arena.attach_candidate_leaf(255,7,2,3,head);}
    catch(const std::logic_error&){rejected=true;}
    assert(rejected);
    rejected=false;
    try {arena.attach_candidate_leaf(4,7,2,3,head);}
    catch(const std::logic_error&){rejected=true;}
    assert(rejected);
    auto wrong_sha=head;
    wrong_sha.logical_leaf_id=42;
    wrong_sha.source_sha256="not-verified";
    rejected=false;
    try {arena.attach_candidate_leaf(3,7,2,3,wrong_sha);}
    catch(const std::invalid_argument&){rejected=true;}
    assert(rejected);
    auto wrong_epoch=head;
    wrong_epoch.logical_leaf_id=42;
    wrong_epoch.source_generation=1;
    rejected=false;
    try {arena.attach_candidate_leaf(3,7,2,3,wrong_epoch);}
    catch(const std::logic_error&){rejected=true;}
    assert(rejected);
    auto bad_vector=head;
    bad_vector.logical_leaf_id=42;
    bad_vector.payload.resize(127);
    rejected=false;
    try {arena.attach_candidate_leaf(3,7,2,3,bad_vector);}
    catch(const std::invalid_argument&){rejected=true;}
    assert(rejected);

    TensorMetaGate gate{};
    gate.base_sha256=base;
    gate.overlay_sha256=overlay;
    gate.baseline_nll=1.0;
    gate.candidate_nll=.95;
    gate.global_approved=true;
    gate.meta_approved=true;
    gate.triad_votes.fill(7);
    // Typed leaves alone cannot be promoted on a fabricated diagnostic;
    // a native tensor candidate scalar must also have been measured.
    auto result=arena.decide(gate);
    assert(!result.promoted);
    assert(result.candidate_leaf_writes==1);
    assert(arena.active_leaves(7,2,3).empty());

    // Transactional abort does not modify the active float bank or leaves.
    arena.begin_candidate();
    assert(arena.attach_candidate_leaf(3,7,2,3,head));
    arena.stage_native_value(3,7,2,3,0.25f);
    gate.meta_approved=false;
    result=arena.decide(gate);
    assert(!result.promoted);
    assert(arena.active(7,2,3)==0);
    assert(arena.active_leaves(7,2,3).empty());

    // This is a STORAGE GATE UNIT TEST with artificial loss values,
    // explicitly NOT evidence of real 48M model improvement.
    arena.begin_candidate();
    assert(arena.attach_candidate_leaf(3,7,2,3,head));
    arena.stage_native_value(3,7,2,3,0.25f);
    gate.meta_approved=true;
    result=arena.decide(gate);
    assert(result.promoted && result.generation==1u);
    assert(result.candidate_leaf_writes==1u);
    assert(arena.active(7,2,3)==0.25f);
    assert(arena.active_leaves(7,2,3).size()==1u);
    assert(arena.active_leaves(7,3,2).empty());
    assert(arena.active_leaves(7,2,3).at(0)==head);

    // A separate typed definition and Boolean leaf may coexist at the
    // SAME oriented index, without changing the scalar or older vector.
    arena.begin_candidate();
    TensorDataLeaf definition{};
    definition.kind=TensorLeafKind::Definition;
    definition.logical_leaf_id=55;
    definition.source_generation=1;
    definition.source_sha256=source;
    definition.payload={0x70,0x65,0x6e,0x67,0x75,0x69,0x6e};
    assert(arena.attach_candidate_leaf(3,7,2,3,definition));
    assert(arena.candidate_leaves(7,2,3).size()==2u);
    assert(arena.active_leaves(7,2,3).size()==1u);
    arena.abort_candidate();
    assert(arena.active_leaves(7,2,3).size()==1u);
    assert(arena.active(7,2,3)==0.25f);
}
