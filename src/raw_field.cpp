#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <cstring>
#include <cmath>
#include <cstdlib>
#include <numeric>
#include <fstream>
#include <iterator>
#include <vector>

namespace nanlm {
namespace {
constexpr std::uint32_t kCommandBase = 0x4000;
constexpr std::uint32_t kProposalBase = 0x4001;
constexpr std::uint32_t kResultBase = 0x4010;
constexpr std::uint32_t kFieldMasks = 0x5000;
constexpr std::uint32_t kCoherencePhases = 0x6000;
constexpr std::uint32_t kHotCredits = 0x7000;
constexpr std::uint32_t kHotMapping = 0x8000;
constexpr std::uint32_t kMicroX0 = 0x7000;
constexpr std::uint32_t kMicroX1 = 0x7100;
constexpr std::uint32_t kMicroOut = 0x7200;
constexpr std::uint32_t kContextCreditArgs = 0x7300;
constexpr std::uint32_t kContextVotes = 0x7100;
constexpr std::uint32_t kContextBackoffTable = 0x40000;
constexpr std::uint32_t kContextBackoffTableWords = 32768u * 3u;
constexpr std::uint32_t kContextBackoffHist = 0x58000;
constexpr std::uint32_t kContextBackoffHistWords = 4096u;
constexpr std::uint32_t kContextBackoffCommand = 40; // separate from context-class opcode 30
std::uint64_t command_step_budget() {
    static const std::uint64_t budget = []() -> std::uint64_t {
        const char* text = std::getenv("NANLM_STEP_BUDGET");
        if (!text || !*text) return 4'000'000'000ull;
        try {
            const std::uint64_t value = std::stoull(text);
            return value == 0 ? 4'000'000'000ull : value;
        } catch (...) {
            return 4'000'000'000ull;
        }
    }();
    return budget;
}
constexpr std::uint32_t kContextTableBase = 0x100000;
constexpr std::uint32_t kContextWordsPerBucket = 272;
constexpr std::uint32_t kGuestWordCount = 0x400000;

void bump_triad_credit(std::int16_t& value, int delta) {
    const int next = static_cast<int>(value) + delta;
    value = static_cast<std::int16_t>(std::max(-32768, std::min(32767, next)));
}

constexpr std::uint32_t kContextMapBase = 0x60000u;
constexpr std::uint32_t kContextCopyBase = 0x80000u;
constexpr std::uint32_t kContextMapSlots = 16384u;
constexpr std::uint32_t kContextMapWords = kContextMapSlots * 3u;
constexpr std::uint32_t kContextAuxMax = 1024u;

// Keep this byte order and mixing identical to mth_context_copy.nas.
std::uint32_t context_copy_hash(std::uint32_t key) {
    std::uint32_t hash = 2166136261u;
    for (int shift = 24; shift >= 0; shift -= 8) {
        hash = (hash ^ ((key >> shift) & 0xFFu)) * 16777619u;
    }
    return hash;
}
} // namespace

RawFieldVM::RawFieldVM(const std::string& driver_image) {
    std::ifstream in(driver_image, std::ios::binary);
    if (!in) {
        fail("cannot open raw field driver: " + driver_image);
        return;
    }
    std::string image((std::istreambuf_iterator<char>(in)),
                      std::istreambuf_iterator<char>());
    vm_ = nan_create();
    if (!vm_) {
        fail("cannot allocate NaN0S VM");
        return;
    }
    if (nan_load_text(vm_, image.data(), image.size()) != 0) {
        fail("cannot load raw field driver line " +
             std::to_string(nan_load_error(vm_)));
        nan_destroy(vm_);
        vm_ = nullptr;
    }
}

RawFieldVM::~RawFieldVM() {
    if (vm_) nan_destroy(vm_);
}

bool RawFieldVM::native_context6_attention(
    std::uint32_t observed_anchor,
    const std::array<std::uint32_t,6>& neighbors,
    std::uint8_t valid_mask, std::uint8_t task,
    std::uint32_t expected_generation, std::uint32_t current_generation,
    NativeContext6Receipt& receipt) {
    receipt = {};
    if (!vm_) return fail("native context6: VM is not loaded");
    // This is a typed ABI transport, not a new host-side embedding or
    // numerical attention. The guest performs the entire calculation.
    constexpr std::uint32_t kRequest=0x003E4000u;
    constexpr std::uint32_t kOutput=0x003E4100u;
    if (!write_word(kRequest+0,observed_anchor))
        return fail("native context6: cannot write anchor");
    for (std::uint32_t i=0;i<6;++i) {
        if (!write_word(kRequest+1+i,neighbors[i]))
            return fail("native context6: cannot write slot");
    }
    if (!write_word(kRequest+7,valid_mask) ||
        !write_word(kRequest+8,task) ||
        !write_word(kRequest+9,expected_generation) ||
        !write_word(kRequest+10,current_generation) ||
        !write_word(kRequest+11,255u) ||
        !write_word(kCommandBase,107u))
        return fail("native context6: cannot write command");
    if (!run_command()) return false;
    const auto accepted=read_word(kResultBase+0);
    const auto count=read_word(kResultBase+1);
    const auto guest_task=read_word(kResultBase+2);
    const auto reason=read_word(kResultBase+3);
    if (accepted==0u) {
        if (count!=0u||guest_task!=0u||reason<1u||reason>4u)
            return fail("native context6: malformed guest rejection");
        receipt.reason=static_cast<std::uint8_t>(reason);
        return true;
    }
    if (accepted!=1u||count==0u||count>6u||guest_task!=task||reason!=0u)
        return fail("native context6: malformed guest approval");
    const auto mask=read_word(kOutput+4);
    const auto task_out=read_word(kOutput+5);
    const auto now_head=read_word(kOutput+6);
    const auto anchor_out=read_word(kOutput+7);
    if (mask!=valid_mask||task_out!=task||now_head!=255u||
        anchor_out!=observed_anchor)
        return fail("native context6: mismatched output identity");
    auto read_f32=[&](std::uint32_t i) {
        const std::uint32_t bits=read_word(kOutput+i);
        float value=0.0f;
        static_assert(sizeof(float)==sizeof(std::uint32_t));
        std::memcpy(&value,&bits,sizeof(value));
        return value;
    };
    const float x=read_f32(0),y=read_f32(1);
    const float radial=read_f32(2),distance=read_f32(3);
    // Boundary validation, not replacement numerical model mathematics.
    if (!(std::isfinite(x)&&std::isfinite(y)&&std::isfinite(radial)&&
          std::isfinite(distance)) || radial<0.0f || radial>=1.0f ||
          distance<0.0f)
        return fail("native context6: malformed Poincare ball receipt");
    receipt.accepted=true;
    receipt.valid_count=static_cast<std::uint8_t>(count);
    receipt.task=static_cast<std::uint8_t>(task_out);
    receipt.mask=static_cast<std::uint8_t>(mask);
    receipt.now_head=static_cast<std::uint8_t>(now_head);
    receipt.observed_anchor=anchor_out;
    receipt.poincare_x=x;
    receipt.poincare_y=y;
    receipt.radius=radial;
    receipt.radial_distance=distance;
    return true;
}

bool RawFieldVM::native_stream6_attention(
    const std::vector<std::uint32_t>& source_word_ids,
    std::uint32_t target_index, std::uint8_t task,
    std::uint32_t masked_query_anchor,
    std::uint32_t expected_generation,
    std::uint32_t current_generation,
    NativeContext6Receipt& receipt) {
    receipt={};
    if (!vm_) return fail("native stream6: VM unavailable");
    if (source_word_ids.empty()||source_word_ids.size()>4096u)
        return fail("native stream6: source count out of physical bounds");
    constexpr std::uint32_t source_base=0x003E6000u;
    constexpr std::uint32_t output_base=0x003E4100u;
    for (std::uint32_t i=0;i<source_word_ids.size();++i)
        if (!write_word(source_base+i,source_word_ids[i]))
            return fail("native stream6: source transport failed");
    const std::array<std::uint32_t,6> args={
        static_cast<std::uint32_t>(source_word_ids.size()),
        target_index,task,masked_query_anchor,
        expected_generation,current_generation};
    for (std::uint32_t i=0;i<args.size();++i)
        if (!write_word(kProposalBase+i,args[i]))
            return fail("native stream6: command transport failed");
    if (!write_word(kCommandBase,109u) || !run_command())
        return fail("native stream6: fused NaN16 dispatch failed: "+error_);
    const auto accepted=read_word(kResultBase+0);
    const auto count=read_word(kResultBase+1);
    const auto actual_task=read_word(kResultBase+2);
    const auto reason=read_word(kResultBase+3);
    if (accepted==0u) {
        if(count!=0u||actual_task!=0u||reason<1u||reason>4u)
            return fail("native stream6: malformed rejection receipt");
        receipt.reason=static_cast<std::uint8_t>(reason);
        return true;
    }
    if(accepted!=1u||count==0u||count>6u||
       actual_task!=task||reason!=0u)
        return fail("native stream6: malformed approved receipt");
    const auto mask=read_word(output_base+4);
    const auto mode=read_word(output_base+5);
    const auto now=read_word(output_base+6);
    const auto anchor=read_word(output_base+7);
    if (mask==0u||mask>63u||mode!=task||now!=255u||anchor==0u||
        (task==0u&&(mask&0x38u)!=0u))
        return fail("native stream6: future/VOID/anchor mismatch");
    const auto decode=[&](std::uint32_t d){
        std::uint32_t bits=read_word(output_base+d);
        float result=0.0f;
        static_assert(sizeof(float)==4);
        std::memcpy(&result,&bits,sizeof(bits));
        return result;
    };
    const float x=decode(0),y=decode(1),r=decode(2),depth=decode(3);
    if (!(std::isfinite(x)&&std::isfinite(y)&&std::isfinite(r)&&
          std::isfinite(depth))||r<0.0f||r>=1.0f||depth<0.0f)
        return fail("native stream6: malformed Poincare output");
    receipt.accepted=true;
    receipt.valid_count=static_cast<std::uint8_t>(count);
    receipt.task=static_cast<std::uint8_t>(mode);
    receipt.mask=static_cast<std::uint8_t>(mask);
    receipt.now_head=static_cast<std::uint8_t>(now);
    receipt.observed_anchor=anchor;
    receipt.poincare_x=x;
    receipt.poincare_y=y;
    receipt.radius=r;
    receipt.radial_distance=depth;
    return true;
}

// ABI-only bridge: the NaN16 guest builds a fresh causal prefix for each
// horizon, then runs the existing CORDIC/MC0/Poincare code. The source may
// include the original 48M's own earlier generated predictions ONLY.
bool RawFieldVM::native_future3_causal_attention(
    const std::vector<std::uint32_t>& observed_word_ids,
    const std::array<std::uint32_t,3>& generated_prefix,
    std::uint8_t generated_count,
    std::uint32_t expected_generation,std::uint32_t current_generation,
    NativeContext6Receipt& receipt) {
    receipt={};
    if(!vm_)return fail("native future3: VM unavailable");
    if(observed_word_ids.empty()||observed_word_ids.size()>4096u||
       generated_count>2u)
        return fail("native future3: observed/generated count invalid");
    constexpr std::uint32_t kObserved=0x003E6000u;
    constexpr std::uint32_t kGenerated=0x003E5000u;
    constexpr std::uint32_t kRequest=0x003E4000u;
    constexpr std::uint32_t kOutput=0x003E4100u;
    for(std::uint32_t i=0;i<observed_word_ids.size();++i)
        if(!write_word(kObserved+i,observed_word_ids[i]))
            return fail("native future3: observed transport failed");
    // A future/poison value beyond generated_count may be present; the
    // native kernel is explicitly forbidden to read that position.
    for(std::uint32_t i=0;i<3u;++i)
        if(!write_word(kGenerated+i,generated_prefix[i]))
            return fail("native future3: generated transport failed");
    const std::array<std::uint32_t,4> args={
        static_cast<std::uint32_t>(observed_word_ids.size()),
        generated_count,expected_generation,current_generation};
    for(std::uint32_t i=0;i<args.size();++i)
        if(!write_word(kProposalBase+i,args[i]))
            return fail("native future3: command transport failed");
    if(!write_word(kCommandBase,112u)||!run_command())
        return fail("native future3: NaN16 dispatch failed: "+error_);
    const auto accepted=read_word(kResultBase);
    const auto count=read_word(kResultBase+1);
    const auto horizon=read_word(kResultBase+2);
    const auto reason=read_word(kResultBase+3);
    if(accepted==0u){
        if(count!=0u||horizon!=0u||reason<1u||reason>4u)
            return fail("native future3: malformed native rejection");
        receipt.reason=static_cast<std::uint8_t>(reason);
        return true;
    }
    if(accepted!=1u||count==0u||count>3u||
       horizon!=static_cast<std::uint32_t>(generated_count)+1u||reason!=0u)
        return fail("native future3: malformed horizon receipt");
    const auto mask=read_word(kOutput+4);
    const auto task=read_word(kOutput+5);
    const auto now=read_word(kOutput+6);
    const auto anchor=read_word(kOutput+7);
    if(mask==0u||mask>7u||task!=0u||now!=255u||anchor==0u||
       mask!=read_word(kRequest+7)||read_word(kRequest+0)!=anchor||
       read_word(kRequest+4)!=0u||read_word(kRequest+5)!=0u||
       read_word(kRequest+6)!=0u||read_word(kRequest+8)!=0u)
        return fail("native future3: causal future leakage or NOW mismatch");
    const auto decode=[&](std::uint32_t offset){
        const std::uint32_t bits=read_word(kOutput+offset);
        float value=0.0f;
        std::memcpy(&value,&bits,sizeof(value));
        return value;
    };
    const float x=decode(0),y=decode(1),radius=decode(2),depth=decode(3);
    if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(radius)||
       !std::isfinite(depth)||radius<0.0f||radius>=1.0f||depth<0.0f)
        return fail("native future3: malformed guest Poincare measurement");
    receipt.accepted=true;
    receipt.valid_count=static_cast<std::uint8_t>(count);
    receipt.task=0;
    receipt.horizon=static_cast<std::uint8_t>(horizon);
    receipt.mask=static_cast<std::uint8_t>(mask);
    receipt.now_head=255;
    receipt.observed_anchor=anchor;
    receipt.poincare_x=x;
    receipt.poincare_y=y;
    receipt.radius=radius;
    receipt.radial_distance=depth;
    return true;
}

bool RawFieldVM::native_head16_vector(
    std::uint8_t head,const std::array<float,128>& source_vector,
    std::uint16_t learned_truth_mask,std::uint16_t xor_candidate_patch,
    std::uint32_t bool_operand_a,std::uint32_t bool_operand_b,
    bool authorized_candidate_writer,
    const std::array<std::uint8_t,3>& sourced_oriented_hyperedge,
    float native_hodge_curl,std::uint16_t phase_turns,
    std::uint32_t expected_generation,std::uint32_t current_generation,
    NativeHead16Receipt& receipt) {
    receipt={};
    if(!vm_||head==255)return fail("native head16: invalid guest/head");
    const std::uint32_t base=0x003B0000u+(static_cast<std::uint32_t>(head)<<8u);
    const std::uint32_t outbase=0x003F0000u+(static_cast<std::uint32_t>(head)<<8u);
    const auto as_bits=[](float value) {
        std::uint32_t bits=0;static_assert(sizeof(value)==sizeof(bits));
        std::memcpy(&bits,&value,4);return bits;
    };
    const auto as_float=[](std::uint32_t bits) {
        float value=0;std::memcpy(&value,&bits,4);return value;
    };
    for(std::uint32_t d=0;d<128u;++d)
        if(!write_word(base+d,as_bits(source_vector[d])))
            return fail("native head16: source vector transmit failed");
    const std::array<std::uint32_t,12> meta={
        learned_truth_mask,xor_candidate_patch,bool_operand_a,bool_operand_b,
        authorized_candidate_writer?1u:0u,expected_generation,
        current_generation,
        sourced_oriented_hyperedge[0],sourced_oriented_hyperedge[1],
        sourced_oriented_hyperedge[2],as_bits(native_hodge_curl),
        static_cast<std::uint32_t>(phase_turns)};
    for(std::uint32_t i=0;i<meta.size();++i)
        if(!write_word(base+128u+i,meta[i]))
            return fail("native head16: independent scratch transport failed");
    if(!write_word(kProposalBase,head)||!write_word(kCommandBase,110u)||
       !run_command())return fail("native head16: guest execution rejected: "+error_);
    const auto accepted=read_word(kResultBase+0);
    const auto returning_head=read_word(kResultBase+1);
    const auto vote=read_word(kResultBase+2);
    const auto reason=read_word(kResultBase+3);
    if(accepted==0u) {
        if(returning_head!=0||vote!=0||reason<1u||reason>5u)
            return fail("native head16: bad guest rejection receipt");
        receipt.rejection_reason=static_cast<std::uint8_t>(reason);
        return true;
    }
    if(accepted!=1u||returning_head!=head||vote>1u||reason!=0u)
        return fail("native head16: malformed success receipt");
    if(read_word(base+128)!=learned_truth_mask ||
       read_word(base+140)!=vote || read_word(base+147)!=1u)
        return fail("native head16: independent mask/Boolean vote drift");
    const auto chosen=read_word(base+141);
    const auto candidate_mask=read_word(base+146);
    if(chosen>=16u||candidate_mask==0||candidate_mask>65535u)
        return fail("native head16: invalid selected Boolean function");
    const float radius=as_float(read_word(base+168));
    const float depth=as_float(read_word(base+142));
    const float curl=as_float(read_word(base+143));
    if(!std::isfinite(radius)||!std::isfinite(depth)||!std::isfinite(curl)||
       radius<0.0f||radius>=1.0f||depth<0.0f||std::fabs(curl)>8.0f)
        return fail("native head16: invalid Poincare/curl receipt");
    for(std::uint32_t d=0;d<128u;++d){
        const float v=as_float(read_word(outbase+d));
        if(!std::isfinite(v)||std::fabs(v)>1.0f)
            return fail("native head16: nonfinite/invalid native projection");
        receipt.poincare_vector[d]=v;
    }
    receipt.accepted=true;
    receipt.head=head;receipt.hot_vote=static_cast<std::uint8_t>(vote);
    receipt.rule=static_cast<std::uint8_t>(chosen);
    receipt.candidate_truth_mask=static_cast<std::uint16_t>(candidate_mask);
    receipt.source_generation=expected_generation;
    receipt.radius=radius;receipt.radial_distance=depth;
    receipt.signed_curl_feedback=curl;
    receipt.phase_cos_q16=static_cast<std::int32_t>(read_word(base+144));
    receipt.phase_sin_q16=static_cast<std::int32_t>(read_word(base+145));
    return true;
}

bool RawFieldVM::native_triad_hotcold_vector(
    std::uint8_t triad,const std::array<std::uint8_t,255>& mapping,
    float native_hodge_curl,std::int32_t native_seven_credit_q16,
    std::uint32_t expected_generation,std::uint32_t current_generation,
    NativeTrihead128Receipt& receipt) {
    receipt={};
    if(!vm_||triad>=85)return fail("native trihead128: invalid guest/triad");
    std::array<bool,255> seen{};
    for(std::uint32_t i=0;i<255;++i) {
        const auto h=mapping[i];
        if(h>=255||seen[h])return fail("native trihead128: mapping is not a permutation");
        seen[h]=true;
        if(!write_word(0x003E7000u+i,h))
            return fail("native trihead128: mapping transmit failed");
    }
    std::uint32_t curl_bits=0;std::memcpy(&curl_bits,&native_hodge_curl,4);
    const std::array<std::uint32_t,5> args={
        triad,curl_bits,expected_generation,current_generation,
        static_cast<std::uint32_t>(native_seven_credit_q16)};
    for(std::uint32_t i=0;i<args.size();++i)
        if(!write_word(kProposalBase+i,args[i]))
            return fail("native trihead128: command args transmit failed");
    if(!write_word(kCommandBase,111u)||!run_command())
        return fail("native trihead128: guest execution rejected: "+error_);
    const auto accepted=read_word(kResultBase);
    const auto hot=read_word(kResultBase+1);
    const auto cold=read_word(kResultBase+2);
    const auto reason=read_word(kResultBase+3);
    if(accepted==0u) {
        if(hot!=0u||cold!=0u||reason<1u||reason>5u)
            return fail("native trihead128: malformed rejected receipt");
        receipt.rejection_reason=static_cast<std::uint8_t>(reason);
        return true;
    }
    if(accepted!=1u||hot>3u||hot+cold!=3u||reason!=0u)
        return fail("native trihead128: malformed triad vote receipt");
    const auto meta=0x003EE000u+(static_cast<std::uint32_t>(triad)<<4u);
    if(read_word(meta+5)!=hot||read_word(meta+6)!=cold||
       read_word(meta+12)!=1u||read_word(meta+13)!=triad||
       read_word(meta+14)!=1u||
       read_word(meta+11)!=static_cast<std::uint32_t>(native_seven_credit_q16)||
       read_word(meta+4)!=255u)
        return fail("native trihead128: metadata identity drift");
    const auto hot3=read_word(meta+8);
    const auto cold3=read_word(meta+9);
    const auto majority=static_cast<std::int32_t>(read_word(meta+7));
    if(hot3!=(hot==3u?1u:0u)||cold3!=(cold==3u?1u:0u)||
       majority!=(hot>=2u?1:-1))
        return fail("native trihead128: HOT/COLD classifications disagree");
    const auto as_float=[](std::uint32_t bits) {
        float v=0;std::memcpy(&v,&bits,4);return v;
    };
    const float radius=as_float(read_word(meta+0));
    const float depth=as_float(read_word(meta+1));
    const float curl=as_float(read_word(meta+2));
    const float gradient=as_float(read_word(meta+10));
    if(!std::isfinite(radius)||radius<0||radius>=1||
       !std::isfinite(depth)||depth<0||
       !std::isfinite(curl)||!std::isfinite(gradient))
        return fail("native trihead128: invalid Poincare/curl/gradient");
    const auto dest=0x003EB000u+(static_cast<std::uint32_t>(triad)<<7u);
    for(std::uint32_t d=0;d<128u;++d){
        const float value=as_float(read_word(dest+d));
        if(!std::isfinite(value)||std::fabs(value)>1.0f)
            return fail("native trihead128: invalid vector component");
        receipt.poincare_vector[d]=value;
    }
    receipt.accepted=true;receipt.triad=triad;
    receipt.hot_count=static_cast<std::uint8_t>(hot);
    receipt.cold_count=static_cast<std::uint8_t>(cold);
    receipt.members={mapping[3u*triad],mapping[3u*triad+1],mapping[3u*triad+2]};
    receipt.unanimous_hot=hot3==1u;
    receipt.unanimous_cold=cold3==1u;
    receipt.majority_sign=majority;
    receipt.source_seven_credit_q16=native_seven_credit_q16;
    receipt.source_generation=expected_generation;
    receipt.radius=radius;receipt.radial_distance=depth;
    receipt.signed_curl_feedback=curl;
    receipt.candidate_credit_gradient=gradient;
    return true;
}

bool RawFieldVM::native_head_block(
    const std::array<float,128>& input, std::uint8_t slot,
    std::array<float,128>& output, std::uint8_t& reason) {
    output.fill(0.0f);
    reason = 0u;
    if (!vm_) return fail("native head block: VM unavailable");
    if (slot >= 16u) { reason = 1u; return true; }
    constexpr std::uint32_t kInput = 0x00D00000u;
    constexpr std::uint32_t kOutput = 0x00D02000u;
    auto as_bits = [](float value) {
        std::uint32_t bits = 0u;
        std::memcpy(&bits, &value, sizeof(bits));
        return bits;
    };
    for (std::uint32_t i = 0; i < 128u; ++i) {
        const float value = input[i];
        if (!std::isfinite(value))
            return fail("native head block: nonfinite input");
        if (!write_word(kInput + i, as_bits(value)))
            return fail("native head block: input transport failed");
    }
    if (!write_word(kProposalBase + 0u, kInput) ||
        !write_word(kProposalBase + 1u, kOutput) ||
        !write_word(kProposalBase + 2u, slot) ||
        !write_word(kCommandBase, 122u))
        return fail("native head block: command transport failed");
    if (!run_command())
        return fail("native head block: guest execution failed: " + error_);
    const auto ok = read_word(kResultBase);
    const auto count = read_word(kResultBase + 1u);
    const auto used_slot = read_word(kResultBase + 2u);
    const auto code = read_word(kResultBase + 3u);
    if (ok == 0u) {
        if (count != 0u || used_slot != 0u || code < 1u || code > 3u)
            return fail("native head block: malformed rejection");
        reason = static_cast<std::uint8_t>(code);
        return true;
    }
    if (ok != 1u || count != 128u || used_slot != slot || code != 0u)
        return fail("native head block: malformed success receipt");
    for (std::uint32_t i = 0; i < 128u; ++i) {
        const auto bits = read_word(kOutput + i);
        float value = 0.0f;
        std::memcpy(&value, &bits, sizeof(value));
        if (!std::isfinite(value))
            return fail("native head block: nonfinite output");
        output[i] = value;
    }
    reason = 0u;
    return true;
}

