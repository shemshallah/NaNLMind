// Candidate-only output contract for the ORIGINAL frozen 48M R25 decoder.
// This is a serialization boundary, not an inference model or mutation API.
#pragma once
#include "nanlm/native48m_feedback.hpp"
#include <cmath>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace nanlm {
inline std::string json_quote_48m(std::string_view s){
    std::ostringstream out;
    out<<'"';
    const char* hex="0123456789abcdef";
    for(unsigned char c:s){
        if(c=='"'||c=='\\'){out<<'\\'<<static_cast<char>(c);}
        else if(c<0x20){out<<"\\u00"<<hex[c>>4]<<hex[c&15];}
        else out<<static_cast<char>(c);
    }
    out<<'"';
    return out.str();
}
inline std::string native48m_decoder_candidate_json(
    const Native48MFeedbackReceipt& receipt, const std::string& context,
    const std::string& candidate_word){
    if(!receipt.native_measured||!receipt.meta_available||
       !receipt.candidate_staged||receipt.committed_history_slots==0)
        throw std::logic_error("cannot emit unmeasured, unstaged or future-context candidate");
    if(candidate_word.empty()||candidate_word.size()>128)
        throw std::invalid_argument("canonical candidate word bounds");
    for(unsigned char c:candidate_word){
        if(c>='A'&&c<='Z'||c<0x20)
            throw std::invalid_argument("candidate word must be canonical lowercase");
    }
    if(!std::isfinite(receipt.native_log_weight)||
       std::fabs(receipt.native_log_weight)>8.0f)
        throw std::invalid_argument("invalid native MC0 log weight");
    constexpr const char* base="299a91daf65c8e66fe3489940371d262afef18dd2ef6fef61947ac14c62bb717";
    constexpr const char* overlay="62bf1e5defbb8224d795db16a8e6959cc9aa3d7fed8a63346c4cee205a1bea04";
    std::ostringstream out;
    out<<std::setprecision(9);
    out<<"{\"schema\":\"nanlm.48m-native-feedback/1\"";
    out<<",\"base_sha256\":\""<<base<<"\",\"overlay_sha256\":\""<<overlay<<"\"";
    out<<",\"context\":"<<json_quote_48m(context);
    out<<",\"native_log_weights\":{"<<json_quote_48m(candidate_word)<<":"
       <<receipt.native_log_weight<<"}";
    out<<",\"query_words\":["<<json_quote_48m(candidate_word)<<"]";
    out<<",\"native_evidence\":{\"proposer\":"<<unsigned(receipt.proposer)
       <<",\"h\":"<<unsigned(receipt.h)<<",\"a\":"<<unsigned(receipt.a)
       <<",\"b\":"<<unsigned(receipt.b)
       <<",\"phase_shard\":"<<receipt.phase_shard
       <<",\"native_observed_contexts\":"<<receipt.native_observed_contexts
       <<",\"committed_history_slots\":"<<receipt.committed_history_slots
       <<",\"accepted_triads\":"<<receipt.accepted_triads
       <<",\"field_accepted\":"<<(receipt.field_accepted?"true":"false")
       <<",\"has_admitted_faces\":"<<(receipt.has_admitted_faces?"true":"false")
       <<",\"meta_available\":true,\"candidate_staged\":true"
       <<",\"automatic_promotion\":false}}";
    return out.str();
}
} // namespace nanlm
