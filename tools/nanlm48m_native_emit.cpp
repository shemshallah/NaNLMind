// Local native corpus-window -> 48M decoder candidate receipt.
// Reads two REAL text windows, uses the NaN16 guest tokenizer and mathematical
// kernels, and emits a candidate-only JSON accepted by decoder48m_candidate.py.
// No chart, model, or tensor generation is promoted by this command.
#include "nanlm/native48m_feedback_json.hpp"
#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

static std::string read_text(const std::string& path){
    std::ifstream in(path,std::ios::binary);
    if(!in)throw std::runtime_error("cannot read source window: "+path);
    return {std::istreambuf_iterator<char>(in),std::istreambuf_iterator<char>()};
}
static std::vector<std::uint32_t> guest_words(
    nanlm::RawFieldVM& vm,const std::string& source){
    std::vector<std::uint32_t> words,subwords,meta;
    std::size_t word_count=0,subword_count=0;
    if(!vm.tokenize(source,64,words,subwords,meta,word_count,subword_count))
        throw std::runtime_error("guest tokenize: "+vm.error());
    if(words.empty())throw std::runtime_error("guest tokenizer produced no words");
    return words;
}
int main(int argc,char**argv){
    if(argc!=6){
        std::cerr<<"Usage: nanlm48m-native-emit <previous-window.txt> <current-window.txt> <48m-context> <candidate-word> <candidate.json>\n";
        return 2;
    }
    try{
        const auto previous=read_text(argv[1]),current=read_text(argv[2]);
        if(previous.empty()||previous.size()>64||current.empty()||current.size()>64)
            throw std::invalid_argument("each observed source window must be 1..64 bytes");
        nanlm::RawFieldVM vm("build/field_driver.nan");
        if(!vm.ready())throw std::runtime_error("native guest unavailable: "+vm.error());
        nanlm::DualTensor256Arena arena(
            "299a91daf65c8e66fe3489940371d262afef18dd2ef6fef61947ac14c62bb717",
            "62bf1e5defbb8224d795db16a8e6959cc9aa3d7fed8a63346c4cee205a1bea04");
        // Locally authorized test operator only. This does not confer any
        // authority in the production NANNET remote write path.
        arena.set_writer_permission(3,true);
        arena.begin_candidate();
        nanlm::Native48MFeedbackBridge bridge(vm,arena);
        bridge.reset_native_session();
        std::array<float,32640> no_external_pair_flow{};
        const auto past_words=guest_words(vm,previous);
        const auto past=bridge.measure_and_stage(
            {previous.begin(),previous.end()},past_words,3,7,2,3,
            no_external_pair_flow,{});
        bridge.commit_context(past);
        const auto current_words=guest_words(vm,current);
        const auto receipt=bridge.measure_and_stage(
            {current.begin(),current.end()},current_words,3,7,2,3,
            no_external_pair_flow,{});
        const std::string output=nanlm::native48m_decoder_candidate_json(
            receipt,argv[3],argv[4]);
        std::ofstream out(argv[5],std::ios::binary|std::ios::trunc);
        if(!out)throw std::runtime_error("cannot open candidate receipt for writing");
        out<<output<<'\n';
        if(!out)throw std::runtime_error("candidate receipt write failed");
        // No fitted development NLL, no admissible Hodge faces: never promote.
        arena.abort_candidate();
        std::cout<<"native_48m_candidate_only=yes"
                 <<" observed_contexts="<<receipt.native_observed_contexts
                 <<" committed_past_slots="<<receipt.committed_history_slots
                 <<" accepted_triads="<<receipt.accepted_triads
                 <<" meta_available="<<receipt.meta_available
                 <<" decoder_receipt="<<argv[5]<<"\n";
        return 0;
    }catch(const std::exception& e){
        std::cerr<<"native_48m_candidate_error: "<<e.what()<<"\n";
        return 1;
    }
}