bool RawFieldVM::native_head_block6(
    const std::array<float, 6 * 128>& input, std::uint8_t token_count,
    std::uint8_t slot, std::array<float, 6 * 128>& output,
    std::uint8_t& reason) {
    output.fill(0.0f);
    reason = 0u;
    if (!vm_) return fail("native head block6: VM unavailable");
    if (token_count == 0u || token_count > 6u) { reason = 1u; return true; }
    if (slot >= 16u) { reason = 1u; return true; }
    constexpr std::uint32_t kInput = 0x00D00000u;
    constexpr std::uint32_t kOutput = 0x00D02000u;
    auto as_bits = [](float value) {
        std::uint32_t bits = 0u;
        std::memcpy(&bits, &value, sizeof(bits));
        return bits;
    };
    const std::uint32_t count = static_cast<std::uint32_t>(token_count) * 128u;
    for (std::uint32_t i = 0; i < count; ++i) {
        const float value = input[i];
        if (!std::isfinite(value))
            return fail("native head block6: nonfinite input");
        if (!write_word(kInput + i, as_bits(value)))
            return fail("native head block6: input transport failed");
    }
    if (!write_word(kProposalBase + 0u, kInput) ||
        !write_word(kProposalBase + 1u, kOutput) ||
        !write_word(kProposalBase + 2u, slot) ||
        !write_word(kProposalBase + 3u, token_count) ||
        !write_word(kCommandBase, 122u))
        return fail("native head block6: command transport failed");
    if (!run_command())
        return fail("native head block6: guest execution failed: " + error_);
    const auto ok = read_word(kResultBase);
    const auto words = read_word(kResultBase + 1u);
    const auto used_slot = read_word(kResultBase + 2u);
    const auto code = read_word(kResultBase + 3u);
    if (ok == 0u) {
        if (words != 0u || used_slot != 0u || code < 1u || code > 3u)
            return fail("native head block6: malformed rejection");
        reason = static_cast<std::uint8_t>(code);
        return true;
    }
    if (ok != 1u || words != count || used_slot != slot || code != 0u)
        return fail("native head block6: malformed success receipt");
    for (std::uint32_t i = 0; i < count; ++i) {
        const auto bits = read_word(kOutput + i);
        float value = 0.0f;
        std::memcpy(&value, &bits, sizeof(value));
        if (!std::isfinite(value))
            return fail("native head block6: nonfinite output");
        output[i] = value;
    }
    reason = 0u;
    return true;
}

bool RawFieldVM::native_head_state_readout(
    const std::array<float, 128>& state,
    const std::vector<std::array<float, 128>>& candidates,
    std::vector<float>& scores, std::uint8_t& reason) {
    scores.clear();
    reason = 0u;
    if (!vm_) return fail("native head readout: VM unavailable");
    if (candidates.empty() || candidates.size() > 64u) {
        reason = 1u;
        return true;
    }
    constexpr std::uint32_t kState = 0x00D03000u;
    constexpr std::uint32_t kCandidates = 0x00D04000u;
    constexpr std::uint32_t kScores = 0x00D07000u;
    auto as_bits = [](float value) {
        std::uint32_t bits = 0u;
        std::memcpy(&bits, &value, sizeof(bits));
        return bits;
    };
    for (std::uint32_t d = 0; d < 128u; ++d) {
        if (!std::isfinite(state[d]))
            return fail("native head readout: nonfinite state");
        if (!write_word(kState + d, as_bits(state[d])))
            return fail("native head readout: state transport failed");
    }
    for (std::size_t i = 0; i < candidates.size(); ++i) {
        for (std::uint32_t d = 0; d < 128u; ++d) {
            const float value = candidates[i][d];
            if (!std::isfinite(value))
                return fail("native head readout: nonfinite candidate");
            if (!write_word(kCandidates + static_cast<std::uint32_t>(i) * 128u + d,
                            as_bits(value)))
                return fail("native head readout: candidate transport failed");
        }
    }
    if (!write_word(kProposalBase + 0u, kState) ||
        !write_word(kProposalBase + 1u, kCandidates) ||
        !write_word(kProposalBase + 2u, kScores) ||
        !write_word(kProposalBase + 3u, static_cast<std::uint32_t>(candidates.size())) ||
        !write_word(kCommandBase, 123u))
        return fail("native head readout: command transport failed");
    if (!run_command())
        return fail("native head readout: guest execution failed: " + error_);
    const auto ok = read_word(kResultBase);
    const auto count = read_word(kResultBase + 1u);
    const auto code = read_word(kResultBase + 3u);
    if (ok == 0u) {
        if (count != 0u || code != 1u)
            return fail("native head readout: malformed rejection");
        reason = 1u;
        return true;
    }
    if (ok != 1u || count != candidates.size() || code != 0u)
        return fail("native head readout: malformed success receipt");
    scores.resize(candidates.size());
    for (std::size_t i = 0; i < candidates.size(); ++i) {
        const auto bits = read_word(kScores + static_cast<std::uint32_t>(i));
        float value = 0.0f;
        std::memcpy(&value, &bits, sizeof(value));
        if (!std::isfinite(value))
            return fail("native head readout: nonfinite score");
        scores[i] = value;
    }
    reason = 0u;
    return true;
}

bool RawFieldVM::native_head_state_train(
    const std::array<float, 128>& state,
    const std::vector<std::array<float, 128>>& candidates,
    std::uint8_t target, float learning_rate,
    std::vector<float>& probabilities,
    std::vector<std::array<float, 128>>& updated_candidates,
    float& loss, std::uint8_t& predicted, std::uint8_t& reason) {
    probabilities.clear();
    updated_candidates.clear();
    loss = 0.0f;
    predicted = 0u;
    reason = 0u;
    if (!vm_) return fail("native head train: VM unavailable");
    if (candidates.empty() || candidates.size() > 64u ||
        target >= candidates.size() || !std::isfinite(learning_rate) ||
        learning_rate < 0.0f) {
        reason = 1u;
        return true;
    }
    constexpr std::uint32_t kState = 0x00D03000u;
    constexpr std::uint32_t kCandidates = 0x00D04000u;
    constexpr std::uint32_t kProbabilities = 0x00D07000u;
    auto as_bits = [](float value) {
        std::uint32_t bits = 0u;
        std::memcpy(&bits, &value, sizeof(bits));
        return bits;
    };
    for (std::uint32_t d = 0; d < 128u; ++d) {
        if (!std::isfinite(state[d]))
            return fail("native head train: nonfinite state");
        if (!write_word(kState + d, as_bits(state[d])))
            return fail("native head train: state transport failed");
    }
    for (std::size_t i = 0; i < candidates.size(); ++i) {
        for (std::uint32_t d = 0; d < 128u; ++d) {
            const float value = candidates[i][d];
            if (!std::isfinite(value))
                return fail("native head train: nonfinite candidate");
            if (!write_word(kCandidates + static_cast<std::uint32_t>(i) * 128u + d,
                            as_bits(value)))
                return fail("native head train: candidate transport failed");
        }
    }
    if (!write_word(kProposalBase + 0u, kState) ||
        !write_word(kProposalBase + 1u, kCandidates) ||
        !write_word(kProposalBase + 2u, kProbabilities) ||
        !write_word(kProposalBase + 3u, static_cast<std::uint32_t>(candidates.size())) ||
        !write_word(kProposalBase + 4u, target) ||
        !write_word(kProposalBase + 5u, as_bits(learning_rate)) ||
        !write_word(kCommandBase, 124u))
        return fail("native head train: command transport failed");
    if (!run_command())
        return fail("native head train: guest execution failed: " + error_);
    const auto ok = read_word(kResultBase);
    const auto loss_bits = read_word(kResultBase + 1u);
    const auto pred = read_word(kResultBase + 2u);
    const auto code = read_word(kResultBase + 3u);
    if (ok == 0u) {
        if (loss_bits != 0u || pred != 0u || code != 1u)
            return fail("native head train: malformed rejection");
        reason = 1u;
        return true;
    }
    if (ok != 1u || pred >= candidates.size() || code != 0u)
        return fail("native head train: malformed success receipt");
    std::memcpy(&loss, &loss_bits, sizeof(loss));
    if (!std::isfinite(loss))
        return fail("native head train: nonfinite loss");
    probabilities.resize(candidates.size());
    for (std::size_t i = 0; i < candidates.size(); ++i) {
        const auto bits = read_word(kProbabilities + static_cast<std::uint32_t>(i));
        float value = 0.0f;
        std::memcpy(&value, &bits, sizeof(value));
        if (!std::isfinite(value) || value < 0.0f || value > 1.0f)
            return fail("native head train: invalid probability");
        probabilities[i] = value;
    }
    updated_candidates.resize(candidates.size());
    for (std::size_t i = 0; i < candidates.size(); ++i) {
        for (std::uint32_t d = 0; d < 128u; ++d) {
            const auto bits = read_word(
                kCandidates + static_cast<std::uint32_t>(i) * 128u + d);
            float value = 0.0f;
            std::memcpy(&value, &bits, sizeof(value));
            if (!std::isfinite(value))
                return fail("native head train: nonfinite updated candidate");
            updated_candidates[i][d] = value;
        }
    }
    predicted = static_cast<std::uint8_t>(pred);
    reason = 0u;
    return true;
}

bool RawFieldVM::native_head_page_train(
    const std::array<float, 6 * 128>& context, std::uint8_t token_count,
    std::uint8_t slot, const std::array<float, 128>& target,
    float learning_rate, std::array<float, 6 * 128>& output,
    float& error_norm, std::uint8_t& reason,
    bool update_output_projection) {
    output.fill(0.0f);
    error_norm = 0.0f;
    reason = 0u;
    if (!vm_) return fail("native page train: VM unavailable");
    if (token_count == 0u || token_count > 6u || slot >= 16u ||
        !std::isfinite(learning_rate) || learning_rate < 0.0f) {
        reason = 1u;
        return true;
    }
    constexpr std::uint32_t kContext = 0x00D00000u;
    constexpr std::uint32_t kOutput = 0x00D02000u;
    constexpr std::uint32_t kTarget = 0x00D03000u;
    auto as_bits = [](float value) {
        std::uint32_t bits = 0u;
        std::memcpy(&bits, &value, sizeof(bits));
        return bits;
    };
    const std::uint32_t count = static_cast<std::uint32_t>(token_count) * 128u;
    for (std::uint32_t i = 0; i < count; ++i) {
        if (!std::isfinite(context[i]))
            return fail("native page train: nonfinite context");
        if (!write_word(kContext + i, as_bits(context[i])))
            return fail("native page train: context transport failed");
    }
    for (std::uint32_t d = 0; d < 128u; ++d) {
        if (!std::isfinite(target[d]))
            return fail("native page train: nonfinite target");
        if (!write_word(kTarget + d, as_bits(target[d])))
            return fail("native page train: target transport failed");
    }
    if (!write_word(kProposalBase + 0u, kContext) ||
        !write_word(kProposalBase + 1u, kOutput) ||
        !write_word(kProposalBase + 2u, slot) ||
        !write_word(kProposalBase + 3u, token_count) ||
        !write_word(kProposalBase + 4u, kTarget) ||
        !write_word(kProposalBase + 5u, as_bits(learning_rate)) ||
        !write_word(kCommandBase, update_output_projection ? 126u : 125u))
        return fail("native page train: command transport failed");
    if (!run_command())
        return fail("native page train: guest execution failed: " + error_);
    const auto ok = read_word(kResultBase);
    const auto error_bits = read_word(kResultBase + 1u);
    const auto code = read_word(kResultBase + 3u);
    if (ok == 0u) {
        if (error_bits != 0u || code < 1u || code > 2u)
            return fail("native page train: malformed rejection");
        reason = static_cast<std::uint8_t>(code);
        return true;
    }
    if (ok != 1u || code != 0u)
        return fail("native page train: malformed success receipt");
    std::memcpy(&error_norm, &error_bits, sizeof(error_norm));
    if (!std::isfinite(error_norm) || error_norm < 0.0f)
        return fail("native page train: invalid error norm");
    for (std::uint32_t i = 0; i < count; ++i) {
        const auto bits = read_word(kOutput + i);
        float value = 0.0f;
        std::memcpy(&value, &bits, sizeof(value));
        if (!std::isfinite(value))
            return fail("native page train: nonfinite output");
        output[i] = value;
    }
    reason = 0u;
    return true;
}

bool RawFieldVM::native_head_page_train_w1(
    const std::array<float, 6 * 128>& context, std::uint8_t token_count,
    std::uint8_t slot, const std::array<float, 128>& target,
    float learning_rate, std::array<float, 6 * 128>& output,
    float& error_norm, std::uint8_t& reason) {
    output.fill(0.0f);
    error_norm = 0.0f;
    reason = 0u;
    if (!vm_) return fail("native W1 page train: VM unavailable");
    if (token_count == 0u || token_count > 6u || slot >= 16u ||
        !std::isfinite(learning_rate) || learning_rate < 0.0f) {
        reason = 1u;
        return true;
    }
    constexpr std::uint32_t kContext = 0x00D00000u;
    constexpr std::uint32_t kOutput = 0x00D02000u;
    constexpr std::uint32_t kTarget = 0x00D03000u;
    auto as_bits = [](float value) {
        std::uint32_t bits = 0u;
        std::memcpy(&bits, &value, sizeof(bits));
        return bits;
    };
    const std::uint32_t count = static_cast<std::uint32_t>(token_count) * 128u;
    for (std::uint32_t i = 0; i < count; ++i) {
        if (!std::isfinite(context[i]))
            return fail("native W1 page train: nonfinite context");
        if (!write_word(kContext + i, as_bits(context[i])))
            return fail("native W1 page train: context transport failed");
    }
    for (std::uint32_t d = 0; d < 128u; ++d) {
        if (!std::isfinite(target[d]))
            return fail("native W1 page train: nonfinite target");
        if (!write_word(kTarget + d, as_bits(target[d])))
            return fail("native W1 page train: target transport failed");
    }
    if (!write_word(kProposalBase + 0u, kContext) ||
        !write_word(kProposalBase + 1u, kOutput) ||
        !write_word(kProposalBase + 2u, slot) ||
        !write_word(kProposalBase + 3u, token_count) ||
        !write_word(kProposalBase + 4u, kTarget) ||
        !write_word(kProposalBase + 5u, as_bits(learning_rate)) ||
        !write_word(kCommandBase, 127u))
        return fail("native W1 page train: command transport failed");
    if (!run_command())
        return fail("native W1 page train: guest execution failed: " + error_);
    const auto ok = read_word(kResultBase);
    const auto error_bits = read_word(kResultBase + 1u);
    const auto code = read_word(kResultBase + 3u);
    if (ok == 0u) {
        if (error_bits != 0u || code < 1u || code > 2u)
            return fail("native W1 page train: malformed rejection");
        reason = static_cast<std::uint8_t>(code);
        return true;
    }
    if (ok != 1u || code != 0u)
        return fail("native W1 page train: malformed success receipt");
    std::memcpy(&error_norm, &error_bits, sizeof(error_norm));
    if (!std::isfinite(error_norm) || error_norm < 0.0f)
        return fail("native W1 page train: invalid error norm");
    for (std::uint32_t i = 0; i < count; ++i) {
        const auto bits = read_word(kOutput + i);
        float value = 0.0f;
        std::memcpy(&value, &bits, sizeof(value));
        if (!std::isfinite(value))
            return fail("native W1 page train: nonfinite output");
        output[i] = value;
    }
    reason = 0u;
    return true;
}

bool RawFieldVM::native_shortlist_batch(
    const std::array<std::uint32_t,6>& context_words,
    std::uint8_t valid_mask, std::uint8_t task,
    std::uint32_t expected_generation, std::uint32_t current_generation,
    const std::vector<std::uint32_t>& candidate_word_ids,
    std::vector<NativeShortlistCandidate>& out, std::size_t& accepted) {
    if (!vm_) return fail("native shortlist: VM not loaded");
    if (candidate_word_ids.empty() || candidate_word_ids.size() > 64u)
        return fail("native shortlist: candidate count outside 1..64");
    for (std::uint32_t word : candidate_word_ids)
        if (word == 0u) return fail("native shortlist: zero candidate word");
    constexpr std::uint32_t kRequest = 0x003E7000u;
    constexpr std::uint32_t kOutput = 0x003E7400u;
    if (!write_word(kRequest, static_cast<std::uint32_t>(candidate_word_ids.size())))
        return fail("native shortlist: request count");
    for (std::size_t i = 0; i < context_words.size(); ++i)
        if (!write_word(kRequest + 1u + static_cast<std::uint32_t>(i),
                        context_words[i]))
            return fail("native shortlist: context");
    if (!write_word(kRequest + 7u, valid_mask) ||
        !write_word(kRequest + 8u, task) ||
        !write_word(kRequest + 9u, expected_generation) ||
        !write_word(kRequest + 10u, current_generation) ||
        !write_word(kRequest + 11u, 255u))
        return fail("native shortlist: metadata");
    for (std::size_t i = 0; i < candidate_word_ids.size(); ++i)
        if (!write_word(kRequest + 12u + static_cast<std::uint32_t>(i),
                        candidate_word_ids[i]))
            return fail("native shortlist: candidates");
    if (!write_word(kProposalBase + 0u, kRequest) ||
        !write_word(kProposalBase + 1u, kOutput) ||
        !write_word(kCommandBase, 118u))
        return fail("native shortlist: command");
    if (!run_command()) return false;
    accepted = read_word(kResultBase + 0u);
    if (accepted > candidate_word_ids.size())
        return fail("native shortlist: accepted count overflow");
    out.assign(candidate_word_ids.size(), NativeShortlistCandidate{});
    for (std::size_t i = 0; i < candidate_word_ids.size(); ++i) {
        const std::uint32_t base = kOutput + static_cast<std::uint32_t>(i * 4u);
        auto as_float = [&](std::uint32_t offset) {
            const std::uint32_t bits = read_word(base + offset);
            float value = 0.0f;
            std::memcpy(&value, &bits, sizeof(value));
            return value;
        };
        out[i].poincare_x = as_float(0);
        out[i].poincare_y = as_float(1);
        out[i].radius = as_float(2);
        out[i].radial_distance = as_float(3);
        out[i].accepted =
            std::isfinite(out[i].poincare_x) && std::isfinite(out[i].poincare_y) &&
            std::isfinite(out[i].radius) && std::isfinite(out[i].radial_distance) &&
            out[i].radius >= 0.0f && out[i].radius < 1.0f &&
            out[i].radial_distance >= 0.0f;
    }
    return true;
}

// Native opcode113 transports sourced head vectors into private NaN16
// scratches, executes every Boolean/trig/head and every 128D trihead in the
// guest, and READS its genuine source-derived 85 masks and field quorum.
// The host is a provenance/ABI boundary, NOT a substitute geometry engine.
bool RawFieldVM::native_full_field_255_85(
    const std::array<NativeFullFieldHeadSource,255>& sources,
    const std::array<std::uint8_t,255>& mapping,
    const std::array<float,85>& triad_curls,
    const std::array<std::int32_t,85>& seven_credits,
    std::uint32_t expected_epoch,std::uint32_t current_epoch,
    NativeFullField128Receipt& receipt) {
    receipt={};
    if(!vm_)return fail("native full field: NaN0S guest not loaded");
    const auto bits=[](float v){
        std::uint32_t b=0;static_assert(sizeof(b)==sizeof(v));
        std::memcpy(&b,&v,sizeof(b));return b;
    };
    const auto f32=[](std::uint32_t b){
        float v=0;std::memcpy(&v,&b,sizeof(b));return v;
    };
    // Prevalidate entire mapping/capability/source envelope so partial
    // transport never makes a malformed field appear measured.
    std::array<bool,255> seen{};
    for(std::size_t slot=0;slot<255u;++slot){
        const unsigned h=mapping[slot];
        if(h>=255u||seen[h])
            return fail("native full field: duplicate/VOID mapping");
        seen[h]=true;
    }
    for(unsigned h=0;h<255u;++h){
        const auto& x=sources[h];
        if(!x.candidate_writer_lease || !x.truth_mask ||
           !std::isfinite(x.sourced_native_hodge_curl) ||
           std::fabs(x.sourced_native_hodge_curl)>8.0f)
            return fail("native full field: missing head lease/truth/Hodge source");
        const auto& e=x.sourced_oriented_hyperedge;
        if(e[0]>=255u||e[1]>=255u||e[2]>=255u||
           e[0]==e[1]||e[0]==e[2]||e[1]==e[2])
            return fail("native full field: invalid sourced oriented head triangle");
        for(float v:x.sourced_vector)
            if(!std::isfinite(v))
                return fail("native full field: nonfinite sourced 128D head vector");
    }
    for(std::size_t t=0;t<85u;++t)
        if(!std::isfinite(triad_curls[t]) ||
           std::fabs(triad_curls[t])>8.0f ||
           seven_credits[t]<-524288 || seven_credits[t]>524288)
            return fail("native full field: nonfinite/out-of-range native curl or credit");
    constexpr std::uint32_t kMapping=0x003E7000u;
    constexpr std::uint32_t kCurl=0x003EF600u;
    constexpr std::uint32_t kCredit=0x003EF700u;
    constexpr std::uint32_t kVotes=0x003EF000u;
    constexpr std::uint32_t kReport=0x003EF100u;
    // Every source vector and operator setting goes to its OWN head slab.
    for(unsigned h=0;h<255u;++h){
        const auto& x=sources[h];
        const std::uint32_t base=0x003B0000u+(h<<8u);
        for(unsigned d=0;d<128u;++d)
            if(!write_word(base+d,bits(x.sourced_vector[d])))
                return fail("native full field: head vector scratch transport failed");
        const std::array<std::uint32_t,12> meta={
            x.truth_mask,x.candidate_xor_patch,x.boolean_a,x.boolean_b,
            x.candidate_writer_lease?1u:0u,expected_epoch,current_epoch,
            x.sourced_oriented_hyperedge[0],x.sourced_oriented_hyperedge[1],
            x.sourced_oriented_hyperedge[2],bits(x.sourced_native_hodge_curl),
            x.phase_turns};
        for(unsigned i=0;i<meta.size();++i)
            if(!write_word(base+128u+i,meta[i]))
                return fail("native full field: head truth/epoch transport failed");
    }
    for(unsigned i=0;i<255u;++i)
        if(!write_word(kMapping+i,mapping[i]))
            return fail("native full field: mapping transport failed");
    for(unsigned t=0;t<85u;++t)
        if(!write_word(kCurl+t,bits(triad_curls[t])) ||
           !write_word(kCredit+t,static_cast<std::uint32_t>(seven_credits[t])))
            return fail("native full field: sourced credit/curl transport failed");
    if(!write_word(kProposalBase,expected_epoch)||
       !write_word(kProposalBase+1,current_epoch)||
       !write_word(kCommandBase,113u)||!run_command())
        return fail("native full field: fused NaN16 guest failed: "+error_);
    const auto ok=read_word(kResultBase),quorum=read_word(kResultBase+1);
    const auto head_count=read_word(kResultBase+2),reason=read_word(kResultBase+3);
    if(ok==0u){
        if(quorum||head_count||reason<1u||reason>5u)
            return fail("native full field: invalid rejected guest receipt");
        receipt.rejection_reason=static_cast<std::uint8_t>(reason);
        return true;
    }
    if(ok!=1u||head_count!=255u||quorum>85u||reason!=0u)
        return fail("native full field: incomplete or invalid guest execution");
    std::array<std::uint32_t,10> field{};
    for(unsigned i=0;i<field.size();++i)field[i]=read_word(kReport+i);
    if(field[0]!=255u||field[1]!=85u||field[2]>255u||
       field[3]!=quorum||field[4]>85u||field[5]>85u||
       field[6]>85u||field[7]>1u||field[8]!=255u||
       field[9]!=expected_epoch||
       field[3]+field[4]!=85u||field[5]>field[3]||
       field[6]>field[4]||field[7]!=(quorum>=43u?1u:0u))
        return fail("native full field: guest field/quorum report inconsistent");
    receipt.mapping=mapping;
    receipt.head_count=255u;receipt.triad_count=85u;
    receipt.hot_heads=static_cast<std::uint16_t>(field[2]);
    receipt.hot_majority_triads=static_cast<std::uint16_t>(quorum);
    receipt.cold_majority_triads=static_cast<std::uint16_t>(field[4]);
    receipt.unanimous_hot=static_cast<std::uint16_t>(field[5]);
    receipt.unanimous_cold=static_cast<std::uint16_t>(field[6]);
    receipt.field_hot=field[7]==1u;receipt.source_generation=expected_epoch;
    for(unsigned t=0;t<85u;++t){
        const auto vote=read_word(kVotes+t);
        if(vote>7u)return fail("native full field: malformed triad member mask");
        receipt.native_vote_masks[t]=static_cast<std::uint8_t>(vote);
    }
    // Verify every distinct head scratch and read the native Poincare128
    // vector. The host does not project or rotate any source coordinates.
    for(unsigned h=0;h<255u;++h){
        const std::uint32_t src=0x003B0000u+(h<<8u);
        const std::uint32_t dst=0x003F0000u+(h<<8u);
        const auto vote=read_word(src+140u),rule=read_word(src+141u);
        const auto mask=read_word(src+146u);
        if(read_word(src+147u)!=1u||read_word(src+128u)!=sources[h].truth_mask||
           vote>1u||rule>=16u||!mask||mask>65535u)
            return fail("native full field: head Boolean/source identity drift");
        auto& out=receipt.heads[h];
        out.head=static_cast<std::uint8_t>(h);
        out.hot_vote=static_cast<std::uint8_t>(vote);
        out.rule=static_cast<std::uint8_t>(rule);
        out.candidate_truth_mask=static_cast<std::uint16_t>(mask);
        out.source_generation=expected_epoch;
        out.radius=f32(read_word(src+168u));
        out.radial_distance=f32(read_word(src+142u));
        out.signed_curl_feedback=f32(read_word(src+143u));
        out.phase_cos_q16=static_cast<std::int32_t>(read_word(src+144u));
        out.phase_sin_q16=static_cast<std::int32_t>(read_word(src+145u));
        if(!std::isfinite(out.radius)||out.radius<0.0f||out.radius>=1.0f||
           !std::isfinite(out.radial_distance)||out.radial_distance<0.0f||
           !std::isfinite(out.signed_curl_feedback)||
           std::fabs(out.signed_curl_feedback)>8.0f)
            return fail("native full field: invalid guest head Poincare/curl");
        for(unsigned d=0;d<128u;++d){
            const float v=f32(read_word(dst+d));
            if(!std::isfinite(v)||std::fabs(v)>1.0f)
                return fail("native full field: invalid guest head vector");
            out.poincare_vector[d]=v;
        }
        out.accepted=true;
    }
    // Read each trihead's independent 128D Poincare, HOT/COLD selection,
    // signed native curl and seven-credit eligibility gradient (not BPTT).
    for(unsigned t=0;t<85u;++t){
        const std::uint32_t meta=0x003EE000u+(t<<4u);
        const std::uint32_t dst=0x003EB000u+(t<<7u);
        const auto hot=read_word(meta+5),cold=read_word(meta+6);
        const auto sign=static_cast<std::int32_t>(read_word(meta+7));
        if(hot>3u||hot+cold!=3u||read_word(meta+12)!=1u||
           read_word(meta+13)!=t||read_word(meta+14)!=1u||
           read_word(meta+4)!=255u||
           read_word(meta+11)!=static_cast<std::uint32_t>(seven_credits[t])||
           read_word(meta+8)!=(hot==3u?1u:0u)||
           read_word(meta+9)!=(cold==3u?1u:0u)||
           sign!=(hot>=2u?1:-1))
            return fail("native full field: trihead scratch metadata drift");
        auto& out=receipt.triheads[t];
        out.triad=static_cast<std::uint8_t>(t);
        out.members={mapping[3u*t],mapping[3u*t+1u],mapping[3u*t+2u]};
        out.hot_count=static_cast<std::uint8_t>(hot);
        out.cold_count=static_cast<std::uint8_t>(cold);
        out.unanimous_hot=hot==3u;out.unanimous_cold=cold==3u;
        out.majority_sign=sign;
        out.source_seven_credit_q16=seven_credits[t];
        out.source_generation=expected_epoch;
        out.radius=f32(read_word(meta));
        out.radial_distance=f32(read_word(meta+1u));
        out.signed_curl_feedback=f32(read_word(meta+2u));
        out.candidate_credit_gradient=f32(read_word(meta+10u));
        if(!std::isfinite(out.radius)||out.radius<0.0f||out.radius>=1.0f||
           !std::isfinite(out.radial_distance)||out.radial_distance<0.0f||
           !std::isfinite(out.signed_curl_feedback)||
           !std::isfinite(out.candidate_credit_gradient))
            return fail("native full field: invalid native triad geometry");
        for(unsigned d=0;d<128u;++d){
            const float v=f32(read_word(dst+d));
            if(!std::isfinite(v)||std::fabs(v)>1.0f)
                return fail("native full field: invalid native triad vector");
            out.poincare_vector[d]=v;
        }
        // Independent raw-head votes must agree with guest-produced mask.
        const unsigned mask=unsigned(receipt.heads[out.members[0]].hot_vote)|
            (unsigned(receipt.heads[out.members[1]].hot_vote)<<1u)|
            (unsigned(receipt.heads[out.members[2]].hot_vote)<<2u);
        if(mask!=receipt.native_vote_masks[t])
            return fail("native full field: mask is not derived from its three heads");
        out.accepted=true;
    }
    receipt.accepted=true;
    return true;
}

