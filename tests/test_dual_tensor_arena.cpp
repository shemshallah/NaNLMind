#include "nanlm/dual_tensor_arena.hpp"
#include <cassert>
#include <iostream>
#include <stdexcept>
using nanlm::DualTensor256Arena;
using nanlm::TensorMetaGate;
int main(){
 const std::string base(64,'a'),overlay(64,'b');
 DualTensor256Arena a(base,overlay);
 assert(a.byte_offset(0,0,0,0)==0);
 assert(a.byte_offset(0,0,1,0)==1024);
 assert(a.byte_offset(0,1,0,0)==1028);
 assert(a.byte_offset(0,0,1,1)==67108864u+1024);
 for(unsigned h=0;h<255;++h) assert(a.byte_offset(h,2,3,1)+4==a.byte_offset(h,3,2,1));
 a.begin_candidate();
 bool denied=false;
 try{a.stage_native_value(3,3,1,2,1.f);}catch(const std::logic_error&){denied=true;}
 assert(denied);
 a.set_writer_permission(3,true);
 a.set_writer_permission(6,true);
 a.stage_native_value(3,3,1,2,3.f);
 a.stage_native_value(6,3,2,1,-7.f);
 assert(a.candidate(3,1,2)==3.f && a.candidate(3,2,1)==-7.f);
 assert(a.active(3,1,2)==0.f);
 TensorMetaGate good;
 good.base_sha256=base;good.overlay_sha256=overlay;
 good.baseline_nll=6.3;good.candidate_nll=6.2;
 good.global_approved=true;good.meta_approved=true;
 for(unsigned i=0;i<43;++i)good.triad_votes[i]=3;
 auto result=a.decide(good);
 assert(result.promoted && result.accepted_triads==43 && result.generation==1);
 assert(a.active(3,1,2)==3.f && a.active(3,2,1)==-7.f);
 a.begin_candidate();a.stage_native_value(3,3,1,2,123.f);
 auto bad=good;bad.candidate_nll=6.5;
 assert(!a.decide(bad).promoted && a.active(3,1,2)==3.f);
 a.begin_candidate();a.stage_native_value(3,3,1,2,999.f);
 bad=good;bad.overlay_sha256=std::string(64,'c');
 assert(!a.decide(bad).promoted && a.active(3,1,2)==3.f);
 a.begin_candidate();
 bool blocked=false;
 try{a.stage_native_value(3,255,1,1,1.f);}catch(const std::out_of_range&){blocked=true;}
 assert(blocked);a.abort_candidate();
 std::cout<<"PASS 128MiB mirrored tensor, candidate authorization, NLL/triad/meta promotion\n";
}
