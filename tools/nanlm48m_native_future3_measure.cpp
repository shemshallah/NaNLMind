// Original frozen 48M three-word decoder's *native NaN16* causal observer.
// Stateless process boundary: all tokenization/phasor/MC0/Poincare math runs
// through the SAME NaN0S field-driver guest. No host embeddings or training.
// The caller supplies observed text plus only earlier words predicted by
// the frozen R25 decoder. No source future target exists in these arguments.
// This tool is measurement-only: it emits NO synthetic trained logit delta,
// Hodge faces, fake field votes, promoted weights or surrogate decoder.
//
// Usage: nanlm48m-native-future3-measure
//        <original-observed-context> <generated-prefix-or--> <count=0..2>
// JSON receipt written to stdout, rejected inputs cause nonzero process exit.
#include "nanlm/raw_field.hpp"
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
std::vector<std::uint32_t> guest_tokenize(
    nanlm::RawFieldVM& vm,const std::string& text){
    if(text.empty()||text.size()>0xFF00u)
        throw std::invalid_argument("NaN16 tokenizer source byte bounds");
    std::vector<std::uint32_t> words,subwords,meta;
    std::size_t nwords=0,nsubwords=0;
    if(!vm.tokenize(text,4096,words,subwords,meta,nwords,nsubwords))
        throw std::runtime_error("NaN16 tokenizer rejected source: "+vm.error());
    if(words.empty()||words.size()!=nwords)
        throw std::runtime_error("guest returned no valid word IDs");
    for(const auto word:words)
        if(word==0u)throw std::runtime_error("guest produced forbidden zero word ID");
    return words;
}
}
int main(int argc,char** argv){
    if(argc!=4){
        std::cerr<<"Usage: nanlm48m-native-future3-measure"
                 <<" <observed-context> <generated-prefix-or--> <count=0..2>\n";
        return 2;
    }
    try{
        const std::string observed=argv[1],generated=argv[2],count_str=argv[3];
        if(count_str.size()!=1||count_str[0]<'0'||count_str[0]>'2')
            throw std::invalid_argument("generated count must be 0,1,2");
        const unsigned count=static_cast<unsigned>(count_str[0]-'0');
        if((count==0 && generated!="-") || (count!=0 && generated=="-"))
            throw std::invalid_argument("generated prefix/count mismatch");
        nanlm::RawFieldVM vm("build/field_driver.nan");
        if(!vm.ready())throw std::runtime_error("NaN16 guest unavailable: "+vm.error());
        const auto observed_ids=guest_tokenize(vm,observed);
        std::array<std::uint32_t,3> generated_ids{};
        if(count!=0){
            const auto actual=guest_tokenize(vm,generated);
            if(actual.size()!=count)
                throw std::invalid_argument("generated prefix token count mismatch");
            for(unsigned i=0;i<count;++i)generated_ids[i]=actual[i];
        }
        nanlm::NativeContext6Receipt receipt{};
        // The current verified process snapshot is one source epoch, not
        // a persisted transaction or permission to modify the tensor.
        if(!vm.native_future3_causal_attention(
                observed_ids,generated_ids,static_cast<std::uint8_t>(count),
                0,0,receipt))
            throw std::runtime_error("NaN16 future3 observer failed: "+vm.error());
        if(!receipt.accepted || receipt.horizon!=count+1 ||
           receipt.now_head!=255 || receipt.task!=0 || receipt.mask==0 ||
           (receipt.mask&0x38u)!=0)
            throw std::runtime_error("NaN16 future3 guest rejected context");
        std::cout<<std::setprecision(9)
            <<"{\"schema\":\"nanlm.native-future3-measure/1\","
            <<"\"horizon\":"<<unsigned(receipt.horizon)<<','
            <<"\"observed_word_count\":"<<observed_ids.size()<<','
            <<"\"generated_word_count\":"<<count<<','
            <<"\"valid_past_count\":"<<unsigned(receipt.valid_count)<<','
            <<"\"past_mask\":"<<unsigned(receipt.mask)<<','
            <<"\"now_void_head\":"<<unsigned(receipt.now_head)<<','
            <<"\"anchor_word_id\":"<<receipt.observed_anchor<<','
            <<"\"poincare_x\":"<<receipt.poincare_x<<','
            <<"\"poincare_y\":"<<receipt.poincare_y<<','
            <<"\"poincare_radius\":"<<receipt.radius<<','
            <<"\"poincare_depth\":"<<receipt.radial_distance<<','
            <<"\"source_future_read\":false,"
            <<"\"guest_measured\":true,"
            <<"\"candidate_delta_available\":false,"
            <<"\"has_admitted_hodge_faces\":false,"
            <<"\"tensor_promoted\":false}\n";
        return 0;
    }catch(const std::exception& exc){
        std::cerr<<"native_future3_observation_error: "<<exc.what()<<"\n";
        return 1;
    }
}