// Typed NaN16 ABI for physical palindromic anchors and the existing
// C(256,2) dual-rail mirror field. ALL curvature/geometry/recovery is guest.
bool RawFieldVM::native_mirror_pair_rail_gradient(
    const std::array<float,65280>& rails,
    std::uint32_t expected_epoch,std::uint32_t current_epoch,
    std::array<float,32640>& gradients,
    std::uint32_t& hot_pairs,std::uint32_t& cold_pairs,
    std::uint32_t& flat_pairs,bool& accepted,std::uint8_t& reason) {
    gradients.fill(0.0f);
    hot_pairs=0u;cold_pairs=0u;flat_pairs=0u;
    accepted=false;reason=0u;
    if(!vm_)return fail("native mirror rails: VM unavailable");
    // Only ABI transport of independently stored, authenticated physical
    // S+/S- rails. Native opcode120 performs ALL float32 subtraction,
    // VOID checks, signed pair classification and candidate publication.
    constexpr std::uint32_t kRails=0x00340000u;
    constexpr std::uint32_t kFlows=0x003A0000u;
    constexpr std::uint32_t kReport=0x00358000u;
    for(unsigned i=0;i<rails.size();++i){
        const float value=rails[i];
        if(!std::isfinite(value)||std::fabs(value)>8.0f)
            return fail("native mirror rails: nonfinite/out-of-bounds sourced rail");
        std::uint32_t bits=0u;
        std::memcpy(&bits,&value,sizeof(bits));
        if(!write_word(kRails+i,bits))
            return fail("native mirror rails: physical dual-rail transport failure");
    }
    if(!write_word(kProposalBase,expected_epoch)||
       !write_word(kProposalBase+1,current_epoch)||
       !write_word(kCommandBase,120u)||!run_command())
        return fail("native mirror rails: guest measurement failed: "+error_);
    const auto ok=read_word(kResultBase),count=read_word(kResultBase+1);
    const auto hot=read_word(kResultBase+2),code=read_word(kResultBase+3);
    if(ok==0u){
        if(count||hot||code<1u||code>3u)
            return fail("native mirror rails: malformed native refusal");
        reason=static_cast<std::uint8_t>(code);
        return true;
    }
    if(ok!=1u||count!=32640u||code!=0u||hot>32640u)
        return fail("native mirror rails: invalid whole-pair native count");
    const auto hot_actual=read_word(kReport);
    const auto cold_actual=read_word(kReport+1);
    const auto flat_actual=read_word(kReport+2);
    const auto epoch=read_word(kReport+3);
    if(hot_actual!=hot||epoch!=expected_epoch||
       hot_actual+cold_actual+flat_actual!=32640u)
        return fail("native mirror rails: inconsistent guest HOT/COLD/FLAT report");
    for(unsigned i=0;i<32640u;++i){
        const auto word=read_word(kFlows+i);
        float value=0.0f;
        std::memcpy(&value,&word,sizeof(value));
        if(!std::isfinite(value)||std::fabs(value)>8.0f)
            return fail("native mirror rails: invalid published native gradient");
        gradients[i]=value;
    }
    hot_pairs=hot_actual;cold_pairs=cold_actual;flat_pairs=flat_actual;
    accepted=true;return true;
}

bool RawFieldVM::native_mirror_triangle_boot(
    std::uint32_t seed,std::uint32_t epoch,bool& accepted,
    std::uint8_t& reason) {
    accepted=false;reason=0u;
    if(!vm_||seed==0u)return fail("native mirror boot: invalid guest/seed");
    if(!write_word(kProposalBase,seed)||
       !write_word(kProposalBase+1u,epoch)||
       !write_word(kCommandBase,114u)||!run_command())
        return fail("native mirror boot: NaN16 execution failed: "+error_);
    const auto ok=read_word(kResultBase);
    const auto count=read_word(kResultBase+1);
    const auto code=read_word(kResultBase+2);
    if(ok==0u){
        if(count!=0u||code<1u||code>2u)
            return fail("native mirror boot: malformed rejection");
        reason=static_cast<std::uint8_t>(code);return true;
    }
    if(ok!=1u||count!=510u||code!=0u)
        return fail("native mirror boot: malformed seeded sample count");
    constexpr std::uint32_t kFlag=0x00394000u;
    if(read_word(kFlag)!=1u||read_word(kFlag+1)!=seed||
       read_word(kFlag+2)!=epoch)
        return fail("native mirror boot: frozen seed or generation drift");
    accepted=true;return true;
}

bool RawFieldVM::native_mirror_triangle_measure(
    const std::array<float,32640>& flows,
    std::uint32_t expected_epoch,std::uint32_t current_epoch,
    std::vector<NativeMirrorTriangleReceipt>& measured,
    std::uint16_t& hot_majority,bool& accepted,std::uint8_t& reason) {
    measured.clear();hot_majority=0;accepted=false;reason=0u;
    if(!vm_)return fail("native mirror field: missing guest");
    constexpr std::uint32_t kFlow=0x003A0000u;
    constexpr std::uint32_t kRecords=0x00360000u;
    const auto as_bits=[](float value){
        std::uint32_t bits=0;static_assert(sizeof(value)==sizeof(bits));
        std::memcpy(&bits,&value,sizeof(bits));return bits;
    };
    const auto as_float=[](std::uint32_t bits){
        float value=0;std::memcpy(&value,&bits,sizeof(value));return value;
    };
    for(const auto v:flows)
        if(!std::isfinite(v)||std::fabs(v)>8.0f)
            return fail("native mirror field: nonfinite/unbounded signed pair source");
    for(std::uint32_t i=0;i<flows.size();++i)
        if(!write_word(kFlow+i,as_bits(flows[i])))
            return fail("native mirror field: C(256,2) pair-flow transport failed");
    const std::array<std::uint32_t,3> args={510u,expected_epoch,current_epoch};
    for(std::uint32_t i=0;i<args.size();++i)
        if(!write_word(kProposalBase+i,args[i]))
            return fail("native mirror field: epoch transport failed");
    if(!write_word(kCommandBase,115u)||!run_command())
        return fail("native mirror field: fused guest failed: "+error_);
    const auto ok=read_word(kResultBase);
    const auto count=read_word(kResultBase+1);
    const auto hot=read_word(kResultBase+2);
    const auto code=read_word(kResultBase+3);
    if(ok==0u){
        if(count||hot||code<1u||code>4u)
            return fail("native mirror field: malformed rejection");
        reason=static_cast<std::uint8_t>(code);return true;
    }
    if(ok!=1u||count!=510u||hot>510u||code!=0u)
        return fail("native mirror field: wrong sample/field report");
    measured.reserve(510u);
    std::uint32_t computed_hot_majority=0;
    for(std::uint32_t t=0;t<510u;++t){
        NativeMirrorTriangleReceipt v{};
        v.sample_index=static_cast<std::uint16_t>(t);
        const std::uint32_t base=kRecords+(t<<5u);
        for(std::uint32_t d=0;d<32u;++d)
            v.native_record_words[d]=read_word(base+d);
        const auto& w=v.native_record_words;
        if(w[0]>=255u||w[1]>=255u||w[2]>=255u||
           w[0]==w[1]||w[0]==w[2]||w[1]==w[2]||
           w[3]!=(t>=255u?1u:0u)||w[4]>7u||w[5]>7u||
           (w[4]&w[5])!=0u||w[6]>3u||w[7]>3u||
           w[6]+w[7]>3u||w[9]!=(w[6]==3u?1u:0u)||
           w[10]!=(w[7]==3u?1u:0u)||w[26]!=expected_epoch||
           w[27]!=255u||w[28]!=0u||w[29]!=0u||
           w[30]!=0u||w[31]!=0u)
            return fail("native mirror field: malformed native triangle record");
        const auto majority=static_cast<std::int32_t>(w[8]);
        if(majority!=(w[6]>=2u?1:w[7]>=2u?-1:0))
            return fail("native mirror field: HOT/COLD majority drift");
        v.anchors={static_cast<std::uint8_t>(w[0]),
                   static_cast<std::uint8_t>(w[1]),
                   static_cast<std::uint8_t>(w[2])};
        v.family=static_cast<std::uint8_t>(w[3]);
        v.hot_mask=static_cast<std::uint8_t>(w[4]);
        v.cold_mask=static_cast<std::uint8_t>(w[5]);
        v.hot_count=static_cast<std::uint8_t>(w[6]);
        v.cold_count=static_cast<std::uint8_t>(w[7]);
        v.majority_sign=majority;
        v.unanimous_hot=w[9]==1u;v.unanimous_cold=w[10]==1u;
        v.loop_curl=as_float(w[11]);
        v.directed_edges={as_float(w[12]),as_float(w[13]),as_float(w[14])};
        v.native_reconstruction=as_float(w[15]);
        v.native_residual=as_float(w[16]);
        for(unsigned d=0;d<3u;++d)
            v.palindrome_addresses[d]=static_cast<std::uint16_t>(w[17u+d]);
        for(unsigned d=0;d<6u;++d)
            v.directed_mirror_addresses[d]=static_cast<std::uint16_t>(w[20u+d]);
        for(unsigned d=11u;d<=16u;++d)
            if(!std::isfinite(as_float(w[d])))
                return fail("native mirror field: nonfinite measured gradient/curl");
        for(unsigned d=17u;d<=25u;++d)
            if(w[d]>65535u)
                return fail("native mirror field: physical address overflow");
        v.source_generation=expected_epoch;
        v.measured=true;
        computed_hot_majority+=v.hot_count>=2u?1u:0u;
        measured.push_back(v);
    }
    if(computed_hot_majority!=hot)
        return fail("native mirror field: 510 guest vote report mismatch");
    hot_majority=static_cast<std::uint16_t>(hot);
    accepted=true;return true;
}

bool RawFieldVM::native_mirror_triangle_project(
    std::uint16_t sample_index,std::uint32_t source_epoch,
    NativeMirrorTriangleReceipt& receipt) {
    if(!vm_||sample_index>=510u||!receipt.measured||
       receipt.sample_index!=sample_index||
       receipt.source_generation!=source_epoch)
        return fail("native mirror Poincare128: missing matching source measurement");
    if(!write_word(kProposalBase,sample_index)||
       !write_word(kProposalBase+1u,source_epoch)||
       !write_word(kCommandBase,116u)||!run_command())
        return fail("native mirror Poincare128: guest execution failed: "+error_);
    const auto ok=read_word(kResultBase);
    const auto width=read_word(kResultBase+1);
    const auto reason=read_word(kResultBase+3);
    if(ok==0u){
        if(width!=0u||reason<1u||reason>4u)
            return fail("native mirror Poincare128: malformed rejection");
        receipt.projected=false;return true;
    }
    if(ok!=1u||width!=128u||reason!=0u)
        return fail("native mirror Poincare128: malformed native projection");
    const auto decode=[](std::uint32_t bits){
        float v=0;std::memcpy(&v,&bits,sizeof(v));return v;
    };
    const std::uint32_t base=0x00360000u+(std::uint32_t(sample_index)<<5u);
    for(unsigned d=28u;d<32u;++d)
        receipt.native_record_words[d]=read_word(base+d);
    if(receipt.native_record_words[31]!=1u)
        return fail("native mirror Poincare128: missing guest acceptance stamp");
    receipt.poincare_radius=decode(receipt.native_record_words[28]);
    receipt.poincare_depth=decode(receipt.native_record_words[29]);
    receipt.signed_curl_radial_feedback=decode(receipt.native_record_words[30]);
    if(!std::isfinite(receipt.poincare_radius)||receipt.poincare_radius<0.0f||
       receipt.poincare_radius>=1.0f||!std::isfinite(receipt.poincare_depth)||
       receipt.poincare_depth<0.0f||
       !std::isfinite(receipt.signed_curl_radial_feedback))
        return fail("native mirror Poincare128: nonfinite geometry");
    for(unsigned d=0;d<128u;++d){
        const float v=decode(read_word(0x00371000u+d));
        if(!std::isfinite(v)||std::fabs(v)>1.0f)
            return fail("native mirror Poincare128: nonfinite vector dimension");
        receipt.poincare_vector[d]=v;
    }
    receipt.projected=true;return true;
}

bool RawFieldVM::native_mirror_triangle_recover(
    std::uint16_t sample_index,std::uint32_t epoch,
    const std::array<float,32640>& current_flows,
    NativeMirrorTriangleRecoveryReceipt& receipt) {
    receipt={};
    if(!vm_||sample_index>=510u)
        return fail("native mirror repair: invalid guest/triangle index");
    for(float flow:current_flows)
        if(!std::isfinite(flow)||std::fabs(flow)>8.0f)
            return fail("native mirror repair: malformed current signed rail source");
    for(unsigned i=0;i<32640u;++i){
        std::uint32_t bits=0;
        std::memcpy(&bits,&current_flows[i],sizeof(bits));
        if(!write_word(0x003A0000u+i,bits))
            return fail("native mirror repair: current observed rail transport failed");
    }
    if(!write_word(kProposalBase,sample_index)||
       !write_word(kProposalBase+1u,epoch)||
       !write_word(kCommandBase,117u)||!run_command())
        return fail("native mirror repair: guest execution failed: "+error_);
    const auto ok=read_word(kResultBase);
    const auto reason=read_word(kResultBase+3);
    if(ok==0u){
        if(read_word(kResultBase+1)||read_word(kResultBase+2)||
           reason<1u||reason>3u)
            return fail("native mirror repair: malformed native refusal");
        receipt.rejection_reason=static_cast<std::uint8_t>(reason);
        return true;
    }
    if(ok!=1u||reason!=0u)
        return fail("native mirror repair: malformed success receipt");
    const auto decode=[](std::uint32_t bits){
        float v=0;std::memcpy(&v,&bits,sizeof(v));return v;
    };
    receipt.reconstructed_edge=decode(read_word(0x00374000u));
    receipt.current_edge=decode(read_word(0x00374001u));
    receipt.residual=decode(read_word(0x00374002u));
    receipt.source_generation=read_word(0x00374003u);
    if(!std::isfinite(receipt.reconstructed_edge)||
       !std::isfinite(receipt.current_edge)||
       !std::isfinite(receipt.residual)||receipt.source_generation!=epoch)
        return fail("native mirror repair: corrupt candidate recovery receipt");
    receipt.accepted=true;return true;
}

bool RawFieldVM::native_hyperedge128_depth(
    const std::array<float,128>& sourced_vector,
    const std::array<std::uint8_t,3>& ordered_hyperedge,
    float native_hodge_curl, std::uint32_t expected_generation,
    std::uint32_t current_generation,
    NativeHyperedge128Receipt& receipt) {
    receipt = {};
    if (!vm_) return fail("native hyperedge128: VM not loaded");
    constexpr std::uint32_t source_base=0x003E5000u;
    constexpr std::uint32_t output_base=0x003E5200u;
    constexpr std::uint32_t record_base=0x003E5400u;
    constexpr std::uint32_t meta_base=0x003E5500u;
    auto as_bits=[](float value) {
        std::uint32_t bits=0;
        static_assert(sizeof(bits)==sizeof(value));
        std::memcpy(&bits,&value,sizeof(bits));
        return bits;
    };
    auto as_float=[](std::uint32_t bits) {
        float value=0.0f;
        std::memcpy(&value,&bits,sizeof(bits));
        return value;
    };
    // Transport all 128 observed source components into guest-owned math.
    // The caller must verify provenance and that these belong to the same
    // admitted Hodge/topology/epoch. The guest only validates numeric shape.
    for (std::uint32_t d=0;d<128u;++d)
        if (!write_word(source_base+d,as_bits(sourced_vector[d])))
            return fail("native hyperedge128: input transport failed");
    const std::array<std::uint32_t,8> record={
        ordered_hyperedge[0],ordered_hyperedge[1],ordered_hyperedge[2],
        as_bits(native_hodge_curl),expected_generation,current_generation,
        255u,1u};
    for (std::uint32_t i=0;i<record.size();++i)
        if (!write_word(record_base+i,record[i]))
            return fail("native hyperedge128: evidence transport failed");
    if (!write_word(kCommandBase,108u) || !run_command())
        return fail("native hyperedge128: guest dispatch failed: "+error_);
    const auto accepted=read_word(kResultBase);
    const auto count=read_word(kResultBase+1);
    const auto sign=read_word(kResultBase+2);
    const auto reason=read_word(kResultBase+3);
    if (accepted==0u) {
        if (count!=0u||sign!=0u||reason<1u||reason>4u)
            return fail("native hyperedge128: malformed guest rejection");
        receipt.rejection_reason=static_cast<std::uint8_t>(reason);
        return true;
    }
    if (accepted!=1u||count!=128u||reason!=0u)
        return fail("native hyperedge128: malformed guest approval");
    const auto orientation=static_cast<std::int32_t>(sign);
    const auto orientation_meta=static_cast<std::int32_t>(read_word(meta_base+3));
    const auto now=read_word(meta_base+4);
    if ((orientation!=-1&&orientation!=0&&orientation!=1) ||
        orientation_meta!=orientation || now!=255u)
        return fail("native hyperedge128: orientation/VOID identity drift");
    const float radius=as_float(read_word(meta_base+0));
    const float depth=as_float(read_word(meta_base+1));
    const float feedback=as_float(read_word(meta_base+2));
    if (!std::isfinite(radius)||!std::isfinite(depth)||
        !std::isfinite(feedback)||radius<0||radius>=1||
        depth<0||std::fabs(feedback)>8.0f)
        return fail("native hyperedge128: nonfinite or nonball measurement");
    // Validation only; Poincare and curl math happened inside NaN16.
    for (std::uint32_t d=0;d<128u;++d) {
        const float value=as_float(read_word(output_base+d));
        if (!std::isfinite(value)||std::fabs(value)>=1.0f)
            return fail("native hyperedge128: invalid projected component");
        receipt.poincare_vector[d]=value;
    }
    receipt.accepted=true;
    receipt.radius=radius;
    receipt.radial_distance=depth;
    receipt.signed_curl_feedback=feedback;
    receipt.orientation=orientation;
    receipt.now_head=static_cast<std::uint8_t>(now);
    return true;
}

bool RawFieldVM::native_spectral_tensor_propose(
    const std::array<std::int64_t,256>& spectral_q16_i64,
    const std::array<std::uint8_t,85>& trihead_masks,
    const std::array<std::array<std::uint8_t,2>,255>& directed_pairs,
    const std::array<std::uint8_t,255>& writer_capabilities,
    std::uint32_t expected_generation, std::uint32_t current_generation,
    bool global_approved, bool meta_approved,
    NativeSpectralTensorResult& result) {
    result = {};
    if (!vm_) return fail("native spectral tensor: VM not loaded");
    // The host only serializes a verified observation envelope; the guest
    // performs all mathematical acceptance, voting and directed mapping.
    constexpr std::uint32_t spectral_base=0x003D0000u;
    constexpr std::uint32_t trihead_base=0x003D0400u;
    constexpr std::uint32_t pair_base=0x003D0500u;
    constexpr std::uint32_t writer_base=0x003D0800u;
    constexpr std::uint32_t output_base=0x003D1000u;
    for (std::size_t h=0;h<spectral_q16_i64.size();++h) {
        const std::uint64_t bits=static_cast<std::uint64_t>(spectral_q16_i64[h]);
        if (!write_word(spectral_base+static_cast<std::uint32_t>(2*h),
                        static_cast<std::uint32_t>(bits)) ||
            !write_word(spectral_base+static_cast<std::uint32_t>(2*h+1),
                        static_cast<std::uint32_t>(bits>>32u)))
            return fail("native spectral tensor: cannot transmit I64 input");
    }
    for (std::size_t t=0;t<trihead_masks.size();++t)
        if (!write_word(trihead_base+static_cast<std::uint32_t>(t),trihead_masks[t]))
            return fail("native spectral tensor: cannot transmit trihead mask");
    for (std::size_t h=0;h<directed_pairs.size();++h) {
        const std::uint32_t j=static_cast<std::uint32_t>(h);
        if (!write_word(pair_base+2u*j,directed_pairs[h][0]) ||
            !write_word(pair_base+2u*j+1u,directed_pairs[h][1]) ||
            !write_word(writer_base+j,writer_capabilities[h]))
            return fail("native spectral tensor: cannot transmit candidate coordinates");
    }
    if (!write_word(kProposalBase+0,expected_generation) ||
        !write_word(kProposalBase+1,current_generation) ||
        !write_word(kProposalBase+2,global_approved?1u:0u) ||
        !write_word(kProposalBase+3,meta_approved?1u:0u) ||
        !write_word(kCommandBase,106u))
        return fail("native spectral tensor: cannot transmit generation and gate");
    if (!run_command()) return false;
    const auto status=read_word(kResultBase+0);
    const auto approved=read_word(kResultBase+1);
    const auto count=read_word(kResultBase+2);
    const auto reason=read_word(kResultBase+3);
    if (status==0u) {
        if (approved!=0u||count!=0u||reason<1u||reason>5u)
            return fail("native spectral tensor: malformed guest reject receipt");
        result.rejection_reason=static_cast<std::uint8_t>(reason);
        return true;
    }
    if (status!=1u||reason!=0u||approved<43u||approved>85u||
        count==0u||count>255u)
        return fail("native spectral tensor: malformed guest approval receipt");
    result.accepted_triads=static_cast<std::uint16_t>(approved);
    std::array<bool,255> seen{};
    for (std::uint32_t i=0;i<count;++i) {
        const auto base=output_base+5u*i;
        const auto h=read_word(base+0);
        const auto a=read_word(base+1);
        const auto b=read_word(base+2);
        const auto offset=read_word(base+3);
        const auto credit=read_word(base+4);
        if (h>=255u||a>=255u||b>=255u||seen[h]||
            writer_capabilities[h]!=1u||
            a!=directed_pairs[h][0]||b!=directed_pairs[h][1]||
            offset<67108864u||offset>=134217728u||
            (offset&3u)!=0u)
            return fail("native spectral tensor: invalid candidate bank receipt");
        seen[h]=true;
        result.records.push_back({
            static_cast<std::uint8_t>(h),
            static_cast<std::uint8_t>(a),
            static_cast<std::uint8_t>(b),
            offset,
            static_cast<std::int32_t>(credit)});
    }
    result.accepted=true;
    return true;
}

bool RawFieldVM::fail(const std::string& message) {
    error_ = message;
    return false;
}

bool RawFieldVM::write_word(std::uint32_t index, std::uint32_t payload) {
    const std::uint8_t bytes[4] = {
        static_cast<std::uint8_t>(payload & 0xFFu),
        static_cast<std::uint8_t>((payload >> 8) & 0xFFu),
        static_cast<std::uint8_t>((payload >> 16) & 0xFFu),
        static_cast<std::uint8_t>((payload >> 24) & 0xFFu),
    };
    return nan_write_bytes(vm_, index * 4u, bytes, sizeof(bytes)) == 0;
}

std::uint32_t RawFieldVM::read_word(std::uint32_t index) const {
    return static_cast<std::uint32_t>(nan_word(vm_, index) >> 16u);
}

bool RawFieldVM::run_command() {
    if (!vm_) return fail("raw field VM is not loaded");
    nan_set_pc(vm_, 0);
    nan_set_reg(vm_, 13, 1);
    const int rc = nan_run(vm_, command_step_budget());
    if (rc != NAN_HALTED) {
        return fail("raw field driver did not halt: " +
                    std::string(nan_strerror(rc)));
    }
    const char* trap = nan_trap_text(vm_);
    if (trap && *trap) return fail("raw field driver trap: " + std::string(trap));
    return true;
}

bool RawFieldVM::triad_score(std::uint16_t m0, std::uint16_t m1,
                             std::uint16_t m2, std::uint32_t a,
                             std::uint32_t b, bool target,
                             std::int32_t& score) {
    if (!write_word(kProposalBase + 0, m0) ||
        !write_word(kProposalBase + 1, m1) ||
        !write_word(kProposalBase + 2, m2) ||
        !write_word(kProposalBase + 3, a) ||
        !write_word(kProposalBase + 4, b) ||
        !write_word(kProposalBase + 5, target ? 1u : 0u) ||
        !write_word(kCommandBase, 45))
        return fail("cannot write triad score command");
    if (!run_command()) return false;
    score = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}

bool RawFieldVM::proposal(std::uint16_t current_mask, std::uint16_t patch,
                          const std::array<std::uint16_t, 3>& members,
                          std::uint32_t a, std::uint32_t b, bool target,
                          RawProposalResult& out) {
    if (!write_word(kCommandBase, 1) ||
        !write_word(kProposalBase + 0, current_mask) ||
        !write_word(kProposalBase + 1, patch) ||
        !write_word(kProposalBase + 2, members[0]) ||
        !write_word(kProposalBase + 3, members[1]) ||
        !write_word(kProposalBase + 4, members[2]) ||
        !write_word(kProposalBase + 5, a) ||
        !write_word(kProposalBase + 6, b) ||
        !write_word(kProposalBase + 7, target ? 1u : 0u)) {
        return fail("cannot write raw proposal command");
    }
    if (!run_command()) return false;
    out.votes = static_cast<std::uint8_t>(read_word(kResultBase + 0) & 7u);
    out.accepted = (read_word(kResultBase + 1) & 1u) != 0;
    out.candidate_mask = static_cast<std::uint16_t>(read_word(kResultBase + 2));
    out.candidate_rule = static_cast<std::uint8_t>(read_word(kResultBase + 3) & 15u);
    return true;
}


bool RawFieldVM::dual_gate(bool fast_accepted, bool slow_accepted,
                           bool field_accepted, std::int32_t coherence,
                           std::int32_t threshold,
                           std::uint16_t current_mask,
                           std::uint16_t patch, DualProposalResult& out) {
    if (!write_word(kProposalBase + 0, fast_accepted ? 1u : 0u) ||
        !write_word(kProposalBase + 1, slow_accepted ? 1u : 0u) ||
        !write_word(kProposalBase + 2, field_accepted ? 1u : 0u) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(coherence)) ||
        !write_word(kProposalBase + 4, static_cast<std::uint32_t>(threshold)) ||
        !write_word(kProposalBase + 5, current_mask) ||
        !write_word(kProposalBase + 6, patch) ||
        !write_word(kCommandBase, 87)) {
        return fail("cannot write dual-gate command");
    }
    if (!run_command()) return false;
    out.committed = (read_word(kResultBase + 0) & 1u) != 0;
    out.committed_mask = static_cast<std::uint16_t>(read_word(kResultBase + 1));
    out.fast_credit = static_cast<std::int32_t>(read_word(kResultBase + 2));
    out.slow_credit = static_cast<std::int32_t>(read_word(kResultBase + 3));
    out.medium_credit = static_cast<std::int32_t>(read_word(kResultBase + 4));
    return true;
}

bool RawFieldVM::propose_dual(Universe& universe, HeadArray& heads,
                              std::uint8_t fast_head, std::uint8_t slow_head,
                              std::uint16_t patch, std::uint32_t a,
                              std::uint32_t b, bool target,
                              std::int32_t coherence_threshold,
                              DualProposalResult& out) {
    if (fast_head >= kTriadMemberCount || slow_head >= kTriadMemberCount)
        return fail("dual proposer is not a triad head");
    auto members_for = [&](std::uint8_t head, std::array<std::uint16_t, 3>& m) {
        const std::uint8_t triad = universe.triad_index(head);
        if (triad >= kTriadCount) return false;
        const std::size_t base = static_cast<std::size_t>(triad) * kTriadSize;
        const auto& table = universe.triad_members();
        m = {heads.at(table[base]).boolean_mask(),
             heads.at(table[base + 1]).boolean_mask(),
             heads.at(table[base + 2]).boolean_mask()};
        return true;
    };
    std::array<std::uint16_t, 3> fast_members{}, slow_members{};
    if (!members_for(fast_head, fast_members) ||
        !members_for(slow_head, slow_members)) return fail("dual triad missing");
    HeadView fast_view = heads.at(fast_head);
    HeadView slow_view = heads.at(slow_head);
    if (!proposal(fast_view.boolean_mask(), patch, fast_members, a, b, target,
                  out.fast) ||
        !proposal(slow_view.boolean_mask(), patch, slow_members, a, b, target,
                  out.slow)) return false;

    std::uint16_t field_count = 0;
    if (!field_vote(universe.triad_votes(), field_count, out.field_accepted))
        return false;
    std::array<std::uint16_t, kTriadMemberCount> phases{};
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        for (std::size_t s = 0; s < kTriadSize; ++s) {
            const std::uint8_t h = universe.triad_members()[t * kTriadSize + s];
            phases[t * kTriadSize + s] =
                static_cast<std::uint16_t>(universe.head(h).phase & 0xFFFFu);
        }
    }
    std::int32_t coherence_q16 = 0;
    if (!coherence(phases, coherence_q16)) return false;
    out.slow_ok = coherence_q16 >= coherence_threshold;
    if (!dual_gate(out.fast.accepted, out.slow.accepted, out.field_accepted,
                   coherence_q16, coherence_threshold, slow_view.boolean_mask(),
                   patch, out)) return false;
    if (out.committed) {
        if (!slow_view.self_modify_boolean(patch))
            return fail("dual proposal committed but slow head is not writable");
    }
    bump_triad_credit(universe.head_credit()[fast_head], out.fast_credit);
    bump_triad_credit(universe.head_credit()[slow_head], out.slow_credit);
    return true;
}

bool RawFieldVM::propose(Universe& universe, HeadArray& heads,
                         std::uint8_t proposer, std::uint16_t patch,
                         std::uint32_t a, std::uint32_t b, bool target,
                         RawProposalResult& out) {
    if (proposer >= kTriadMemberCount) return fail("proposer is not a triad head");
    HeadView view = heads.at(proposer);
    const std::uint8_t triad = universe.triad_index(proposer);
    if (triad >= kTriadCount) return fail("proposer has no triad");
    const std::size_t base = static_cast<std::size_t>(triad) * kTriadSize;
    const auto& table = universe.triad_members();
    std::array<std::uint16_t, 3> members = {
        heads.at(table[base]).boolean_mask(),
        heads.at(table[base + 1]).boolean_mask(),
        heads.at(table[base + 2]).boolean_mask(),
    };
    if (!proposal(view.boolean_mask(), patch, members, a, b, target, out))
        return false;
    if (out.accepted) {
        if (!view.self_modify_boolean(patch))
            return fail("raw proposal accepted but head is not writable");
    }
    bump_triad_credit(universe.head_credit()[proposer], out.accepted ? 1 : -1);
    bump_triad_credit(universe.triad_credit()[triad], out.accepted ? 1 : -1);
    if (!field_vote(universe)) return false;
    if (!coherence(universe)) return false;
    return true;
}

bool RawFieldVM::auto_remap(Universe& universe, HeadArray& heads,
                             std::uint32_t seed, std::uint32_t a,
                             std::uint32_t b, bool target,
                             AutoRemapResult& out) {
    std::array<std::uint8_t, kTriadCount> order{};
    std::iota(order.begin(), order.end(), 0);
    std::stable_sort(order.begin(), order.end(), [&](std::uint8_t x,
                                                     std::uint8_t y) {
        return universe.triad_credit()[x] < universe.triad_credit()[y];
    });
    out.triad_a = order[0];
    out.triad_b = order[1];
    out.slot_a = static_cast<std::uint8_t>((seed >> 8) % kTriadSize);
    out.slot_b = static_cast<std::uint8_t>((seed >> 16) % kTriadSize);
    out.attempted = true;
    return remap_chart(universe, heads, out.triad_a, out.slot_a,
                       out.triad_b, out.slot_b, a, b, target,
                       out.improved, out.before, out.after);
}

bool RawFieldVM::field_vote(const std::array<std::uint8_t, kTriadCount>& masks,
                            std::uint16_t& accepted_count,
                            bool& field_accepted) {
    for (std::size_t i = 0; i < masks.size(); ++i) {
        if (!write_word(kFieldMasks + static_cast<std::uint32_t>(i), masks[i])) {
            return fail("cannot write field vote masks");
        }
    }
    if (!write_word(kCommandBase, 2)) return fail("cannot write field vote command");
    if (!run_command()) return false;
    accepted_count = static_cast<std::uint16_t>(read_word(kResultBase + 0));
    field_accepted = (read_word(kResultBase + 1) & 1u) != 0;
    return true;
}

bool RawFieldVM::coherence(
    const std::array<std::uint16_t, kTriadMemberCount>& phases,
    std::int32_t& q16) {
    for (std::size_t i = 0; i < phases.size(); ++i) {
        if (!write_word(kCoherencePhases + static_cast<std::uint32_t>(i),
                        phases[i])) {
            return fail("cannot write coherence phases");
        }
    }
    if (!write_word(kCommandBase, 3)) return fail("cannot write coherence command");
    if (!run_command()) return false;
    q16 = static_cast<std::int32_t>(read_word(kResultBase + 0));
    return true;
}



bool RawFieldVM::context_encode(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions,
    const std::vector<std::array<float, kRawFeatureDim>>& word_embeddings,
    const std::array<std::array<float, kRawFeatureDim>, 4>& position_gates,
    const std::array<float, kRawFeatureDim>& bias,
    const std::array<float, kRawFeatureDim>& order, float orientation,
    std::array<float, kRawFeatureDim>& out) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count ||
        word_embeddings.size() < 64) {
        return fail("context encoder dimensions invalid");
    }
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t i = 0; i < token_count; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i])) {
            return fail("cannot write context token");
        }
    }
    for (std::size_t t = 0; t < 64; ++t)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7100u + static_cast<std::uint32_t>(t * 8 + d),
                    word_embeddings[t][d])) return fail("cannot write word embedding");
    for (std::size_t p = 0; p < 4; ++p)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7300u + static_cast<std::uint32_t>(p * 8 + d),
                    position_gates[p][d])) return fail("cannot write position gate");
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        if (!wf(0x7380u + static_cast<std::uint32_t>(d), bias[d]) ||
            !wf(0x7390u + static_cast<std::uint32_t>(d), order[d])) {
            return fail("cannot write context bias");
        }
    }
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 50)) {
        return fail("cannot write context-encode command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != kRawFeatureDim) return fail("context encode count");
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        const std::uint32_t bits = read_word(0x73A0u + static_cast<std::uint32_t>(d));
        std::memcpy(&out[d], &bits, sizeof(bits));
    }
    return true;
}




bool RawFieldVM::sense_step(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions,
    const std::vector<std::array<float, kRawFeatureDim>>& word_embeddings,
    const std::array<std::array<float, kRawFeatureDim>, 4>& position_gates,
    const std::array<float, kRawFeatureDim>& bias,
    const std::array<float, kRawFeatureDim>& order,
    const std::vector<std::array<float, kRawFeatureDim>>& sense_heads,
    const std::vector<float>& sense_bias, std::size_t target,
    float learning_rate, float orientation, float& probability, float& loss) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count || word_embeddings.size() < 64 ||
        sense_heads.empty() || sense_heads.size() > 8 ||
        sense_bias.size() != sense_heads.size() || target >= sense_heads.size()) {
        return fail("sense-step dimensions invalid");
    }
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t i = 0; i < token_count; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i]))
            return fail("cannot write sense tokens");
    for (std::size_t i = 0; i < 64; ++i)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7100u + static_cast<std::uint32_t>(i * 8 + d),
                    word_embeddings[i][d])) return fail("cannot write sense embeddings");
    for (std::size_t p = 0; p < 4; ++p)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7300u + static_cast<std::uint32_t>(p * 8 + d),
                    position_gates[p][d])) return fail("cannot write sense gates");
    for (std::size_t d = 0; d < kRawFeatureDim; ++d)
        if (!wf(0x7380u + static_cast<std::uint32_t>(d), bias[d]) ||
            !wf(0x7390u + static_cast<std::uint32_t>(d), order[d]))
            return fail("cannot write sense vectors");
    for (std::size_t k = 0; k < sense_heads.size(); ++k) {
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7600u + static_cast<std::uint32_t>(k * 8 + d),
                    sense_heads[k][d])) return fail("cannot write sense head");
        if (!wf(0x7700u + static_cast<std::uint32_t>(k), sense_bias[k]))
            return fail("cannot write sense bias");
    }
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!wf(0x7522u, learning_rate) ||
        !write_word(0x4003u, static_cast<std::uint32_t>(sense_heads.size())) ||
        !write_word(0x7523u, static_cast<std::uint32_t>(target)) ||
        !write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 52)) return fail("cannot write sense-step command");
    if (!run_command()) return false;
    const std::uint32_t pbits = read_word(kResultBase);
    const std::uint32_t lbits = read_word(kResultBase + 1);
    std::memcpy(&probability, &pbits, sizeof(pbits));
    std::memcpy(&loss, &lbits, sizeof(lbits));
    return true;
}
bool RawFieldVM::read_sense_state(
    std::size_t count, std::vector<std::array<float, kRawFeatureDim>>& heads,
    std::vector<float>& biases) const {
    if (count == 0 || count > 8) return false;
    heads.assign(count, {});
    biases.assign(count, 0.0f);
    for (std::size_t k = 0; k < count; ++k) {
        for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
            const std::uint32_t bits = read_word(0x7600u + static_cast<std::uint32_t>(k * 8 + d));
            std::memcpy(&heads[k][d], &bits, sizeof(bits));
        }
        const std::uint32_t bits = read_word(0x7700u + static_cast<std::uint32_t>(k));
        std::memcpy(&biases[k], &bits, sizeof(bits));
    }
    return true;
}


bool RawFieldVM::semantic_query(
    const std::vector<std::pair<std::uint8_t, std::uint8_t>>& isa_edges,
    const std::vector<std::pair<std::uint8_t, std::uint8_t>>& negative_isa,
    const std::vector<SemanticAbility>& abilities,
    std::uint8_t query_type, std::uint8_t subject,
    std::uint8_t object_or_action, std::uint8_t& state,
    std::uint8_t& depth) {
    if (isa_edges.size() > 64 || negative_isa.size() > 32 ||
        abilities.size() > 64 || subject >= 32 || object_or_action >= 32) {
        return fail("semantic query bounds invalid");
    }
    for (std::size_t i = 0; i < isa_edges.size(); ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(2 * i), isa_edges[i].first) ||
            !write_word(0x7001u + static_cast<std::uint32_t>(2 * i), isa_edges[i].second))
            return fail("cannot write semantic ISA edges");
    }
    for (std::size_t i = 0; i < negative_isa.size(); ++i) {
        if (!write_word(0x7100u + static_cast<std::uint32_t>(2 * i), negative_isa[i].first) ||
            !write_word(0x7101u + static_cast<std::uint32_t>(2 * i), negative_isa[i].second))
            return fail("cannot write semantic negative edges");
    }
    for (std::size_t i = 0; i < abilities.size(); ++i) {
        if (!write_word(0x7200u + static_cast<std::uint32_t>(3 * i), abilities[i].subject) ||
            !write_word(0x7201u + static_cast<std::uint32_t>(3 * i), abilities[i].action) ||
            !write_word(0x7202u + static_cast<std::uint32_t>(3 * i), abilities[i].positive))
            return fail("cannot write semantic abilities");
    }
    if (!write_word(0x7300u, query_type) ||
        !write_word(0x7301u, subject) ||
        !write_word(0x7302u, object_or_action) ||
        !write_word(0x4001u, static_cast<std::uint32_t>(isa_edges.size())) ||
        !write_word(0x4002u, static_cast<std::uint32_t>(negative_isa.size())) ||
        !write_word(0x4003u, static_cast<std::uint32_t>(abilities.size())) ||
        !write_word(kCommandBase, 53)) return fail("cannot write semantic query command");
    if (!run_command()) return false;
    state = static_cast<std::uint8_t>(read_word(kResultBase) & 3u);
    depth = static_cast<std::uint8_t>(read_word(kResultBase + 1) & 0xFFu);
    return true;
}

bool RawFieldVM::read_role_state(std::array<float, kRawFeatureDim>& relation,
                                 float& relation_bias) const {
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        const std::uint32_t bits = read_word(0x7500u + static_cast<std::uint32_t>(d));
        std::memcpy(&relation[d], &bits, sizeof(bits));
    }
    const std::uint32_t bits = read_word(0x7520u);
    std::memcpy(&relation_bias, &bits, sizeof(bits));
    return true;
}


bool RawFieldVM::init_context24(
    const std::vector<std::array<float, 24>>& word_embeddings,
    const std::array<std::array<float, 24>, 4>& position_gates,
    const std::array<float, 24>& bias,
    const std::array<float, 24>& order) {
    if (word_embeddings.size() < 64) return fail("context24 embeddings short");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t t = 0; t < 64; ++t)
        for (std::size_t d = 0; d < 24; ++d)
            if (!wf(0x8000u + static_cast<std::uint32_t>(t * 24 + d),
                    word_embeddings[t][d])) return fail("init context24 embedding");
    for (std::size_t p = 0; p < 4; ++p)
        for (std::size_t d = 0; d < 24; ++d)
            if (!wf(0x8600u + static_cast<std::uint32_t>(p * 24 + d),
                    position_gates[p][d])) return fail("init context24 gate");
    for (std::size_t d = 0; d < 24; ++d)
        if (!wf(0x8700u + static_cast<std::uint32_t>(d), bias[d]) ||
            !wf(0x8720u + static_cast<std::uint32_t>(d), order[d]))
            return fail("init context24 vector");
    return true;
}

bool RawFieldVM::init_role24(const std::array<float, 24>& relation,
                             float relation_bias) {
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t d = 0; d < 24; ++d)
        if (!wf(0x8760u + static_cast<std::uint32_t>(d), relation[d]))
            return fail("init role24 relation");
    return wf(0x8780u, relation_bias);
}


bool RawFieldVM::init_role24k(
    const std::vector<std::array<float, 24>>& relation_heads,
    const std::vector<float>& relation_bias) {
    if (relation_heads.empty() || relation_heads.size() > 8 ||
        relation_bias.size() != relation_heads.size())
        return fail("role24k init bounds");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t k = 0; k < relation_heads.size(); ++k) {
        for (std::size_t d = 0; d < 24; ++d)
            if (!wf(0x8A00u + static_cast<std::uint32_t>(k * 24 + d),
                    relation_heads[k][d])) return fail("role24k head");
        if (!wf(0x8C00u + static_cast<std::uint32_t>(k), relation_bias[k]))
            return fail("role24k bias");
    }
    return write_word(0x8C08u, static_cast<std::uint32_t>(relation_heads.size()));
}




bool RawFieldVM::read_context24(
    std::vector<std::array<float, 24>>& word_embeddings,
    std::array<std::array<float, 24>, 4>& position_gates,
    std::array<float, 24>& bias, std::array<float, 24>& order) {
    auto rf = [&](std::uint32_t index, float& value) {
        const std::uint32_t bits = read_word(index);
        std::memcpy(&value, &bits, sizeof(value));
    };
    word_embeddings.assign(64, {});
    for (std::size_t t = 0; t < 64; ++t)
        for (std::size_t d = 0; d < 24; ++d)
            rf(0x8000u + static_cast<std::uint32_t>(t * 24 + d),
               word_embeddings[t][d]);
    for (std::size_t p = 0; p < 4; ++p)
        for (std::size_t d = 0; d < 24; ++d)
            rf(0x8600u + static_cast<std::uint32_t>(p * 24 + d),
               position_gates[p][d]);
    for (std::size_t d = 0; d < 24; ++d) {
        rf(0x8700u + static_cast<std::uint32_t>(d), bias[d]);
        rf(0x8720u + static_cast<std::uint32_t>(d), order[d]);
    }
    return true;
}

bool RawFieldVM::read_sense24(
    std::vector<std::array<float, 24>>& heads, std::vector<float>& biases) {
    const std::uint32_t count = read_word(0x4003u);
    if (count == 0 || count > 8) return fail("sense24 state count");
    heads.assign(count, {});
    biases.assign(count, 0.0f);
    for (std::uint32_t k = 0; k < count; ++k) {
        for (std::uint32_t d = 0; d < 24; ++d) {
            const std::uint32_t bits = read_word(0x8800u + k * 24u + d);
            std::memcpy(&heads[k][d], &bits, sizeof(bits));
        }
        const std::uint32_t bits = read_word(0x8900u + k);
        std::memcpy(&biases[k], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::read_role24k_state(
    std::vector<std::array<float, 24>>& heads, std::vector<float>& biases) {
    const std::uint32_t count = read_word(0x8C08u);
    if (count == 0 || count > 8) return fail("role24k state count");
    heads.assign(count, {});
    biases.assign(count, 0.0f);
    for (std::uint32_t k = 0; k < count; ++k) {
        for (std::uint32_t d = 0; d < 24; ++d) {
            const std::uint32_t bits = read_word(0x8A00u + k * 24u + d);
            std::memcpy(&heads[k][d], &bits, sizeof(bits));
        }
        const std::uint32_t bits = read_word(0x8C00u + k);
        std::memcpy(&biases[k], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::role_step24k_cached(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions, std::size_t target_relation,
    float label, float learning_rate, float orientation, float& probability,
    float& delta) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count) return fail("role24k token count");
    for (std::size_t i = 0; i < token_count; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i]))
            return fail("role24k tokens");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!wf(0x8781u, label) || !wf(0x8782u, learning_rate) ||
        !write_word(0x8C09u, static_cast<std::uint32_t>(target_relation)) ||
        !write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 57)) return fail("role24k command");
    if (!run_command()) return false;
    const std::uint32_t pbits = read_word(kResultBase);
    const std::uint32_t dbits = read_word(kResultBase + 1);
    std::memcpy(&probability, &pbits, sizeof(pbits));
    std::memcpy(&delta, &dbits, sizeof(dbits));
    return true;
}

bool RawFieldVM::role_step24_cached(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions, float label,
    float learning_rate, float orientation, float& probability, float& delta) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count) return fail("role24 token count");
    for (std::size_t i = 0; i < token_count; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i]))
            return fail("role24 tokens");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!wf(0x8781u, label) || !wf(0x8782u, learning_rate) ||
        !write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 55)) return fail("role24 command");
    if (!run_command()) return false;
    const std::uint32_t pbits = read_word(kResultBase);
    const std::uint32_t dbits = read_word(kResultBase + 1);
    std::memcpy(&probability, &pbits, sizeof(pbits));
    std::memcpy(&delta, &dbits, sizeof(dbits));
    return true;
}

bool RawFieldVM::init_sense24(
    const std::vector<std::array<float, 24>>& sense_heads,
    const std::vector<float>& sense_bias) {
    if (sense_heads.empty() || sense_heads.size() > 8 ||
        sense_bias.size() != sense_heads.size()) return fail("sense24 init bounds");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t k = 0; k < sense_heads.size(); ++k) {
        for (std::size_t d = 0; d < 24; ++d)
            if (!wf(0x8800u + static_cast<std::uint32_t>(k * 24 + d),
                    sense_heads[k][d])) return fail("sense24 head");
        if (!wf(0x8900u + static_cast<std::uint32_t>(k), sense_bias[k]))
            return fail("sense24 bias");
    }
    return write_word(0x4003u, static_cast<std::uint32_t>(sense_heads.size()));
}

bool RawFieldVM::sense_step24_cached(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions, std::size_t target,
    float learning_rate, float orientation, float& probability, float& loss) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count) return fail("sense24 token count");
    for (std::size_t i = 0; i < token_count; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i]))
            return fail("sense24 tokens");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!wf(0x8782u, learning_rate) ||
        !write_word(0x8783u, static_cast<std::uint32_t>(target)) ||
        !write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 56)) return fail("sense24 command");
    if (!run_command()) return false;
    const std::uint32_t pbits = read_word(kResultBase);
    const std::uint32_t lbits = read_word(kResultBase + 1);
    std::memcpy(&probability, &pbits, sizeof(pbits));
    std::memcpy(&loss, &lbits, sizeof(lbits));
    return true;
}

bool RawFieldVM::role_step(
    std::size_t token_count, const std::vector<std::uint8_t>& tokens,
    const std::vector<std::uint8_t>& positions,
    const std::vector<std::array<float, kRawFeatureDim>>& word_embeddings,
    const std::array<std::array<float, kRawFeatureDim>, 4>& position_gates,
    const std::array<float, kRawFeatureDim>& bias,
    const std::array<float, kRawFeatureDim>& order,
    const std::array<float, kRawFeatureDim>& relation,
    float relation_bias, float label, float learning_rate,
    float orientation, float& probability, float& delta) {
    if (token_count == 0 || token_count > 16 || tokens.size() != token_count ||
        positions.size() != token_count || word_embeddings.size() < 64) {
        return fail("role-step dimensions invalid");
    }
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t i = 0; i < token_count; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), tokens[i]) ||
            !write_word(0x7400u + static_cast<std::uint32_t>(i), positions[i]))
            return fail("cannot write role tokens");
    }
    for (std::size_t i = 0; i < 64; ++i)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7100u + static_cast<std::uint32_t>(i * 8 + d),
                    word_embeddings[i][d])) return fail("cannot write role embeddings");
    for (std::size_t p = 0; p < 4; ++p)
        for (std::size_t d = 0; d < kRawFeatureDim; ++d)
            if (!wf(0x7300u + static_cast<std::uint32_t>(p * 8 + d),
                    position_gates[p][d])) return fail("cannot write role gates");
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        if (!wf(0x7380u + static_cast<std::uint32_t>(d), bias[d]) ||
            !wf(0x7390u + static_cast<std::uint32_t>(d), order[d]) ||
            !wf(0x7500u + static_cast<std::uint32_t>(d), relation[d])) {
            return fail("cannot write role vectors");
        }
    }
    std::uint32_t obits = 0;
    std::memcpy(&obits, &orientation, sizeof(obits));
    if (!wf(0x7520u, relation_bias) || !wf(0x7521u, label) ||
        !wf(0x7522u, learning_rate) ||
        !write_word(kProposalBase + 0, static_cast<std::uint32_t>(token_count)) ||
        !write_word(kProposalBase + 1, obits) ||
        !write_word(kCommandBase, 51)) {
        return fail("cannot write role-step command");
    }
    if (!run_command()) return false;
    const std::uint32_t pbits = read_word(kResultBase);
    const std::uint32_t dbits = read_word(kResultBase + 1);
    std::memcpy(&probability, &pbits, sizeof(pbits));
    std::memcpy(&delta, &dbits, sizeof(dbits));
    return true;
}

bool RawFieldVM::holo(const std::array<std::uint16_t, 3>& phases,
                      std::array<std::int32_t, 2>& out) {
    for (std::size_t i = 0; i < phases.size(); ++i)
        if (!write_word(kProposalBase + static_cast<std::uint32_t>(i), phases[i]))
            return fail("cannot write HOLO phases");
    if (!write_word(kCommandBase, 35)) return fail("cannot write HOLO command");
    if (!run_command()) return false;
    out[0] = static_cast<std::int32_t>(read_word(kResultBase));
    out[1] = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}
bool RawFieldVM::ring(const std::array<std::uint16_t, kTriadMemberCount>& phases,
                      std::uint32_t shift, std::int32_t& correlation) {
    if (shift >= kTriadMemberCount) return fail("RING shift outside ring");
    for (std::size_t i = 0; i < phases.size(); ++i)
        if (!write_word(kCoherencePhases + static_cast<std::uint32_t>(i), phases[i]))
            return fail("cannot write RING phases");
    if (!write_word(kProposalBase, shift) || !write_word(kCommandBase, 36))
        return fail("cannot write RING command");
    if (!run_command()) return false;
    correlation = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}
bool RawFieldVM::leaf(std::uint32_t row_bits, std::uint32_t leaf_mask,
                      std::int32_t counter_q16, std::array<std::int32_t, 2>& out) {
    if (!write_word(kProposalBase, row_bits) ||
        !write_word(kProposalBase + 1, leaf_mask) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(counter_q16)) ||
        !write_word(kCommandBase, 37)) return fail("cannot write LEAF command");
    if (!run_command()) return false;
    out[0] = static_cast<std::int32_t>(read_word(kResultBase));
    out[1] = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}
bool RawFieldVM::tca(std::int32_t local, std::int32_t peer_a, std::int32_t peer_b,
                     std::int32_t& advantage) {
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(local)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(peer_a)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(peer_b)) ||
        !write_word(kCommandBase, 38)) return fail("cannot write TCA command");
    if (!run_command()) return false;
    advantage = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}
bool RawFieldVM::flux(std::int32_t phase_u, std::int32_t phase_v,
                      std::int32_t weight, std::int32_t source,
                      std::array<std::int32_t, 3>& out) {
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(phase_u)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(phase_v)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(weight)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(source)) ||
        !write_word(kCommandBase, 39)) return fail("cannot write FLUX command");
    if (!run_command()) return false;
    for (std::size_t i = 0; i < out.size(); ++i)
        out[i] = static_cast<std::int32_t>(read_word(kResultBase + i));
    return true;
}

bool RawFieldVM::cft(std::int32_t e_ab, std::int32_t e_bc,
                     std::int32_t e_ca, std::int32_t error,
                     std::int32_t rate, std::array<std::int32_t, 4>& out) {
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(e_ab)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(e_bc)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(e_ca)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(error)) ||
        !write_word(kProposalBase + 4, static_cast<std::uint32_t>(rate)) ||
        !write_word(kCommandBase, 6)) {
        return fail("cannot write CFT command");
    }
    if (!run_command()) return false;
    for (std::size_t i = 0; i < out.size(); ++i) {
        out[i] = static_cast<std::int32_t>(read_word(kResultBase + i));
    }
    return true;
}

bool RawFieldVM::trail(std::int32_t reward, std::int32_t v_minus_next,
                       std::int32_t v_plus, std::int32_t v_plus_prev,
                       std::int32_t v_minus, std::int32_t e_plus,
                       std::int32_t e_minus, std::int32_t grad_plus,
                       std::int32_t grad_minus, std::int32_t gamma,
                       std::int32_t lambda, std::array<std::int32_t, 3>& out) {
    const std::array<std::int32_t, 11> args = {
        reward, v_minus_next, v_plus, v_plus_prev, v_minus, e_plus,
        e_minus, grad_plus, grad_minus, gamma, lambda};
    for (std::size_t i = 0; i < args.size(); ++i) {
        if (!write_word(kProposalBase + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(args[i]))) {
            return fail("cannot write TRAIL command");
        }
    }
    if (!write_word(kCommandBase, 7)) return fail("cannot write TRAIL command");
    if (!run_command()) return false;
    for (std::size_t i = 0; i < out.size(); ++i) {
        out[i] = static_cast<std::int32_t>(read_word(kResultBase + i));
    }
    return true;
}


bool RawFieldVM::hot_triheads(
    const std::array<std::int32_t, kTriadMemberCount>& credits,
    std::int32_t threshold, HotTriheadResult& out) {
    for (std::size_t i = 0; i < credits.size(); ++i) {
        if (!write_word(kHotCredits + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i]))) {
            return fail("cannot write hot-head credits");
        }
    }
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(threshold)) ||
        !write_word(kCommandBase, 8)) {
        return fail("cannot write hot-trihead command");
    }
    if (!run_command()) return false;

    out.hot_heads = static_cast<std::uint16_t>(read_word(kResultBase + 0));
    out.hot_triads = static_cast<std::uint16_t>(read_word(kResultBase + 1));
    out.field_hot = (read_word(kResultBase + 2) & 1u) != 0;
    const std::uint32_t mapped = read_word(kResultBase + 3);
    if (out.hot_heads > kTriadMemberCount || mapped != kTriadMemberCount) {
        return fail("raw hot-trihead result has an invalid count");
    }

    std::array<bool, kTriadMemberCount> seen{};
    for (std::size_t i = 0; i < out.members.size(); ++i) {
        const std::uint32_t value = read_word(
            kHotMapping + static_cast<std::uint32_t>(i));
        if (value >= kTriadMemberCount) {
            return fail("raw hot-trihead mapping contains an invalid head");
        }
        if (seen[value]) return fail("raw hot-trihead mapping repeats a head");
        seen[value] = true;
        out.members[i] = static_cast<std::uint8_t>(value);
    }
    out.mapped = false;
    return true;
}

bool RawFieldVM::hot_triheads(
    Universe& universe,
    const std::array<std::int32_t, kTriadMemberCount>& credits,
    std::int32_t threshold, HotTriheadResult& out) {
    if (!hot_triheads(credits, threshold, out)) return false;

    for (std::size_t i = 0; i < out.members.size(); ++i) {
        universe.triad_members()[i] = out.members[i];
        const std::size_t t = i / kTriadSize;
        const std::size_t slot = i % kTriadSize;
        universe.triad_of()[out.members[i]] = static_cast<std::uint8_t>(t);
        universe.triad_slot()[out.members[i]] = static_cast<std::uint8_t>(slot);
    }
    universe.triad_votes().fill(0);
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        bump_triad_credit(universe.triad_credit()[t],
                          t < out.hot_triads ? 1 : -1);
    }
    out.mapped = true;
    return true;
}

bool RawFieldVM::context_class_map(
    const ContextClassInput& input,
    const std::array<std::int32_t, kTriadMemberCount>& credits,
    ContextClassResult& out) {
    return context_class_credit(input, ContextCreditInput{}, credits, out);
}

bool RawFieldVM::context_class_credit(
    const ContextClassInput& input,
    const ContextCreditInput& credit,
    const std::array<std::int32_t, kTriadMemberCount>& credits,
    ContextClassResult& out) {
    if (input.buckets == 0 || input.buckets > 16384) {
        return fail("context class bucket count outside 1..16384");
    }
    if (!input.direct && input.bucket >= input.buckets) {
        return fail("context class bucket is outside the table");
    }
    if (input.direct &&
        (input.direct_high > 15 || input.direct_low > 15)) {
        return fail("context class direct nibble outside 0..15");
    }
    if (credit.kind != ContextCreditKind::None &&
        credit.kind != ContextCreditKind::Cft &&
        credit.kind != ContextCreditKind::Trail) {
        return fail("unknown context credit kind");
    }
    for (std::size_t i = 0; i < credits.size(); ++i) {
        if (!write_word(kHotCredits + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i]))) {
            return fail("cannot write context class head credits");
        }
    }
    if (!write_word(kProposalBase + 0, input.high_table) ||
        !write_word(kProposalBase + 1,
                    static_cast<std::uint32_t>(input.buckets)) ||
        !write_word(kProposalBase + 2, input.bucket) ||
        !write_word(kProposalBase + 3, input.low_table) ||
        !write_word(kProposalBase + 4, input.direct ? 1u : 0u) ||
        !write_word(kProposalBase + 5, input.direct_high) ||
        !write_word(kProposalBase + 6, input.direct_low) ||
        !write_word(kProposalBase + 7,
                    static_cast<std::uint32_t>(credit.kind)) ||
        !write_word(kProposalBase + 8,
                    static_cast<std::uint32_t>(input.head_threshold))) {
        return fail("cannot write context class mapping command");
    }
    for (std::size_t i = 0; i < credit.cft.size(); ++i) {
        if (!write_word(kProposalBase + 9 + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credit.cft[i]))) {
            return fail("cannot write context CFT arguments");
        }
    }
    if (credit.kind == ContextCreditKind::Trail) {
        for (std::size_t i = 0; i < credit.trail.size(); ++i) {
            if (!write_word(kContextCreditArgs + static_cast<std::uint32_t>(i),
                            static_cast<std::uint32_t>(credit.trail[i]))) {
                return fail("cannot write context TRAIL arguments");
            }
        }
    }
    if (!write_word(kCommandBase, 30)) {
        return fail("cannot write context class command");
    }
    if (!run_command()) return false;

    out.high = static_cast<std::uint8_t>(read_word(kResultBase + 0) & 15u);
    out.low = static_cast<std::uint8_t>(read_word(kResultBase + 1) & 15u);
    out.head = static_cast<std::uint8_t>(read_word(kResultBase + 2) & 255u);
    const std::uint32_t triad = read_word(kResultBase + 3);
    const std::uint32_t member = read_word(kResultBase + 4);
    out.field_head = (read_word(kResultBase + 12) & 1u) != 0;
    if (out.field_head) {
        if (out.head != kFieldHead || triad != 0xFFFFu || member != 0xFFFFu) {
            return fail("context class field head result is inconsistent");
        }
        out.triad = 0xFFFFu;
        out.member = 0xFFFFu;
    } else {
        if (out.head >= kFieldHead || triad >= kTriadCount ||
            member >= kTriadSize) {
            return fail("context class result is outside the triad topology");
        }
        out.triad = static_cast<std::uint16_t>(triad);
        out.member = static_cast<std::uint16_t>(member);
    }
    const std::uint32_t accepted = read_word(kResultBase + 5);
    if (accepted > kTriadCount) {
        return fail("context class accepted-triad count exceeds 85");
    }
    out.accepted_triads = static_cast<std::uint16_t>(accepted);
    out.field_accepted = (read_word(kResultBase + 6) & 1u) != 0;
    out.triad_accepted = (read_word(kResultBase + 7) & 1u) != 0;
    out.head_credit_before =
        static_cast<std::int32_t>(read_word(kResultBase + 8));
    out.head_credit_after =
        static_cast<std::int32_t>(read_word(kResultBase + 9));
    out.credit_applied = (read_word(kResultBase + 10) & 1u) != 0;
    out.credit_delta = static_cast<std::int32_t>(read_word(kResultBase + 11));
    for (std::size_t i = 0; i < out.votes.size(); ++i) {
        out.votes[i] = static_cast<std::uint8_t>(
            read_word(kContextVotes + static_cast<std::uint32_t>(i)) & 1u);
    }
    return true;
}

bool RawFieldVM::context_class_apply(
    Universe& universe,
    const ContextClassInput& input,
    const ContextCreditInput& credit,
    ContextClassResult& out) {
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        for (std::size_t s = 0; s < kTriadSize; ++s) {
            if (universe.triad_members()[t * kTriadSize + s] !=
                static_cast<std::uint8_t>(t * kTriadSize + s)) {
                return fail("context class field link requires the canonical triad mapping");
            }
        }
    }
    std::array<std::int32_t, kTriadMemberCount> credits{};
    for (std::size_t i = 0; i < credits.size(); ++i) {
        credits[i] = universe.head_credit()[i];
    }
    if (!context_class_credit(input, credit, credits, out)) return false;
    if (out.head < kTriadMemberCount) {
        const int next = std::max<int>(
            -32768, std::min<int>(32767, out.head_credit_after));
        universe.head_credit()[out.head] = static_cast<std::int16_t>(next);
    }
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        universe.triad_votes()[t] = out.votes[t];
    }
    universe.triad_field_count() = out.accepted_triads;
    return true;
}


bool RawFieldVM::micro_feature(
    const std::array<float, kRawFeatureDim>& x0,
    const std::array<float, kRawFeatureDim>& x1,
    std::array<float, kRawFeatureDim>& out) {
    for (std::size_t i = 0; i < kRawFeatureDim; ++i) {
        std::uint32_t a = 0, b = 0;
        std::memcpy(&a, &x0[i], sizeof(a));
        std::memcpy(&b, &x1[i], sizeof(b));
        if (!write_word(kMicroX0 + static_cast<std::uint32_t>(i), a) ||
            !write_word(kMicroX1 + static_cast<std::uint32_t>(i), b)) {
            return fail("cannot write raw micro-feature input");
        }
    }
    if (!write_word(kCommandBase, 9)) return fail("cannot write micro-feature command");
    if (!run_command()) return false;
    if (read_word(kResultBase) != kRawFeatureDim) {
        return fail("raw micro-feature returned the wrong count");
    }
    for (std::size_t i = 0; i < kRawFeatureDim; ++i) {
        const std::uint32_t bits = read_word(kMicroOut + static_cast<std::uint32_t>(i));
        std::memcpy(&out[i], &bits, sizeof(bits));
    }
    return true;
}



bool RawFieldVM::write_trunk_inputs(
    const std::vector<std::array<float, kRawFeatureDim>>& tokens,
    const TrunkWeights& weights) {
    if (tokens.empty() || tokens.size() > kRawTrunkContext) {
        return fail("causal trunk token count outside 1..256");
    }
    auto write_float = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t tkn = 0; tkn < tokens.size(); ++tkn) {
        for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
            if (!write_float(kMicroX0 + static_cast<std::uint32_t>(tkn * 8 + d),
                             tokens[tkn][d])) {
                return fail("cannot write causal-trunk token");
            }
        }
    }
    return write_trunk_weights(weights);
}

bool RawFieldVM::trunk_feature(
    const std::vector<std::array<float, kRawFeatureDim>>& tokens,
    std::array<float, kRawFeatureDim>& out) {
    if (tokens.empty() || tokens.size() > kRawTrunkContext) {
        return fail("causal trunk token count outside 1..256");
    }
    auto write_float = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t tkn = 0; tkn < tokens.size(); ++tkn) {
        for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
            if (!write_float(kMicroX0 + static_cast<std::uint32_t>(tkn * 8 + d),
                             tokens[tkn][d])) {
                return fail("cannot write causal-trunk token");
            }
        }
    }
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(tokens.size())) ||
        !write_word(kCommandBase, 10)) {
        return fail("cannot write causal-trunk command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != kRawFeatureDim) {
        return fail("raw causal trunk returned the wrong feature count");
    }
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        const std::uint32_t bits = read_word(0xA000u + static_cast<std::uint32_t>(d));
        std::memcpy(&out[d], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::causal_trunk(
    const std::vector<std::array<float, kRawFeatureDim>>& tokens,
    const TrunkWeights& weights,
    std::array<float, kRawFeatureDim>& out) {
    if (!write_trunk_inputs(tokens, weights)) return false;
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(tokens.size())) ||
        !write_word(kCommandBase, 10)) {
        return fail("cannot write causal-trunk command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != kRawFeatureDim) {
        return fail("raw causal trunk returned the wrong feature count");
    }
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        const std::uint32_t bits = read_word(0xA000u + static_cast<std::uint32_t>(d));
        std::memcpy(&out[d], &bits, sizeof(bits));
    }
    return true;
}



bool RawFieldVM::causal_trunk_cached(
    const std::vector<std::array<float, kRawFeatureDim>>& tokens,
    std::array<float, kRawFeatureDim>& out) {
    if (tokens.empty() || tokens.size() > kRawTrunkContext) {
        return fail("cached causal trunk token count outside 1..256");
    }
    for (std::size_t tkn = 0; tkn < tokens.size(); ++tkn) {
        for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
            std::uint32_t bits = 0;
            std::memcpy(&bits, &tokens[tkn][d], sizeof(bits));
            if (!write_word(kMicroX0 + static_cast<std::uint32_t>(tkn * 8 + d),
                            bits)) {
                return fail("cannot write cached trunk token");
            }
        }
    }
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(tokens.size())) ||
        !write_word(kCommandBase, 10)) {
        return fail("cannot write cached causal-trunk command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != kRawFeatureDim) {
        return fail("cached causal trunk returned the wrong feature count");
    }
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        const std::uint32_t bits = read_word(0xA000u + static_cast<std::uint32_t>(d));
        std::memcpy(&out[d], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::readout_train(
    const std::vector<std::array<float, kRawFeatureDim>>& tokens,
    const TrunkWeights& weights, std::uint8_t target, float learning_rate,
    bool& correct, float& target_score, float& best_wrong_score,
    float& loss) {
    // Load tokens/weights once; the readout weights at 0xB000 persist.
    if (!write_trunk_inputs(tokens, weights)) return false;
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(tokens.size())) ||
        !write_word(kProposalBase + 1, target) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kCommandBase, 12)) {
        return fail("cannot write readout-train command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ts = read_word(kResultBase + 1);
    const std::uint32_t bs = read_word(kResultBase + 2);
    const std::uint32_t ls = read_word(kResultBase + 3);
    std::memcpy(&target_score, &ts, sizeof(ts));
    std::memcpy(&best_wrong_score, &bs, sizeof(bs));
    std::memcpy(&loss, &ls, sizeof(ls));
    return true;
}

bool RawFieldVM::readout_only(
    const std::array<float, kRawFeatureDim>& feature, std::uint8_t target,
    float learning_rate, bool& correct, float& target_score,
    float& best_wrong_score, float& loss) {
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &feature[d], sizeof(bits));
        if (!write_word(0xA000u + static_cast<std::uint32_t>(d), bits)) {
            return fail("cannot write readout feature");
        }
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kCommandBase, 16)) {
        return fail("cannot write readout-only command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ts = read_word(kResultBase + 1);
    const std::uint32_t bs = read_word(kResultBase + 2);
    const std::uint32_t ls = read_word(kResultBase + 3);
    std::memcpy(&target_score, &ts, sizeof(ts));
    std::memcpy(&best_wrong_score, &bs, sizeof(bs));
    std::memcpy(&loss, &ls, sizeof(ls));
    return true;
}



bool RawFieldVM::read_trunk_weights(TrunkWeights& out) const {
    auto read_float = [&](std::uint32_t base, float* values, std::size_t count) {
        for (std::size_t i = 0; i < count; ++i) {
            const std::uint32_t bits = read_word(base + static_cast<std::uint32_t>(i));
            std::memcpy(&values[i], &bits, sizeof(bits));
        }
    };
    read_float(0x9000, out.wq.data(), out.wq.size());
    read_float(0x9040, out.wk.data(), out.wk.size());
    read_float(0x9080, out.wv.data(), out.wv.size());
    read_float(0x90C0, out.wout.data(), out.wout.size());
    read_float(0x9100, out.w1.data(), out.w1.size());
    read_float(0x9180, out.w2.data(), out.w2.size());
    return true;
}


bool RawFieldVM::read_wide_weights(std::size_t dim, std::size_t hidden,
                                   WideTrunkWeights& out) const {
    if (dim == 0 || dim > 128 || hidden == 0 || hidden > 512) return false;
    out.dim = dim;
    out.hidden = hidden;
    out.wq.resize(dim * dim);
    out.wk.resize(dim * dim);
    out.wv.resize(dim * dim);
    out.wout.resize(dim * dim);
    out.w1.resize(hidden * dim);
    out.w2.resize(dim * hidden);
    auto read_block = [&](std::uint32_t base, std::vector<float>& values) {
        for (std::size_t i = 0; i < values.size(); ++i) {
            const std::uint32_t bits = read_word(base + static_cast<std::uint32_t>(i));
            std::memcpy(&values[i], &bits, sizeof(bits));
        }
    };
    read_block(0x60000u, out.wq);
    read_block(0x60000u + static_cast<std::uint32_t>(dim * dim), out.wk);
    read_block(0x60000u + static_cast<std::uint32_t>(2 * dim * dim), out.wv);
    read_block(0x60000u + static_cast<std::uint32_t>(3 * dim * dim), out.wout);
    read_block(0x60000u + static_cast<std::uint32_t>(4 * dim * dim), out.w1);
    read_block(0x60000u + static_cast<std::uint32_t>(4 * dim * dim + hidden * dim),
               out.w2);
    return true;
}

bool RawFieldVM::set_readout_row(
    std::uint8_t row, const std::array<float, kRawFeatureDim>& values) {
    if (row >= 255) return fail("readout row outside 0..254");
    for (std::size_t i = 0; i < values.size(); ++i) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &values[i], sizeof(bits));
        if (!write_word(0xB000u + static_cast<std::uint32_t>(row * 8 + i),
                        bits)) {
            return fail("cannot write readout row");
        }
    }
    return true;
}

bool RawFieldVM::readout_sample(
    const std::array<float, kRawFeatureDim>& feature, std::uint8_t target,
    float learning_rate, std::uint32_t salt, bool& correct,
    float& target_score, float& best_wrong_score, float& loss) {
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &feature[d], sizeof(bits));
        if (!write_word(0xA000u + static_cast<std::uint32_t>(d), bits)) {
            return fail("cannot write sampled readout feature");
        }
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kProposalBase + 2, salt) ||
        !write_word(kCommandBase, 17)) {
        return fail("cannot write sampled readout command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ts = read_word(kResultBase + 1);
    const std::uint32_t bs = read_word(kResultBase + 2);
    const std::uint32_t ls = read_word(kResultBase + 3);
    std::memcpy(&target_score, &ts, sizeof(ts));
    std::memcpy(&best_wrong_score, &bs, sizeof(bs));
    std::memcpy(&loss, &ls, sizeof(ls));
    return true;
}

bool RawFieldVM::readout_softmax(
    const std::array<float, kRawFeatureDim>& feature, std::uint8_t target,
    float learning_rate, bool& correct, float& loss,
    float& target_probability) {
    for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &feature[d], sizeof(bits));
        if (!write_word(0xA000u + static_cast<std::uint32_t>(d), bits)) {
            return fail("cannot write softmax readout feature");
        }
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kCommandBase, 19)) {
        return fail("cannot write softmax readout command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ls = read_word(kResultBase + 1);
    const std::uint32_t ps = read_word(kResultBase + 2);
    std::memcpy(&loss, &ls, sizeof(ls));
    std::memcpy(&target_probability, &ps, sizeof(ps));
    return true;
}

bool RawFieldVM::reset_hier_readout(std::size_t dim) {
    if (dim == 0 || dim > 256) return fail("hier readout dim outside 1..256");
    const std::size_t words = 16 * dim + 16 * 16 * dim;
    for (std::size_t i = 0; i < words; ++i) {
        if (!write_word(0xB000u + static_cast<std::uint32_t>(i), 0)) {
            return fail("cannot reset hierarchical readout");
        }
    }
    return true;
}

bool RawFieldVM::readout_hier(const float* feature, std::uint8_t target,
                              float learning_rate, std::size_t dim,
                              bool& correct, float& loss,
                              std::uint8_t& predicted_high,
                              std::uint8_t& predicted_low) {
    if (feature == nullptr || dim == 0 || dim > 256) {
        return fail("invalid hierarchical readout input");
    }
    for (std::size_t d = 0; d < dim; ++d) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &feature[d], sizeof(bits));
        if (!write_word(0xA000u + static_cast<std::uint32_t>(d), bits)) {
            return fail("cannot write hierarchical feature");
        }
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 21)) {
        return fail("cannot write hierarchical readout command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ls = read_word(kResultBase + 1);
    std::memcpy(&loss, &ls, sizeof(ls));
    predicted_high = static_cast<std::uint8_t>(read_word(kResultBase + 2) & 15u);
    predicted_low = static_cast<std::uint8_t>(read_word(kResultBase + 3) & 15u);
    return true;
}

bool RawFieldVM::phase_encode_wide(const std::uint8_t* bytes,
                                   std::size_t count, std::size_t dim,
                                   std::vector<std::int32_t>& out,
                                   std::uint32_t& shard) {
    if (!bytes || count == 0 || count > 64 || dim == 0 || dim > 128) {
        return fail("phase encode requires bytes 1..64 and dim 1..128");
    }
    for (std::size_t i = 0; i < count; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i), bytes[i])) {
            return fail("cannot write phase input byte");
        }
    }
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 60)) {
        return fail("cannot write phase encode command");
    }
    if (!run_command()) return false;
    shard = read_word(kResultBase + 0) & 15u;
    out.resize(dim * 2);
    for (std::size_t i = 0; i < out.size(); ++i) {
        out[i] = static_cast<std::int32_t>(
            read_word(0x5200u + static_cast<std::uint32_t>(i)));
    }
    return true;
}


bool RawFieldVM::phase_rotate(const std::vector<std::int32_t>& in,
                              std::uint32_t turn,
                              std::vector<std::int32_t>& out) {
    if (in.size() < 2 || in.size() % 2 != 0 || in.size() / 2 > 128)
        return fail("phase rotate lanes must be 1..128");
    for (std::size_t i = 0; i < in.size(); ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(in[i])))
            return fail("cannot write phase rotate input");
    if (!write_word(kProposalBase + 0, turn) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(in.size() / 2)) ||
        !write_word(kCommandBase, 58)) return fail("cannot write phase rotate command");
    if (!run_command()) return false;
    out.resize(in.size());
    for (std::size_t i = 0; i < out.size(); ++i)
        out[i] = static_cast<std::int32_t>(read_word(0x7200u + static_cast<std::uint32_t>(i)));
    return true;
}

bool RawFieldVM::pq_encode(const std::vector<std::int32_t>& query,
                           const std::vector<std::int32_t>& codebook,
                           std::size_t codewords, std::size_t dim,
                           std::uint32_t& code, std::int32_t& distance) {
    if (codewords == 0 || codewords > 256 || dim == 0 || dim > 256 ||
        query.size() < dim || codebook.size() < codewords * dim)
        return fail("pq encode bounds invalid");
    for (std::size_t i = 0; i < dim; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(query[i])))
            return fail("cannot write pq query");
    for (std::size_t i = 0; i < codewords * dim; ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(codebook[i])))
            return fail("cannot write pq codebook");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(codewords)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 59)) return fail("cannot write pq command");
    if (!run_command()) return false;
    code = read_word(kResultBase + 0);
    distance = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}

bool RawFieldVM::spectral_iter(
    const std::array<std::int32_t, 64>& adjacency,
    const std::array<std::int32_t, 8>& in,
    std::array<std::int32_t, 8>& out) {
    for (std::size_t i = 0; i < adjacency.size(); ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(adjacency[i])))
            return fail("cannot write spectral adjacency");
    for (std::size_t i = 0; i < in.size(); ++i)
        if (!write_word(0x7040u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(in[i])))
            return fail("cannot write spectral input");
    if (!write_word(kCommandBase, 61)) return fail("cannot write spectral command");
    if (!run_command()) return false;
    for (std::size_t i = 0; i < out.size(); ++i)
        out[i] = static_cast<std::int32_t>(read_word(0x7080u + static_cast<std::uint32_t>(i)));
    return true;
}

bool RawFieldVM::sparse_knn(const std::vector<std::int32_t>& query,
                            const std::vector<std::int32_t>& bank,
                            std::size_t count, std::size_t dim, std::size_t k,
                            std::vector<std::uint32_t>& indices,
                            std::vector<std::int32_t>& scores) {
    if (count == 0 || count > 4096 || dim == 0 || dim > 256 || k == 0 || k > 4 ||
        query.size() < dim || bank.size() < count * dim)
        return fail("sparse kNN bounds invalid");
    for (std::size_t i = 0; i < dim; ++i)
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(query[i])))
            return fail("cannot write kNN query");
    for (std::size_t i = 0; i < count * dim; ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(bank[i])))
            return fail("cannot write kNN bank");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(k)) ||
        !write_word(kCommandBase, 62)) return fail("cannot write kNN command");
    if (!run_command()) return false;
    indices.resize(k);
    scores.resize(k);
    for (std::size_t i = 0; i < k; ++i) {
        indices[i] = read_word(0x7200u + static_cast<std::uint32_t>(i));
        scores[i] = static_cast<std::int32_t>(read_word(0x7240u + static_cast<std::uint32_t>(i)));
    }
    return true;
}

bool RawFieldVM::pq_train(const std::vector<std::int32_t>& samples,
                          std::size_t count, std::size_t dim,
                          std::size_t codewords, std::size_t iterations,
                          std::vector<std::int32_t>& codebook) {
    if (count == 0 || count > 1024 || dim == 0 || dim > 256 ||
        codewords == 0 || codewords > 256 || iterations > 8 ||
        samples.size() < count * dim) {
        return fail("pq train bounds invalid");
    }
    for (std::size_t i = 0; i < count * dim; ++i) {
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(samples[i]))) {
            return fail("cannot write pq training samples");
        }
    }
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(codewords)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(iterations)) ||
        !write_word(kCommandBase, 69)) {
        return fail("cannot write pq training command");
    }
    if (!run_command()) return false;
    codebook.resize(codewords * dim);
    for (std::size_t i = 0; i < codebook.size(); ++i) {
        codebook[i] = static_cast<std::int32_t>(
            read_word(0x50000u + static_cast<std::uint32_t>(i)));
    }
    return true;
}


bool RawFieldVM::pq_update(const std::vector<std::int32_t>& samples,
                           std::size_t count, std::size_t dim,
                           std::size_t codewords, std::size_t iterations,
                           std::vector<std::int32_t>& codebook,
                           std::size_t prior_count) {
    if (count == 0 || count > 1024 || dim == 0 || dim > 256 ||
        codewords == 0 || codewords > 256 || iterations > 8 ||
        samples.size() < count * dim || codebook.size() < codewords * dim)
        return fail("pq update bounds invalid");
    for (std::size_t i = 0; i < count * dim; ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(samples[i])))
            return fail("cannot write pq update samples");
    for (std::size_t i = 0; i < codewords * dim; ++i)
        if (!write_word(0x50000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(codebook[i])))
            return fail("cannot write pq update codebook");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(codewords)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(iterations)) ||
        !write_word(kProposalBase + 4, static_cast<std::uint32_t>(prior_count)) ||
        !write_word(kCommandBase, 71)) return fail("cannot write pq update command");
    if (!run_command()) return false;
    codebook.resize(codewords * dim);
    for (std::size_t i = 0; i < codebook.size(); ++i)
        codebook[i] = static_cast<std::int32_t>(
            read_word(0x50000u + static_cast<std::uint32_t>(i)));
    return true;
}

bool RawFieldVM::pq_residuals(const std::vector<std::int32_t>& samples,
                              const std::vector<std::uint32_t>& codes,
                              std::size_t count, std::size_t dim,
                              const std::vector<std::int32_t>& codebook,
                              std::vector<std::int32_t>& residuals) {
    if (count == 0 || count > 1024 || dim == 0 || dim > 256 ||
        samples.size() < count * dim || codes.size() < count ||
        codebook.empty()) {
        return fail("pq residual bounds invalid");
    }
    for (std::size_t i = 0; i < count * dim; ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(samples[i])))
            return fail("cannot write pq residual samples");
    for (std::size_t i = 0; i < codebook.size(); ++i)
        if (!write_word(0x50000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(codebook[i])))
            return fail("cannot write pq residual codebook");
    for (std::size_t i = 0; i < count; ++i)
        if (!write_word(0x80000u + static_cast<std::uint32_t>(i), codes[i]))
            return fail("cannot write pq residual codes");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 70))
        return fail("cannot write pq residual command");
    if (!run_command()) return false;
    residuals.resize(count * dim);
    for (std::size_t i = 0; i < residuals.size(); ++i)
        residuals[i] = static_cast<std::int32_t>(
            read_word(0x90000u + static_cast<std::uint32_t>(i)));
    return true;
}


bool RawFieldVM::leaf_verify(const std::vector<std::int32_t>& expected,
                              const std::vector<std::int32_t>& codebook,
                              const std::vector<std::int32_t>& residual,
                              std::uint32_t code, std::size_t dim,
                              std::uint32_t tolerance, bool& accepted,
                              std::int32_t& error) {
    if (dim == 0 || dim > 256 || expected.size() < dim ||
        residual.size() < dim || codebook.size() < (code + 1) * dim)
        return fail("leaf verify bounds invalid");
    for (std::size_t i = 0; i < dim; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(expected[i])) ||
            !write_word(0x30000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(residual[i])))
            return fail("cannot write leaf verify vectors");
    }
    for (std::size_t i = 0; i < codebook.size(); ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(codebook[i])))
            return fail("cannot write leaf verify codebook");
    if (!write_word(kProposalBase + 0, code) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kProposalBase + 2, tolerance) ||
        !write_word(kCommandBase, 72)) return fail("cannot write leaf verify command");
    if (!run_command()) return false;
    accepted = (read_word(kResultBase + 0) & 1u) != 0;
    error = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}


bool RawFieldVM::raw_hash(const std::vector<std::int32_t>& payload,
                          std::uint32_t& digest) {
    if (payload.empty() || payload.size() > 65535)
        return fail("checkpoint hash payload outside 1..65535 words");
    for (std::size_t i = 0; i < payload.size(); ++i)
        if (!write_word(0x350000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(payload[i])))
            return fail("cannot write checkpoint hash payload");
    if (!write_word(kProposalBase + 0, 0x350000u) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(payload.size())) ||
        !write_word(kCommandBase, 73))
        return fail("cannot write checkpoint hash command");
    if (!run_command()) return false;
    digest = read_word(kResultBase);
    return true;
}

bool RawFieldVM::tokenize(const std::string& text, std::size_t max_words,
                          std::vector<std::uint32_t>& words,
                          std::vector<std::uint32_t>& subwords,
                          std::vector<std::uint32_t>& meta,
                          std::size_t& word_count, std::size_t& subword_count) {
    constexpr std::uint32_t kTextBase = 0x00400000u;
    constexpr std::uint32_t kWordsBase = 0x00500000u;
    constexpr std::uint32_t kSubwordsBase = 0x00600000u;
    constexpr std::uint32_t kMetaBase = 0x00700000u;
    if (text.empty() || text.size() > 0x00100000u || max_words == 0 ||
        max_words > 131072) return fail("tokenizer bounds invalid");
    for (std::size_t i = 0; i < text.size(); ++i)
        if (!write_word(kTextBase + static_cast<std::uint32_t>(i),
                        static_cast<std::uint8_t>(text[i])))
            return fail("cannot write tokenizer text");
    if (!write_word(kProposalBase + 0, kTextBase) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(text.size())) ||
        !write_word(kProposalBase + 2, kWordsBase) ||
        !write_word(kProposalBase + 3, kSubwordsBase) ||
        !write_word(kProposalBase + 4, kMetaBase) ||
        !write_word(kProposalBase + 5, static_cast<std::uint32_t>(max_words)) ||
        !write_word(kCommandBase, 74))
        return fail("cannot write tokenizer command");
    if (!run_command()) return false;
    word_count = read_word(kResultBase + 0);
    subword_count = read_word(kResultBase + 1);
    if (word_count > max_words || subword_count > max_words * 16u + 64u)
        return fail("tokenizer returned invalid counts");
    words.resize(word_count);
    for (std::size_t i = 0; i < words.size(); ++i)
        words[i] = read_word(kWordsBase + static_cast<std::uint32_t>(i));
    subwords.resize(subword_count);
    for (std::size_t i = 0; i < subwords.size(); ++i)
        subwords[i] = read_word(kSubwordsBase + static_cast<std::uint32_t>(i));
    meta.resize(word_count * 6);
    for (std::size_t i = 0; i < meta.size(); ++i)
        meta[i] = read_word(kMetaBase + static_cast<std::uint32_t>(i));
    return true;
}

bool RawFieldVM::meta_trihead_reset() {
    if (!write_word(kCommandBase, 75)) return fail("cannot write meta reset");
    return run_command();
}

bool RawFieldVM::meta_trihead_observe_batch(
    const std::vector<std::uint32_t>& words, std::size_t& contexts) {
    if (words.empty() || words.size() > 4096)
        return fail("meta observe bounds invalid");
    for (std::size_t i = 0; i < words.size(); ++i)
        if (!write_word(0x20000u + static_cast<std::uint32_t>(i), words[i]))
            return fail("cannot write meta words");
    if (!write_word(kProposalBase + 0,
                    static_cast<std::uint32_t>(words.size())) ||
        !write_word(kCommandBase, 76))
        return fail("cannot write meta observe command");
    if (!run_command()) return false;
    contexts = read_word(kResultBase + 0);
    return contexts == words.size();
}

bool RawFieldVM::read_meta_trihead(std::vector<std::int32_t>& votes,
                                   std::vector<std::int32_t>& credits) {
    votes.resize(85);
    credits.resize(255);
    for (std::size_t i = 0; i < votes.size(); ++i)
        votes[i] = static_cast<std::int32_t>(
            read_word(0x220000u + static_cast<std::uint32_t>(i)));
    for (std::size_t i = 0; i < credits.size(); ++i)
        credits[i] = static_cast<std::int32_t>(
            read_word(0x220100u + static_cast<std::uint32_t>(i)));
    return true;
}

bool RawFieldVM::temporal_slots_reset() {
    if (!write_word(kCommandBase, 77)) return fail("cannot write temporal reset");
    return run_command();
}

bool RawFieldVM::temporal_slots_observe_batch(
    const std::vector<std::uint32_t>& words, std::size_t& contexts) {
    if (words.empty() || words.size() > 4096)
        return fail("temporal observe bounds invalid");
    for (std::size_t i = 0; i < words.size(); ++i)
        if (!write_word(0x20000u + static_cast<std::uint32_t>(i), words[i]))
            return fail("cannot write temporal words");
    if (!write_word(kProposalBase + 0,
                    static_cast<std::uint32_t>(words.size())) ||
        !write_word(kCommandBase, 78))
        return fail("cannot write temporal observe");
    if (!run_command()) return false;
    contexts = read_word(kResultBase + 0);
    return contexts == words.size();
}

bool RawFieldVM::temporal_slots_project() {
    if (!write_word(kCommandBase, 79)) return fail("cannot write temporal project");
    return run_command();
}

bool RawFieldVM::read_temporal_slots(
    std::size_t count, std::vector<std::int32_t>& past_votes,
    std::vector<std::int32_t>& past_credits,
    std::vector<std::int32_t>& future_votes,
    std::vector<std::int32_t>& future_credits,
    std::vector<std::uint32_t>& current_words,
    std::array<std::int32_t, 4>& head255,
    std::vector<std::int32_t>& slots) {
    if (count == 0 || count > 4096) return fail("temporal read bounds");
    past_votes.resize(85); past_credits.resize(255);
    future_votes.resize(85); future_credits.resize(255);
    current_words.resize(count); slots.resize(count * 3);
    for (std::size_t i = 0; i < 85; ++i) {
        past_votes[i] = static_cast<std::int32_t>(read_word(0x230000u + i));
        future_votes[i] = static_cast<std::int32_t>(read_word(0x231000u + i));
    }
    for (std::size_t i = 0; i < 255; ++i) {
        past_credits[i] = static_cast<std::int32_t>(read_word(0x230100u + i));
        future_credits[i] = static_cast<std::int32_t>(read_word(0x231100u + i));
    }
    for (std::size_t i = 0; i < count; ++i) {
        current_words[i] = read_word(0x232000u + static_cast<std::uint32_t>(i));
        slots[i * 3 + 0] = static_cast<std::int32_t>(read_word(
            0x234000u + static_cast<std::uint32_t>(i * 3)));
        slots[i * 3 + 1] = static_cast<std::int32_t>(read_word(
            0x234001u + static_cast<std::uint32_t>(i * 3)));
        slots[i * 3 + 2] = static_cast<std::int32_t>(read_word(
            0x234002u + static_cast<std::uint32_t>(i * 3)));
    }
    for (std::size_t i = 0; i < 4; ++i)
        head255[i] = static_cast<std::int32_t>(read_word(0x233000u + i));
    return true;
}

bool RawFieldVM::ngram_reset() {
    if (!write_word(kCommandBase, 80)) return fail("cannot write ngram reset");
    return run_command();
}

bool RawFieldVM::ngram_train(const std::string& bytes, std::size_t& processed,
                              std::size_t skip) {
    if (bytes.empty() || bytes.size() > 0x10000 || skip > bytes.size())
        return fail("ngram train chunk 1..65536 bytes");
    for (std::size_t i = 0; i < bytes.size(); ++i)
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint8_t>(bytes[i])))
            return fail("cannot write ngram bytes");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(bytes.size())) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(skip)) ||
        !write_word(kCommandBase, 81))
        return fail("cannot write ngram train");
    if (!run_command()) return false;
    processed = read_word(kResultBase + 0);
    return processed == bytes.size();
}

bool RawFieldVM::ngram_topk(
    std::array<std::vector<std::uint32_t>, 4>& keys,
    std::array<std::vector<std::uint32_t>, 4>& counts) {
    if (!write_word(kCommandBase, 82)) return fail("cannot write ngram topk");
    if (!run_command()) return false;
    for (std::size_t order = 0; order < 4; ++order) {
        keys[order].resize(64);
        counts[order].resize(64);
        for (std::size_t i = 0; i < 64; ++i) {
            keys[order][i] = read_word(0x2D0000u +
                static_cast<std::uint32_t>(order * 0x100 + i));
            counts[order][i] = read_word(0x2D1000u +
                static_cast<std::uint32_t>(order * 0x100 + i));
        }
    }
    return true;
}

bool RawFieldVM::hyperbolic_measure(
    const std::vector<std::int32_t>& vector, std::size_t dim,
    std::int32_t& mean, std::int32_t& radial) {
    if (dim == 0 || dim > 256 || vector.size() < dim)
        return fail("hyperbolic bounds invalid");
    for (std::size_t i = 0; i < dim; ++i)
        if (!write_word(0x340000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(vector[i])))
            return fail("cannot write hyperbolic vector");
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 83)) return fail("cannot write hyperbolic cmd");
    if (!run_command()) return false;
    mean = static_cast<std::int32_t>(read_word(kResultBase));
    radial = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}

bool RawFieldVM::path_geometry(
    const std::vector<std::int32_t>& bank, std::size_t count, std::size_t dim,
    std::int32_t& length, std::int32_t& closure, std::int32_t& turn,
    std::int32_t& curvature) {
    if (count < 2 || count > 4096 || dim == 0 || dim > 256 ||
        bank.size() < count * dim) return fail("path bounds invalid");
    for (std::size_t i = 0; i < count * dim; ++i)
        if (!write_word(0x340000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(bank[i])))
            return fail("cannot write path bank");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 84)) return fail("cannot write path cmd");
    if (!run_command()) return false;
    length = static_cast<std::int32_t>(read_word(kResultBase));
    closure = static_cast<std::int32_t>(read_word(kResultBase + 1));
    turn = static_cast<std::int32_t>(read_word(kResultBase + 2));
    curvature = static_cast<std::int32_t>(read_word(kResultBase + 3));
    return true;
}

bool RawFieldVM::triangle_geometry(
    const std::vector<std::int32_t>& vectors, std::size_t dim,
    std::array<std::int32_t, 3>& sides, std::int32_t& area_proxy,
    std::int32_t& tightness, std::int32_t& orientation,
    std::int32_t* stretch) {
    if (dim == 0 || dim > 256 || vectors.size() < dim * 3)
        return fail("triangle bounds invalid");
    for (std::size_t i = 0; i < dim * 3; ++i)
        if (!write_word(0x340000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(vectors[i])))
            return fail("cannot write triangle vectors");
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 85)) return fail("cannot write triangle cmd");
    if (!run_command()) return false;
    for (std::size_t i = 0; i < 3; ++i)
        sides[i] = static_cast<std::int32_t>(read_word(kResultBase + i));
    area_proxy = static_cast<std::int32_t>(read_word(kResultBase + 3));
    tightness = static_cast<std::int32_t>(read_word(kResultBase + 4));
    orientation = static_cast<std::int32_t>(read_word(kResultBase + 5));
    if (stretch) {
        *stretch = static_cast<std::int32_t>(read_word(kResultBase + 6));
    }
    return true;
}

bool RawFieldVM::field_perturb(
    const std::vector<std::int32_t>& vector, std::size_t dim,
    std::vector<std::int32_t>& credits, std::vector<std::int32_t>& votes,
    std::int32_t& field_value) {
    if (dim == 0 || dim > 256 || vector.size() < dim)
        return fail("field perturb bounds invalid");
    for (std::size_t i = 0; i < dim; ++i)
        if (!write_word(0x340000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(vector[i])))
            return fail("cannot write field vector");
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 86)) return fail("cannot write field perturb cmd");
    if (!run_command()) return false;
    credits.resize(255);
    votes.resize(85);
    for (std::size_t i = 0; i < 255; ++i)
        credits[i] = static_cast<std::int32_t>(read_word(0x2E0000u + i));
    for (std::size_t i = 0; i < 85; ++i)
        votes[i] = static_cast<std::int32_t>(read_word(0x2E0100u + i));
    field_value = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}



bool RawFieldVM::global_hodge_q16(
    const std::vector<std::int32_t>& pair_flows_q16,
    const std::vector<std::array<std::uint32_t, 3>>& triangles,
    std::array<float, 256>& divergence, std::array<float, 16>& curl) {
    if (pair_flows_q16.size() != 32640 || triangles.size() > 16)
        return fail("global hodge q16 bounds invalid");
    for (std::size_t i = 0; i < pair_flows_q16.size(); ++i)
        if (!write_word(0x360000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(pair_flows_q16[i])))
            return fail("cannot write global hodge q16 flows");
    for (std::size_t t = 0; t < triangles.size(); ++t)
        for (std::size_t k = 0; k < 3; ++k)
            if (!write_word(0x368000u + static_cast<std::uint32_t>(t * 3 + k),
                            triangles[t][k]))
                return fail("cannot write global hodge q16 triangles");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(triangles.size())) ||
        !write_word(kCommandBase, 100))
        return fail("cannot write global hodge q16 command");
    if (!run_command()) return false;
    if ((read_word(kResultBase) & 1u) == 0)
        return fail("global hodge q16 rejected");
    for (std::size_t i = 0; i < divergence.size(); ++i) {
        const std::uint32_t bits = read_word(0x369000u + static_cast<std::uint32_t>(i));
        std::memcpy(&divergence[i], &bits, sizeof(bits));
    }
    for (std::size_t i = 0; i < curl.size(); ++i) {
        const std::uint32_t bits = read_word(0x369400u + static_cast<std::uint32_t>(i));
        std::memcpy(&curl[i], &bits, sizeof(bits));
    }
    return true;
}


bool RawFieldVM::tensor256_address(std::uint8_t h, std::uint8_t a,
                                   std::uint8_t b, Tensor256Address& out) {
    if (!write_word(kProposalBase + 0, h) ||
        !write_word(kProposalBase + 1, a) ||
        !write_word(kProposalBase + 2, b) ||
        !write_word(kCommandBase, 104))
        return fail("cannot write tensor256 address command");
    if (!run_command()) return false;
    out.valid = (read_word(kResultBase) & 1u) != 0;
    out.cell = read_word(kResultBase + 1);
    out.lane = static_cast<std::uint8_t>(read_word(kResultBase + 2) & 1u);
    out.byte_offset = read_word(kResultBase + 3);
    return true;
}

bool RawFieldVM::tensor256_dual_address(std::uint8_t h, std::uint8_t a,
                                        std::uint8_t b, std::uint8_t bank,
                                        Tensor256Address& out) {
    if (!write_word(kProposalBase + 0, h) ||
        !write_word(kProposalBase + 1, a) ||
        !write_word(kProposalBase + 2, b) ||
        !write_word(kProposalBase + 3, bank) ||
        !write_word(kCommandBase, 105))
        return fail("cannot write tensor256 dual address command");
    if (!run_command()) return false;
    out.valid = (read_word(kResultBase) & 1u) != 0;
    out.cell = read_word(kResultBase + 1);
    out.lane = static_cast<std::uint8_t>(read_word(kResultBase + 2) & 1u);
    out.byte_offset = read_word(kResultBase + 3);
    return true;
}

bool RawFieldVM::global_hodge(
    const std::array<float, 32640>& pair_flows,
    const std::vector<std::array<std::uint32_t, 3>>& triangles,
    std::array<float, 256>& divergence, std::array<float, 16>& curl) {
    if (triangles.size() > 16) return fail("global hodge accepts at most 16 faces");
    auto wf = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t i = 0; i < pair_flows.size(); ++i)
        if (!wf(0x360000u + static_cast<std::uint32_t>(i), pair_flows[i]))
            return fail("cannot write global hodge flows");
    for (std::size_t t = 0; t < triangles.size(); ++t)
        for (std::size_t k = 0; k < 3; ++k)
            if (!write_word(0x368000u + static_cast<std::uint32_t>(t * 3 + k),
                            triangles[t][k]))
                return fail("cannot write global hodge triangles");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(triangles.size())) ||
        !write_word(kCommandBase, 99))
        return fail("cannot write global hodge command");
    if (!run_command()) return false;
    if ((read_word(kResultBase) & 1u) == 0) {
        return fail("global hodge rejected status=" +
                    std::to_string(read_word(kResultBase + 1)));
    }
    for (std::size_t i = 0; i < divergence.size(); ++i) {
        const std::uint32_t bits = read_word(0x369000u + static_cast<std::uint32_t>(i));
        std::memcpy(&divergence[i], &bits, sizeof(bits));
    }
    for (std::size_t i = 0; i < curl.size(); ++i) {
        const std::uint32_t bits = read_word(0x369400u + static_cast<std::uint32_t>(i));
        std::memcpy(&curl[i], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::triangle_model_reset() {
    if (!write_word(kCommandBase, 90)) return fail("cannot write triangle model reset");
    return run_command();
}

bool RawFieldVM::triangle_model_observe(
    const std::array<std::int32_t, 3>& sides, std::int32_t area,
    std::int32_t tightness, std::int32_t orientation, std::int32_t& count) {
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(sides[0])) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(sides[1])) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(sides[2])) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(area)) ||
        !write_word(kProposalBase + 4, static_cast<std::uint32_t>(tightness)) ||
        !write_word(kProposalBase + 5, static_cast<std::uint32_t>(orientation)) ||
        !write_word(kCommandBase, 91)) return fail("cannot write triangle observe");
    if (!run_command()) return false;
    count = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}

bool RawFieldVM::triangle_model_score(
    const std::array<std::int32_t, 3>& sides, std::int32_t area,
    std::int32_t tightness, std::int32_t& score) {
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(sides[0])) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(sides[1])) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(sides[2])) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(area)) ||
        !write_word(kProposalBase + 4, static_cast<std::uint32_t>(tightness)) ||
        !write_word(kCommandBase, 92)) return fail("cannot write triangle score");
    if (!run_command()) return false;
    score = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}


bool RawFieldVM::triangle_model_observe_negative(
    const std::array<std::int32_t, 3>& sides, std::int32_t area,
    std::int32_t tightness, std::int32_t orientation, std::int32_t& count) {
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(sides[0])) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(sides[1])) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(sides[2])) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(area)) ||
        !write_word(kProposalBase + 4, static_cast<std::uint32_t>(tightness)) ||
        !write_word(kProposalBase + 5, static_cast<std::uint32_t>(orientation)) ||
        !write_word(kCommandBase, 93))
        return fail("cannot write triangle negative observe");
    if (!run_command()) return false;
    count = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}

bool RawFieldVM::triangle_model_score_contrastive(
    const std::array<std::int32_t, 3>& sides, std::int32_t area,
    std::int32_t tightness, std::int32_t& score) {
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(sides[0])) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(sides[1])) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(sides[2])) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(area)) ||
        !write_word(kProposalBase + 4, static_cast<std::uint32_t>(tightness)) ||
        !write_word(kCommandBase, 94))
        return fail("cannot write triangle contrastive score");
    if (!run_command()) return false;
    score = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}

bool RawFieldVM::read_triangle_model(
    std::array<std::int32_t, 3>& shape_stats,
    std::array<std::int32_t, 2>& orientation_counts) {
    shape_stats[0] = static_cast<std::int32_t>(
        read_word(0x2E0200u) / 256u);
    shape_stats[1] = static_cast<std::int32_t>(
        read_word(0x2E0201u) / 256u);
    shape_stats[2] = static_cast<std::int32_t>(read_word(0x2E0202u));
    for (std::size_t i = 0; i < 2; ++i)
        orientation_counts[i] = static_cast<std::int32_t>(
            read_word(0x2E0203u + static_cast<std::uint32_t>(i)));
    return true;
}

bool RawFieldVM::read_triangle_model_negative(
    std::array<std::int32_t, 3>& shape_stats,
    std::array<std::int32_t, 2>& orientation_counts) {
    shape_stats[0] = static_cast<std::int32_t>(
        read_word(0x2E0210u) / 256u);
    shape_stats[1] = static_cast<std::int32_t>(
        read_word(0x2E0211u) / 256u);
    shape_stats[2] = static_cast<std::int32_t>(read_word(0x2E0212u));
    for (std::size_t i = 0; i < 2; ++i)
        orientation_counts[i] = static_cast<std::int32_t>(
            read_word(0x2E0213u + static_cast<std::uint32_t>(i)));
    return true;
}

bool RawFieldVM::build_triangle_flow(
    const std::array<std::array<std::uint32_t, 3>, 16>& triads,
    std::size_t triad_count) {
    if (triad_count > 16) return fail("triangle flow count invalid");
    for (std::size_t t = 0; t < 16; ++t)
        for (std::size_t j = 0; j < 3; ++j)
            if (!write_word(0x368000u + static_cast<std::uint32_t>(t * 3 + j),
                            triads[t][j]))
                return fail("cannot write triangle flow triads");
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(triad_count)) ||
        !write_word(kCommandBase, 101)) return fail("cannot write triangle flow cmd");
    if (!run_command()) return false;
    return (read_word(kResultBase) & 1u) != 0;
}

bool RawFieldVM::global_hodge_from_triads(
    const std::array<std::array<std::uint32_t, 3>, 16>& triads,
    std::size_t triad_count, std::vector<float>& divergence,
    std::vector<float>& curl) {
    if (!build_triangle_flow(triads, triad_count)) return false;
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(triad_count)) ||
        !write_word(kCommandBase, 99)) return fail("cannot write hodge from triads");
    if (!run_command()) return false;
    divergence.resize(256); curl.resize(16);
    for (std::size_t i = 0; i < divergence.size(); ++i) {
        const std::uint32_t bits = read_word(0x369000u + static_cast<std::uint32_t>(i));
        std::memcpy(&divergence[i], &bits, sizeof(bits));
    }
    for (std::size_t i = 0; i < curl.size(); ++i) {
        const std::uint32_t bits = read_word(0x369400u + static_cast<std::uint32_t>(i));
        std::memcpy(&curl[i], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::meta_attention(
    const std::vector<float>& query, const std::vector<float>& keys,
    const std::vector<float>& values,
    const std::vector<std::uint32_t>& mask, std::size_t slots,
    std::size_t dim, std::vector<float>& out) {
    if (slots == 0 || slots > 16 || dim == 0 || dim > 256 ||
        query.size() < dim || keys.size() < slots * dim ||
        values.size() < slots * dim || mask.size() < slots)
        return fail("meta attention bounds invalid");
    for (std::size_t i = 0; i < dim; ++i) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &query[i], sizeof(bits));
        if (!write_word(0x340000u + static_cast<std::uint32_t>(i), bits))
            return fail("cannot write meta query");
    }
    for (std::size_t i = 0; i < slots * dim; ++i) {
        std::uint32_t kb = 0, vb = 0;
        std::memcpy(&kb, &keys[i], sizeof(kb));
        std::memcpy(&vb, &values[i], sizeof(vb));
        if (!write_word(0x340800u + static_cast<std::uint32_t>(i), kb) ||
            !write_word(0x341800u + static_cast<std::uint32_t>(i), vb))
            return fail("cannot write meta keys/values");
    }
    for (std::size_t i = 0; i < slots; ++i)
        if (!write_word(0x342800u + static_cast<std::uint32_t>(i), mask[i]))
            return fail("cannot write meta mask");
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(slots)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 102)) return fail("cannot write meta command");
    if (!run_command()) return false;
    if ((read_word(kResultBase) & 1u) == 0)
        return fail("native MC0 attention rejected invalid or uncommitted slots");
    out.resize(dim);
    for (std::size_t i = 0; i < dim; ++i) {
        const std::uint32_t bits = read_word(0x343000u + static_cast<std::uint32_t>(i));
        std::memcpy(&out[i], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::shape_field_reset() {
    if (!write_word(kCommandBase, 96)) return fail("cannot write shape field reset");
    return run_command();
}

bool RawFieldVM::shape_field_observe(std::uint32_t triad,
                                     std::int32_t tightness,
                                     std::int32_t orientation,
                                     std::int32_t area) {
    if (triad >= 85) return fail("shape field triad outside 0..84");
    if (!write_word(kProposalBase + 0, triad) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(tightness)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(orientation)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(area)) ||
        !write_word(kCommandBase, 97)) return fail("cannot write shape observe");
    return run_command();
}

bool RawFieldVM::shape_field_gate(std::int32_t closure,
                                  std::int32_t path_length,
                                  std::int32_t threshold,
                                  std::uint16_t& accepted, bool& field_hot,
                                  std::int32_t& mean_quality) {
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(closure)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(path_length)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(threshold)) ||
        !write_word(kCommandBase, 98)) return fail("cannot write shape gate");
    if (!run_command()) return false;
    accepted = static_cast<std::uint16_t>(read_word(kResultBase));
    field_hot = (read_word(kResultBase + 1) & 1u) != 0;
    mean_quality = static_cast<std::int32_t>(read_word(kResultBase + 2));
    return true;
}

bool RawFieldVM::phase_hyperbolic(
    const std::vector<std::int32_t>& phase_vector, std::size_t lanes,
    std::int32_t& mean_energy, std::int32_t& radial) {
    if (lanes == 0 || lanes > 128 || phase_vector.size() < lanes * 2)
        return fail("phase hyperbolic bounds invalid");
    for (std::size_t i = 0; i < lanes * 2; ++i)
        if (!write_word(0x340000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(phase_vector[i])))
            return fail("cannot write phase vector");
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(lanes)) ||
        !write_word(kCommandBase, 95)) return fail("cannot write phase hyperbolic");
    if (!run_command()) return false;
    mean_energy = static_cast<std::int32_t>(read_word(kResultBase));
    radial = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}

bool RawFieldVM::phase_table_init() {
    if (!write_word(kCommandBase, 64)) return fail("cannot write phase table init");
    if (!run_command()) return false;
    phase_table_ready_ = true;
    return true;
}

bool RawFieldVM::phase_encode_batch(const std::uint8_t* bytes,
                                    std::size_t windows, std::size_t window,
                                    std::size_t dim,
                                    std::vector<std::int32_t>& out) {
    if (!bytes || windows == 0 || windows > 1024 || window == 0 ||
        window > 8 || dim == 0 || dim > 128) {
        return fail("phase batch requires 1..1024 windows, W<=8, D<=128");
    }
    if (!phase_table_ready_ && !phase_table_init()) return false;
    for (std::size_t i = 0; i < windows * window; ++i) {
        if (!write_word(0x60000u + static_cast<std::uint32_t>(i), bytes[i])) {
            return fail("cannot write phase batch input");
        }
    }
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(windows)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(window)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(dim)) ||
        !write_word(kCommandBase, 63)) {
        return fail("cannot write phase batch command");
    }
    if (!run_command()) return false;
    out.resize(windows * dim * 2);
    for (std::size_t i = 0; i < out.size(); ++i) {
        out[i] = static_cast<std::int32_t>(
            read_word(0x70000u + static_cast<std::uint32_t>(i)));
    }
    return true;
}


bool RawFieldVM::vector_matrix_reset() {
    if (!write_word(kCommandBase, 65)) return fail("cannot write vector matrix reset");
    return run_command();
}

bool RawFieldVM::vector_matrix_accumulate(std::uint8_t a, std::uint8_t b,
                                          std::int32_t delta,
                                          std::uint32_t& index,
                                          std::int32_t& value) {
    if (!write_word(kProposalBase + 0, a) ||
        !write_word(kProposalBase + 1, b) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(delta)) ||
        !write_word(kCommandBase, 66))
        return fail("cannot write vector matrix accumulate");
    if (!run_command()) return false;
    index = read_word(kResultBase + 0);
    value = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}

bool RawFieldVM::vector_matrix_probe(std::uint8_t a, std::int32_t threshold,
                                     std::int32_t& best_head,
                                     std::int32_t& score) {
    if (!write_word(kProposalBase + 0, a) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(threshold)) ||
        !write_word(kCommandBase, 67))
        return fail("cannot write vector matrix probe");
    if (!run_command()) return false;
    best_head = static_cast<std::int32_t>(read_word(kResultBase + 0));
    score = static_cast<std::int32_t>(read_word(kResultBase + 1));
    return true;
}

bool RawFieldVM::read_vector_matrix(std::vector<std::int32_t>& cells) {
    cells.resize(32640);
    for (std::size_t i = 0; i < cells.size(); ++i)
        cells[i] = static_cast<std::int32_t>(read_word(0x300000u + static_cast<std::uint32_t>(i)));
    return true;
}


bool RawFieldVM::vector_matrix_credits(std::vector<std::int32_t>& credits) {
    if (!write_word(kCommandBase, 68))
        return fail("cannot write vector matrix credits");
    if (!run_command()) return false;
    credits.resize(255);
    for (std::size_t i = 0; i < credits.size(); ++i)
        credits[i] = static_cast<std::int32_t>(
            read_word(0x7000u + static_cast<std::uint32_t>(i)));
    return true;
}


bool RawFieldVM::load_vector_matrix(const std::vector<std::int32_t>& cells) {
    if (cells.size() != 32640) return fail("vector matrix needs 32640 cells");
    for (std::size_t i = 0; i < cells.size(); ++i)
        if (!write_word(0x300000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(cells[i])))
            return fail("cannot load vector matrix");
    return true;
}

bool RawFieldVM::reset_context_readout(std::size_t buckets) {
    if (buckets == 0 || buckets > 16384) {
        return fail("context bucket count outside 1..16384");
    }
    const std::size_t words = 16 * buckets + 16 * 16 * buckets;
    for (std::size_t i = 0; i < words; ++i) {
        if (!write_word(0x100000u + static_cast<std::uint32_t>(i), 0)) {
            return fail("cannot reset context readout");
        }
    }
    return true;
}


bool RawFieldVM::load_context_readout(const std::string& path,
                                      std::size_t buckets) {
    const std::size_t words = 272 * buckets;
    std::ifstream in(path, std::ios::binary);
    if (!in) return fail("cannot open context checkpoint: " + path);
    in.seekg(0, std::ios::end);
    const std::streamoff bytes = in.tellg();
    if (bytes < 0 || static_cast<std::size_t>(bytes) != words * 4) {
        return fail("context checkpoint size mismatch");
    }
    in.seekg(0, std::ios::beg);
    std::array<std::uint8_t, 4> raw{};
    for (std::size_t i = 0; i < words; ++i) {
        if (!in.read(reinterpret_cast<char*>(raw.data()), raw.size())) {
            return fail("cannot read context checkpoint");
        }
        const std::uint32_t bits = static_cast<std::uint32_t>(raw[0]) |
            (static_cast<std::uint32_t>(raw[1]) << 8) |
            (static_cast<std::uint32_t>(raw[2]) << 16) |
            (static_cast<std::uint32_t>(raw[3]) << 24);
        if (!write_word(0x100000u + static_cast<std::uint32_t>(i), bits)) {
            return fail("cannot write context checkpoint");
        }
    }
    return true;
}

bool RawFieldVM::save_context_readout(const std::string& path,
                                      std::size_t buckets) {
    const std::size_t words = 272 * buckets;
    std::ofstream out(path, std::ios::binary);
    if (!out) return fail("cannot create context checkpoint: " + path);
    for (std::size_t i = 0; i < words; ++i) {
        const std::uint32_t bits = read_word(0x100000u + static_cast<std::uint32_t>(i));
        const std::array<std::uint8_t, 4> raw = {
            static_cast<std::uint8_t>(bits & 0xFFu),
            static_cast<std::uint8_t>((bits >> 8) & 0xFFu),
            static_cast<std::uint8_t>((bits >> 16) & 0xFFu),
            static_cast<std::uint8_t>((bits >> 24) & 0xFFu)};
        out.write(reinterpret_cast<const char*>(raw.data()), raw.size());
    }
    return static_cast<bool>(out);
}

bool RawFieldVM::readout_context(std::uint8_t target, float learning_rate,
                                 std::uint32_t bucket, std::size_t buckets,
                                 bool& correct, float& loss,
                                 std::uint8_t& predicted_high,
                                 std::uint8_t& predicted_low) {
    if (buckets == 0 || buckets > 16384 || bucket >= buckets) {
        return fail("invalid context readout bucket");
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kProposalBase + 2, bucket) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(buckets)) ||
        !write_word(kCommandBase, 25)) {
        return fail("cannot write context readout command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ls = read_word(kResultBase + 1);
    std::memcpy(&loss, &ls, sizeof(ls));
    predicted_high = static_cast<std::uint8_t>(read_word(kResultBase + 2) & 15u);
    predicted_low = static_cast<std::uint8_t>(read_word(kResultBase + 3) & 15u);
    return true;
}

bool RawFieldVM::readout_context_joint(std::uint8_t target,
                                       float learning_rate,
                                       std::uint32_t bucket,
                                       std::size_t buckets, bool& correct,
                                       float& loss,
                                       std::uint8_t& predicted_high,
                                       std::uint8_t& predicted_low) {
    if (buckets == 0 || buckets > 16384 || bucket >= buckets) {
        return fail("invalid context joint-readout bucket");
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kProposalBase + 2, bucket) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(buckets)) ||
        !write_word(kCommandBase, 43)) {
        return fail("cannot write context joint-readout command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ls = read_word(kResultBase + 1);
    std::memcpy(&loss, &ls, sizeof(ls));
    predicted_high = static_cast<std::uint8_t>(read_word(kResultBase + 2) & 15u);
    predicted_low = static_cast<std::uint8_t>(read_word(kResultBase + 3) & 15u);
    return true;
}

bool RawFieldVM::set_context_high(std::size_t bucket, std::size_t high_class,
                                  float value, std::size_t buckets) {
    if (buckets == 0 || buckets > 16384 || bucket >= buckets ||
        high_class >= 16) {
        return fail("invalid context high-cell");
    }
    std::uint32_t bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));
    const std::uint32_t word = 0x100000u +
        static_cast<std::uint32_t>(high_class * buckets + bucket);
    return write_word(word, bits) ? true
                                  : fail("cannot write context high-cell");
}

bool RawFieldVM::set_context_low(std::size_t bucket, std::size_t high_class,
                                 std::size_t low_class, float value,
                                 std::size_t buckets) {
    if (buckets == 0 || buckets > 16384 || bucket >= buckets ||
        high_class >= 16 || low_class >= 16) {
        return fail("invalid context low-cell");
    }
    std::uint32_t bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));
    const std::uint32_t base = 0x100000u +
        static_cast<std::uint32_t>(16 * buckets);
    const std::uint32_t word = base + static_cast<std::uint32_t>(
        (high_class * 16 + low_class) * buckets + bucket);
    return write_word(word, bits) ? true
                                  : fail("cannot write context low-cell");
}

bool RawFieldVM::reset_context_copy(
    const std::vector<std::uint32_t>& exact_contexts,
    std::size_t buckets, std::size_t aux_buckets) {
    if (buckets == 0 || buckets > 16384 || aux_buckets == 0 ||
        aux_buckets > kContextAuxMax) {
        return fail("context copy table dimensions are invalid");
    }
    if (exact_contexts.size() > buckets) {
        return fail("context copy exact map exceeds bucket count");
    }
    for (std::uint32_t i = 0; i < kContextMapWords; ++i)
        if (!write_word(kContextMapBase + i, 0))
            return fail("cannot reset context exact-key map");
    for (std::size_t bucket = 0; bucket < exact_contexts.size(); ++bucket) {
        const std::uint32_t key = exact_contexts[bucket];
        std::uint32_t slot = context_copy_hash(key) % kContextMapSlots;
        for (std::uint32_t probe = 0; probe < kContextMapSlots; ++probe) {
            const std::uint32_t base = kContextMapBase + slot * 3u;
            if (read_word(base) == 0) {
                if (!write_word(base, 1) ||
                    !write_word(base + 1u, key) ||
                    !write_word(base + 2u, static_cast<std::uint32_t>(bucket)))
                    return fail("cannot write context exact-key map");
                break;
            }
            slot = (slot + 1u) % kContextMapSlots;
            if (probe + 1u == kContextMapSlots)
                return fail("context exact-key map is full");
        }
    }
    const std::size_t aux_words = 272u * aux_buckets;
    for (std::size_t i = 0; i < aux_words; ++i)
        if (!write_word(kContextCopyBase + static_cast<std::uint32_t>(i), 0))
            return fail("cannot reset context copy table");
    return true;
}

bool RawFieldVM::readout_context_copy(
    std::uint8_t target, float learning_rate, std::uint32_t context_key,
    std::size_t buckets, std::size_t exact_count, std::size_t aux_buckets,
    float gate_weight, bool& correct, float& loss,
    std::uint8_t& predicted_class) {
    if (buckets == 0 || buckets > 16384 || exact_count >= buckets ||
        aux_buckets == 0 || aux_buckets > kContextAuxMax) {
        return fail("invalid context copy readout dimensions");
    }
    std::uint32_t lr_bits = 0, weight_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    std::memcpy(&weight_bits, &gate_weight, sizeof(weight_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, lr_bits) ||
        !write_word(kProposalBase + 2, context_key) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(buckets)) ||
        !write_word(kProposalBase + 4, static_cast<std::uint32_t>(exact_count)) ||
        !write_word(kProposalBase + 5, static_cast<std::uint32_t>(aux_buckets)) ||
        !write_word(kProposalBase + 6, weight_bits) ||
        !write_word(kCommandBase, 44)) {
        return fail("cannot write context copy command");
    }
    if (!run_command()) return false;
    correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t ls = read_word(kResultBase + 1);
    std::memcpy(&loss, &ls, sizeof(ls));
    predicted_class = static_cast<std::uint8_t>(read_word(kResultBase + 2));
    return true;
}

bool RawFieldVM::reset_context_backoff() {
    for (std::uint32_t i = 0; i < kContextBackoffTableWords; ++i) {
        if (!write_word(kContextBackoffTable + i, 0)) {
            return fail("cannot reset context backoff table");
        }
    }
    for (std::uint32_t i = 0; i < kContextBackoffHistWords; ++i) {
        if (!write_word(kContextBackoffHist + i, 0)) {
            return fail("cannot reset context backoff histogram");
        }
    }
    if (!write_word(kProposalBase + 0, 5) ||
        !write_word(kCommandBase, kContextBackoffCommand)) {
        return fail("cannot reset context backoff state");
    }
    return run_command();
}

bool RawFieldVM::context_backoff_build(std::uint32_t key,
                                       bool* inserted) {
    if (!write_word(kProposalBase + 0, 1) ||
        !write_word(kProposalBase + 1, key) ||
        !write_word(kCommandBase, kContextBackoffCommand)) {
        return fail("cannot write context backoff build command");
    }
    if (!run_command()) return false;
    if (inserted) *inserted = (read_word(kResultBase + 0) & 1u) != 0;
    return true;
}

bool RawFieldVM::context_backoff_build_batch(const std::uint32_t* keys,
                                             std::size_t count,
                                             std::size_t& inserted) {
    constexpr std::uint32_t kKeyBuffer = 0x60000;
    constexpr std::size_t kChunk = 4096;
    inserted = 0;
    if (!keys && count) return fail("context backoff keys are null");
    for (std::size_t base = 0; base < count; base += kChunk) {
        const std::size_t n = std::min(kChunk, count - base);
        for (std::size_t i = 0; i < n; ++i) {
            if (!write_word(kKeyBuffer + static_cast<std::uint32_t>(i), keys[base + i])) {
                return fail("cannot write context backoff key batch");
            }
        }
        if (!write_word(kProposalBase + 0, 4) ||
            !write_word(kProposalBase + 1, static_cast<std::uint32_t>(n)) ||
            !write_word(kProposalBase + 2, kKeyBuffer) ||
            !write_word(kCommandBase, kContextBackoffCommand)) {
            return fail("cannot write context backoff batch command");
        }
        if (!run_command()) return false;
        inserted += read_word(kResultBase + 0);
    }
    return true;
}

bool RawFieldVM::context_backoff_select(std::size_t buckets,
                                        std::size_t exact_limit,
                                        ContextBackoffSelection& out) {
    if (buckets < 2 || buckets > 16384 ||
        exact_limit > 16384) {
        return fail("context backoff buckets 2..16384, exact limit <= 16384");
    }
    if (!write_word(kProposalBase + 0, 2) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(buckets)) ||
        !write_word(kProposalBase + 2,
                    static_cast<std::uint32_t>(exact_limit)) ||
        !write_word(kCommandBase, kContextBackoffCommand)) {
        return fail("cannot write context backoff select command");
    }
    if (!run_command()) return false;
    out.exact_count = read_word(kResultBase + 0);
    out.fallback = read_word(kResultBase + 1);
    out.threshold = read_word(kResultBase + 2);
    out.unique = read_word(kResultBase + 3);
    return true;
}

bool RawFieldVM::readout_context_backoff(std::uint8_t target,
                                         float learning_rate,
                                         std::uint32_t key,
                                         std::size_t buckets,
                                         ContextBackoffStep& out) {
    if (buckets < 2 || buckets > 16384) {
        return fail("context backoff buckets outside 2..16384");
    }
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, 3) ||
        !write_word(kProposalBase + 1, target) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kProposalBase + 3, key) ||
        !write_word(kProposalBase + 4, static_cast<std::uint32_t>(buckets)) ||
        !write_word(kCommandBase, kContextBackoffCommand)) {
        return fail("cannot write context backoff step command");
    }
    if (!run_command()) return false;
    out.correct = (read_word(kResultBase + 0) & 1u) != 0;
    const std::uint32_t loss_bits = read_word(kResultBase + 1);
    std::memcpy(&out.loss, &loss_bits, sizeof(loss_bits));
    out.predicted_high = static_cast<std::uint8_t>(read_word(kResultBase + 2) & 15u);
    out.predicted_low = static_cast<std::uint8_t>(read_word(kResultBase + 3) & 15u);
    out.exact = (read_word(kResultBase + 4) & 1u) != 0;
    out.bucket = read_word(kResultBase + 5);
    return true;
}

void RawFieldVM::reset_readout() {
    for (std::uint32_t i = 0; i < 255u * 8u; ++i) {
        (void)write_word(0xB000u + i, 0);
    }
}

bool RawFieldVM::field_commit(
    const std::array<std::int32_t, kTriadCount>& credits,
    std::int32_t threshold,
    std::array<std::uint8_t, kTriadCount>& votes,
    std::uint16_t& accepted_count, bool& committed) {
    for (std::size_t i = 0; i < credits.size(); ++i) {
        if (!write_word(0x7000 + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i])) ||
            !write_word(0x7100 + static_cast<std::uint32_t>(i), 0)) {
            return fail("cannot write field commit credits");
        }
    }
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(threshold)) ||
        !write_word(kCommandBase, 11)) {
        return fail("cannot write field commit command");
    }
    if (!run_command()) return false;
    accepted_count = static_cast<std::uint16_t>(read_word(kResultBase + 0));
    committed = (read_word(kResultBase + 1) & 1u) != 0;
    for (std::size_t i = 0; i < votes.size(); ++i) {
        votes[i] = static_cast<std::uint8_t>(read_word(0x7100 +
                                                      static_cast<std::uint32_t>(i)) & 1u);
    }
    return true;
}


bool RawFieldVM::causal_trunk_wide(
    const std::vector<float>& tokens, std::size_t count,
    const WideTrunkWeights& weights, std::vector<float>& out) {
    const std::size_t d = weights.dim;
    const std::size_t h = weights.hidden;
    if (count == 0 || count > 1024 || d == 0 || d > 128 || h == 0 || h > 512 ||
        tokens.size() != count * d ||
        weights.wq.size() != d * d || weights.wk.size() != d * d ||
        weights.wv.size() != d * d || weights.wout.size() != d * d ||
        weights.w1.size() != h * d || weights.w2.size() != d * h) {
        return fail("wide causal trunk dimensions are invalid");
    }
    auto write_float = [&](std::uint32_t index, float value) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return write_word(index, bits);
    };
    for (std::size_t i = 0; i < tokens.size(); ++i) {
        if (!write_float(0x10000u + static_cast<std::uint32_t>(i), tokens[i])) {
            return fail("cannot write wide-trunk tokens");
        }
    }
    const struct {
        const std::vector<float>* values;
        std::uint32_t base;
    } blocks[] = {
        {&weights.wq, 0x60000u},
        {&weights.wk, 0x60000u + static_cast<std::uint32_t>(d * d)},
        {&weights.wv, 0x60000u + static_cast<std::uint32_t>(2 * d * d)},
        {&weights.wout, 0x60000u + static_cast<std::uint32_t>(3 * d * d)},
        {&weights.w1, 0x60000u + static_cast<std::uint32_t>(4 * d * d)},
        {&weights.w2, 0x60000u + static_cast<std::uint32_t>(4 * d * d + h * d)},
    };
    for (const auto& block : blocks) {
        for (std::size_t i = 0; i < block.values->size(); ++i) {
            if (!write_float(block.base + static_cast<std::uint32_t>(i),
                             (*block.values)[i])) {
                return fail("cannot write wide-trunk weights");
            }
        }
    }
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(d)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(h)) ||
        !write_word(kCommandBase, 13)) {
        return fail("cannot write wide-trunk command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != d) {
        return fail("raw wide trunk returned the wrong feature count " +
                    std::to_string(read_word(kResultBase)));
    }
    out.assign(d, 0.0f);
    for (std::size_t i = 0; i < d; ++i) {
        const std::uint32_t bits = read_word(0x200000u + static_cast<std::uint32_t>(i));
        std::memcpy(&out[i], &bits, sizeof(bits));
    }
    return true;
}


bool RawFieldVM::trunk_credit(std::uint8_t target, std::uint8_t best_wrong,
                              float learning_rate) {
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kCommandBase, 14)) {
        return fail("cannot write trunk-credit command");
    }
    if (!run_command()) return false;
    if ((read_word(kResultBase) & 1u) == 0) {
        return fail("raw trunk credit did not complete");
    }
    return true;
}


bool RawFieldVM::qkv_credit(std::uint8_t target, std::uint8_t best_wrong,
                            float learning_rate) {
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kCommandBase, 15)) {
        return fail("cannot write QKV-credit command");
    }
    if (!run_command()) return false;
    if ((read_word(kResultBase) & 1u) == 0) {
        return fail("raw QKV credit did not complete");
    }
    return true;
}


bool RawFieldVM::causal_trunk_wide_cached(const std::vector<float>& tokens,
                                          std::size_t count, std::size_t dim,
                                          std::vector<float>& out) {
    if (count == 0 || count > 1024 || dim == 0 || dim > 256 ||
        tokens.size() != count * dim) {
        return fail("wide cached trunk dimensions are invalid");
    }
    for (std::size_t i = 0; i < tokens.size(); ++i) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &tokens[i], sizeof(bits));
        if (!write_word(0x10000u + static_cast<std::uint32_t>(i), bits)) {
            return fail("cannot write cached wide tokens");
        }
    }
    if (!write_word(kProposalBase + 0, static_cast<std::uint32_t>(count)) ||
        !write_word(kProposalBase + 1, static_cast<std::uint32_t>(dim)) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(4 * dim)) ||
        !write_word(kCommandBase, 13)) {
        return fail("cannot write cached wide command");
    }
    if (!run_command()) return false;
    if (read_word(kResultBase) != dim) {
        return fail("cached wide trunk returned the wrong feature count");
    }
    out.assign(dim, 0.0f);
    for (std::size_t i = 0; i < dim; ++i) {
        const std::uint32_t bits = read_word(0x200000u + static_cast<std::uint32_t>(i));
        std::memcpy(&out[i], &bits, sizeof(bits));
    }
    return true;
}

bool RawFieldVM::set_wide_readout_row(std::uint8_t row, const float* values,
                                      std::size_t dim) {
    if (row >= 255 || dim == 0 || dim > 128) return fail("wide readout row invalid");
    for (std::size_t i = 0; i < dim; ++i) {
        std::uint32_t bits = 0;
        std::memcpy(&bits, &values[i], sizeof(bits));
        if (!write_word(0x180000u + static_cast<std::uint32_t>(row * dim + i),
                        bits)) return fail("cannot write wide readout row");
    }
    return true;
}

bool RawFieldVM::qkv_credit_wide(std::uint8_t target, std::uint8_t best_wrong,
                                 float learning_rate) {
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kCommandBase, 18)) {
        return fail("cannot write wide QKV-credit command");
    }
    if (!run_command()) return false;
    if ((read_word(kResultBase) & 1u) == 0) {
        return fail("raw wide QKV credit did not complete");
    }
    return true;
}


bool RawFieldVM::trunk_credit_wide(std::uint8_t target,
                                   std::uint8_t best_wrong,
                                   float learning_rate) {
    std::uint32_t lr_bits = 0;
    std::memcpy(&lr_bits, &learning_rate, sizeof(lr_bits));
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, lr_bits) ||
        !write_word(kCommandBase, 20)) {
        return fail("cannot write wide trunk-credit command");
    }
    if (!run_command()) return false;
    if ((read_word(kResultBase) & 1u) == 0) {
        return fail("raw wide trunk credit did not complete");
    }
    return true;
}



bool RawFieldVM::combine_credits(const std::array<std::int32_t, 7>& credits,
                                 const std::array<std::int32_t, 7>& coefficients,
                                 std::int32_t& combined) {
    for (std::size_t i = 0; i < 7; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i])) ||
            !write_word(0x7100u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(coefficients[i]))) {
            return fail("cannot write credit-combine args");
        }
    }
    if (!write_word(kCommandBase, 31)) {
        return fail("cannot write credit-combine command");
    }
    if (!run_command()) return false;
    combined = static_cast<std::int32_t>(read_word(kResultBase));
    return true;
}



bool RawFieldVM::credit_bundle(const CreditBundleState& state,
                               std::array<std::int32_t, 7>& credits) {
    auto w = [&](std::uint32_t index, std::int32_t value) {
        return write_word(index, static_cast<std::uint32_t>(value));
    };
    for (std::size_t i = 0; i < state.cft.size(); ++i)
        if (!w(0x8000u + i, state.cft[i])) return fail("cannot write CFT bundle");
    for (std::size_t i = 0; i < state.trail.size(); ++i)
        if (!w(0x8010u + i, state.trail[i])) return fail("cannot write TRAIL bundle");
    for (std::size_t i = 0; i < state.holo.size(); ++i)
        if (!w(0x8020u + i, state.holo[i])) return fail("cannot write HOLO bundle");
    if (!w(0x8030u, state.ring_shift)) return fail("cannot write RING shift");
    for (std::size_t i = 0; i < state.ring_phases.size(); ++i)
        if (!write_word(0x7500u + static_cast<std::uint32_t>(i),
                        state.ring_phases[i])) return fail("cannot write RING phases");
    for (std::size_t i = 0; i < state.leaf.size(); ++i)
        if (!w(0x8040u + i, state.leaf[i])) return fail("cannot write LEAF bundle");
    for (std::size_t i = 0; i < state.tca.size(); ++i)
        if (!w(0x8050u + i, state.tca[i])) return fail("cannot write TCA bundle");
    for (std::size_t i = 0; i < state.flux.size(); ++i)
        if (!w(0x8060u + i, state.flux[i])) return fail("cannot write FLUX bundle");
    if (!write_word(kCommandBase, 29)) return fail("cannot write credit-bundle command");
    if (!run_command()) return false;
    for (std::size_t i = 0; i < credits.size(); ++i) {
        credits[i] = static_cast<std::int32_t>(read_word(0x7200u +
                                                        static_cast<std::uint32_t>(i)));
    }
    return true;
}

bool RawFieldVM::credit_ablation(
    const CreditBundleState& state,
    const std::array<std::int32_t, 7>& base_coefficients,
    std::array<std::int32_t, 8>& combined) {
    std::array<std::int32_t, 7> credits{};
    if (!credit_bundle(state, credits)) return false;
    std::int32_t value = 0;
    if (!combine_credits(credits, base_coefficients, value)) return false;
    combined[0] = value;
    for (std::size_t ablate = 0; ablate < 7; ++ablate) {
        std::array<std::int32_t, 7> coefficients = base_coefficients;
        coefficients[ablate] = 0;
        if (!combine_credits(credits, coefficients, value)) return false;
        combined[ablate + 1] = value;
    }
    return true;
}

bool RawFieldVM::combined_trunk_credit(
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t threshold_q16,
    const std::array<std::int32_t, 7>& credits,
    const std::array<std::int32_t, 7>& coefficients, bool& applied) {
    for (std::size_t i = 0; i < 7; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i])) ||
            !write_word(0x7100u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(coefficients[i]))) {
            return fail("cannot write combined-credit args");
        }
    }
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(base_lr_q16)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(threshold_q16)) ||
        !write_word(kCommandBase, 32)) {
        return fail("cannot write combined-credit command");
    }
    if (!run_command()) return false;
    applied = (read_word(kResultBase) & 1u) != 0;
    return true;
}


bool RawFieldVM::combined_trunk_credit_all(
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t threshold_q16,
    const std::array<std::int32_t, 7>& credits,
    const std::array<std::int32_t, 7>& coefficients, bool& applied) {
    for (std::size_t i = 0; i < 7; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i])) ||
            !write_word(0x7100u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(coefficients[i]))) {
            return fail("cannot write combined-all args");
        }
    }
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(base_lr_q16)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(threshold_q16)) ||
        !write_word(kCommandBase, 33)) {
        return fail("cannot write combined-all command");
    }
    if (!run_command()) return false;
    applied = (read_word(kResultBase) & 1u) != 0;
    return true;
}

bool RawFieldVM::write_wide_weights(const WideTrunkWeights& weights) {
    const std::size_t d = weights.dim;
    const std::size_t h = weights.hidden;
    if (d == 0 || d > 128 || h == 0 || h > 512) return false;
    const std::uint32_t bases[6] = {
        0x60000u,
        0x60000u + static_cast<std::uint32_t>(d * d),
        0x60000u + static_cast<std::uint32_t>(2 * d * d),
        0x60000u + static_cast<std::uint32_t>(3 * d * d),
        0x60000u + static_cast<std::uint32_t>(4 * d * d),
        0x60000u + static_cast<std::uint32_t>(4 * d * d + h * d)};
    const std::vector<float>* blocks[6] = {
        &weights.wq, &weights.wk, &weights.wv,
        &weights.wout, &weights.w1, &weights.w2};
    for (std::size_t b = 0; b < 6; ++b) {
        for (std::size_t i = 0; i < blocks[b]->size(); ++i) {
            std::uint32_t bits = 0;
            std::memcpy(&bits, &(*blocks[b])[i], sizeof(bits));
            if (!write_word(bases[b] + static_cast<std::uint32_t>(i), bits)) {
                return fail("cannot write wide weights");
            }
        }
    }
    return true;
}

bool RawFieldVM::combined_trunk_credit_wide(
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t threshold_q16,
    const std::array<std::int32_t, 7>& credits,
    const std::array<std::int32_t, 7>& coefficients, bool& applied) {
    for (std::size_t i = 0; i < 7; ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i])) ||
            !write_word(0x7100u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(coefficients[i]))) {
            return fail("cannot write combined-wide args");
        }
    }
    if (!write_word(kProposalBase + 0, target) ||
        !write_word(kProposalBase + 1, best_wrong) ||
        !write_word(kProposalBase + 2, static_cast<std::uint32_t>(base_lr_q16)) ||
        !write_word(kProposalBase + 3, static_cast<std::uint32_t>(threshold_q16)) ||
        !write_word(kCommandBase, 34)) {
        return fail("cannot write combined-wide command");
    }
    if (!run_command()) return false;
    applied = (read_word(kResultBase) & 1u) != 0;
    return true;
}

bool RawFieldVM::commit_combined_credit(
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t threshold_q16,
    const std::array<std::int32_t, 7>& credits,
    const std::array<std::int32_t, 7>& coefficients,
    const std::array<std::int32_t, kTriadMemberCount>& head_credits,
    std::int32_t head_threshold_q16,
    bool& field_accepted, bool& committed) {
    TrunkWeights snapshot{};
    if (!read_trunk_weights(snapshot)) return fail("cannot snapshot trunk");
    std::array<std::uint8_t, kTriadCount> votes{};
    std::uint16_t accepted = 0;
    if (!credit_field_vote(head_credits, head_threshold_q16, votes,
                           accepted, field_accepted)) return false;
    committed = false;
    if (!field_accepted) return true;
    bool applied = false;
    if (!combined_trunk_credit_all(target, best_wrong, base_lr_q16,
                                   threshold_q16, credits, coefficients,
                                   applied)) {
        (void)write_trunk_weights(snapshot);
        return false;
    }
    if (!applied) {
        (void)write_trunk_weights(snapshot);
        return true;
    }
    committed = true;
    return true;
}


bool RawFieldVM::commit_combined_credit_wide(
    std::size_t dim, std::size_t hidden,
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t threshold_q16,
    const std::array<std::int32_t, 7>& credits,
    const std::array<std::int32_t, 7>& coefficients,
    const std::array<std::int32_t, kTriadMemberCount>& head_credits,
    std::int32_t head_threshold_q16,
    bool& field_accepted, bool& committed) {
    WideTrunkWeights snapshot{};
    if (!read_wide_weights(dim, hidden, snapshot)) return fail("cannot snapshot wide trunk");
    std::array<std::uint8_t, kTriadCount> votes{};
    std::uint16_t accepted = 0;
    if (!credit_field_vote(head_credits, head_threshold_q16, votes,
                           accepted, field_accepted)) return false;
    committed = false;
    if (!field_accepted) return true;
    bool applied = false;
    if (!combined_trunk_credit_wide(target, best_wrong, base_lr_q16,
                                    threshold_q16, credits, coefficients,
                                    applied)) {
        (void)write_wide_weights(snapshot);
        return false;
    }
    if (!applied) {
        (void)write_wide_weights(snapshot);
        return true;
    }
    committed = true;
    return true;
}

bool RawFieldVM::cft_trunk_credit(std::uint8_t target, std::uint8_t best_wrong,
                                  std::int32_t base_lr_q16,
                                  std::int32_t threshold_q16,
                                  std::int32_t e_ab, std::int32_t e_bc,
                                  std::int32_t e_ca, std::int32_t error,
                                  std::int32_t rate, bool& applied) {
    const std::uint32_t args[9] = {
        target, best_wrong, static_cast<std::uint32_t>(base_lr_q16),
        static_cast<std::uint32_t>(threshold_q16), static_cast<std::uint32_t>(e_ab),
        static_cast<std::uint32_t>(e_bc), static_cast<std::uint32_t>(e_ca),
        static_cast<std::uint32_t>(error), static_cast<std::uint32_t>(rate)};
    for (std::size_t i = 0; i < 9; ++i) {
        if (!write_word(kProposalBase + static_cast<std::uint32_t>(i), args[i])) {
            return fail("cannot write CFT trunk-credit args");
        }
    }
    if (!write_word(kCommandBase, 22)) {
        return fail("cannot write CFT trunk-credit command");
    }
    if (!run_command()) return false;
    applied = (read_word(kResultBase) & 1u) != 0;
    return true;
}


bool RawFieldVM::credit_field_vote(
    const std::array<std::int32_t, kTriadMemberCount>& credits,
    std::int32_t threshold,
    std::array<std::uint8_t, kTriadCount>& votes,
    std::uint16_t& accepted_count, bool& field_accepted) {
    for (std::size_t i = 0; i < credits.size(); ++i) {
        if (!write_word(0x7000u + static_cast<std::uint32_t>(i),
                        static_cast<std::uint32_t>(credits[i]))) {
            return fail("cannot write credit-field credits");
        }
    }
    if (!write_word(kProposalBase, static_cast<std::uint32_t>(threshold)) ||
        !write_word(kCommandBase, 24)) {
        return fail("cannot write credit-field command");
    }
    if (!run_command()) return false;
    accepted_count = static_cast<std::uint16_t>(read_word(kResultBase + 0));
    field_accepted = (read_word(kResultBase + 1) & 1u) != 0;
    for (std::size_t i = 0; i < votes.size(); ++i) {
        votes[i] = static_cast<std::uint8_t>(read_word(0x7100u +
                                                      static_cast<std::uint32_t>(i)) & 1u);
    }
    return true;
}


bool RawFieldVM::write_trunk_weights(const TrunkWeights& weights) {
    auto write_block = [&](std::uint32_t base, const float* data,
                           std::size_t count) {
        for (std::size_t i = 0; i < count; ++i) {
            std::uint32_t bits = 0;
            std::memcpy(&bits, &data[i], sizeof(bits));
            if (!write_word(base + static_cast<std::uint32_t>(i), bits)) {
                return false;
            }
        }
        return true;
    };
    return write_block(0x9000, weights.wq.data(), weights.wq.size()) &&
           write_block(0x9040, weights.wk.data(), weights.wk.size()) &&
           write_block(0x9080, weights.wv.data(), weights.wv.size()) &&
           write_block(0x90C0, weights.wout.data(), weights.wout.size()) &&
           write_block(0x9100, weights.w1.data(), weights.w1.size()) &&
           write_block(0x9180, weights.w2.data(), weights.w2.size());
}

bool RawFieldVM::commit_cft_credit(
    std::uint8_t target, std::uint8_t best_wrong,
    std::int32_t base_lr_q16, std::int32_t cft_threshold_q16,
    std::int32_t e_ab, std::int32_t e_bc, std::int32_t e_ca,
    std::int32_t error, std::int32_t rate,
    const std::array<std::int32_t, kTriadMemberCount>& head_credits,
    std::int32_t head_threshold_q16,
    bool& field_accepted, bool& committed) {
    TrunkWeights snapshot{};
    if (!read_trunk_weights(snapshot)) return fail("cannot snapshot trunk weights");
    std::array<std::uint8_t, kTriadCount> votes{};
    std::uint16_t accepted = 0;
    if (!credit_field_vote(head_credits, head_threshold_q16, votes,
                           accepted, field_accepted)) {
        return false;
    }
    committed = false;
    if (!field_accepted) return true;
    bool applied = false;
    if (!cft_trunk_credit(target, best_wrong, base_lr_q16, cft_threshold_q16,
                          e_ab, e_bc, e_ca, error, rate, applied)) {
        (void)write_trunk_weights(snapshot);
        return false;
    }
    if (!applied) {
        (void)write_trunk_weights(snapshot);
        return true;
    }
    committed = true;
    return true;
}

bool RawFieldVM::remap(const std::array<std::uint16_t, 6>& masks,
                       std::uint32_t a, std::uint32_t b, bool target,
                       bool& improved, std::int32_t& before,
                       std::int32_t& after) {
    for (std::size_t i = 0; i < masks.size(); ++i) {
        if (!write_word(kProposalBase + static_cast<std::uint32_t>(i), masks[i])) {
            return fail("cannot write remap masks");
        }
    }
    if (!write_word(kProposalBase + 6, a) ||
        !write_word(kProposalBase + 7, b) ||
        !write_word(kProposalBase + 8, target ? 1u : 0u) ||
        !write_word(kCommandBase, 4)) {
        return fail("cannot write remap command");
    }
    if (!run_command()) return false;
    improved = (read_word(kResultBase + 0) & 1u) != 0;
    before = static_cast<std::int32_t>(read_word(kResultBase + 1));
    after = static_cast<std::int32_t>(read_word(kResultBase + 2));
    return true;
}

bool RawFieldVM::remap_general(const std::array<std::uint16_t, 6>& masks,
                                std::uint8_t slot_a, std::uint8_t slot_b,
                                std::uint32_t a, std::uint32_t b, bool target,
                                bool& improved, std::int32_t& before,
                                std::int32_t& after) {
    if (slot_a >= kTriadSize || slot_b >= kTriadSize)
        return fail("remap slot outside 0..2");
    for (std::size_t i = 0; i < masks.size(); ++i) {
        if (!write_word(kProposalBase + static_cast<std::uint32_t>(i), masks[i]))
            return fail("cannot write general remap masks");
    }
    if (!write_word(kProposalBase + 6, a) ||
        !write_word(kProposalBase + 7, b) ||
        !write_word(kProposalBase + 8, target ? 1u : 0u) ||
        !write_word(kProposalBase + 9, slot_a) ||
        !write_word(kProposalBase + 10, slot_b) ||
        !write_word(kCommandBase, 5)) {
        return fail("cannot write general remap command");
    }
    if (!run_command()) return false;
    improved = (read_word(kResultBase + 0) & 1u) != 0;
    before = static_cast<std::int32_t>(read_word(kResultBase + 1));
    after = static_cast<std::int32_t>(read_word(kResultBase + 2));
    return true;
}

bool RawFieldVM::remap_chart(Universe& universe, HeadArray& heads,
                             std::uint8_t triad_a, std::uint8_t slot_a,
                             std::uint8_t triad_b, std::uint8_t slot_b,
                             std::uint32_t a, std::uint32_t b, bool target,
                             bool& improved, std::int32_t& before,
                             std::int32_t& after) {
    if (triad_a >= kTriadCount || triad_b >= kTriadCount ||
        triad_a == triad_b || slot_a >= kTriadSize || slot_b >= kTriadSize) {
        return fail("invalid general remap triad/slot");
    }
    const auto& table = universe.triad_members();
    const std::size_t base_a = static_cast<std::size_t>(triad_a) * kTriadSize;
    const std::size_t base_b = static_cast<std::size_t>(triad_b) * kTriadSize;
    std::array<std::uint16_t, 6> masks = {
        heads.at(table[base_a + 0]).boolean_mask(),
        heads.at(table[base_a + 1]).boolean_mask(),
        heads.at(table[base_a + 2]).boolean_mask(),
        heads.at(table[base_b + 0]).boolean_mask(),
        heads.at(table[base_b + 1]).boolean_mask(),
        heads.at(table[base_b + 2]).boolean_mask(),
    };
    if (!remap_general(masks, slot_a, slot_b, a, b, target,
                       improved, before, after)) return false;
    if (!improved) {
        bump_triad_credit(universe.triad_credit()[triad_a], -1);
        bump_triad_credit(universe.triad_credit()[triad_b], -1);
        return true;
    }
    const std::uint8_t head_a = table[base_a + slot_a];
    const std::uint8_t head_b = table[base_b + slot_b];
    universe.triad_members()[base_a + slot_a] = head_b;
    universe.triad_members()[base_b + slot_b] = head_a;
    universe.triad_of()[head_b] = triad_a;
    universe.triad_slot()[head_b] = slot_a;
    universe.triad_of()[head_a] = triad_b;
    universe.triad_slot()[head_a] = slot_b;
    universe.triad_votes()[triad_a] = 0;
    universe.triad_votes()[triad_b] = 0;
    bump_triad_credit(universe.triad_credit()[triad_a], 1);
    bump_triad_credit(universe.triad_credit()[triad_b], 1);
    if (!field_vote(universe)) return false;
    if (!coherence(universe)) return false;
    return true;
}

bool RawFieldVM::field_vote(Universe& universe) {
    std::uint16_t accepted = 0;
    bool field_ok = false;
    if (!field_vote(universe.triad_votes(), accepted, field_ok)) return false;
    universe.triad_field_count() = accepted;
    return true;
}

bool RawFieldVM::coherence(Universe& universe) {
    std::array<std::uint16_t, kTriadMemberCount> phases{};
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        for (std::size_t s = 0; s < kTriadSize; ++s) {
            const std::uint8_t h = universe.triad_members()[t * kTriadSize + s];
            phases[t * kTriadSize + s] =
                static_cast<std::uint16_t>(universe.head(h).phase & 0xFFFFu);
        }
    }
    std::int32_t q16 = 0;
    if (!coherence(phases, q16)) return false;
    universe.field_coherence() = q16;
    return true;
}

} // namespace nanlm
