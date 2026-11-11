// Full 128MiB external storage for the existing NaN16 256^3 dual mirror mapper.
// NaN16 computes all vector/model arithmetic; this host stores admitted guest values.
// It never mutates the original frozen 48M language decoder.
#pragma once
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace nanlm {
struct TensorMetaGate {
    double baseline_nll=std::numeric_limits<double>::quiet_NaN();
    double candidate_nll=std::numeric_limits<double>::quiet_NaN();
    std::array<std::uint8_t,85> triad_votes{};
    bool global_approved=false, meta_approved=false;
    std::string base_sha256, overlay_sha256;
};
struct TensorGateResult {
    bool promoted=false;
    std::uint32_t accepted_triads=0;
    std::uint64_t generation=0;
    std::size_t candidate_writes=0;
    double nll_improvement=0.0;
};
class DualTensor256Arena {
public:
    static constexpr std::size_t kSide=256;
    static constexpr std::size_t kBankFloats=kSide*kSide*kSide;
    static constexpr std::size_t kBankBytes=kBankFloats*sizeof(float);
    static constexpr std::size_t kTotalBytes=2*kBankBytes;
    static_assert(kBankBytes==67108864u && kTotalBytes==134217728u);
    explicit DualTensor256Arena(std::string base_sha256,std::string overlay_sha256)
      : active_(kBankFloats,0.0f),candidate_(kBankFloats,0.0f),
        base_sha256_(std::move(base_sha256)),overlay_sha256_(std::move(overlay_sha256)) {
        if(base_sha256_.size()!=64 || overlay_sha256_.size()!=64)
            throw std::invalid_argument("frozen 48M SHA-256 pair required");
        authority_.fill(false);
    }
    // Identical canonical pair and orientation layout to the NaN16 resolver.
    static std::size_t index(unsigned h,unsigned a,unsigned b) {
        if(h>=255 || a>=255 || b>=255)throw std::out_of_range("void 255");
        const std::size_t base=std::size_t(h)<<16;
        if(a==b)return base+a;
        const unsigned lo=a<b?a:b,hi=a<b?b:a;
        const std::size_t pair=(std::size_t(lo)*(511u-lo))/2u+hi-lo-1u;
        return base+256u+2u*pair+(a>b?1u:0u);
    }
    static std::size_t byte_offset(unsigned h,unsigned a,unsigned b,unsigned bank) {
        if(bank>1)throw std::out_of_range("bank");
        return bank*kBankBytes+4u*index(h,a,b);
    }
    // Physical head identity grants no implicit authority (including head 0).
    void set_writer_permission(unsigned h,bool granted) {
        if(h>=255)throw std::out_of_range("void writer");
        authority_[h]=granted;
    }
    // A coordinator may explicitly authorize ALL 255 trainable heads
    // to propose candidate writes for the current epoch. This does not
    // grant direct active-bank writes or authorize void255. Revocable.
    void set_all_candidate_writer_permissions(bool granted) noexcept {
        authority_.fill(granted);
    }
    bool candidate_writer_allowed(unsigned h) const {
        if(h>=255)throw std::out_of_range("void writer");
        return authority_[h];
    }
    float active(unsigned h,unsigned a,unsigned b)const {
        return active_.at(index(h,a,b));
    }
    float candidate(unsigned h,unsigned a,unsigned b)const {
        if(!open_)throw std::logic_error("candidate closed");
        return candidate_.at(index(h,a,b));
    }
    void begin_candidate() {
        if(open_)throw std::logic_error("candidate already open");
        candidate_=active_; // 64MiB complete copy; no sparse substitute.
        writes_=0;open_=true;
    }
    // Native guest calculates the VALUE. Controller enforces admission only.
    void stage_native_value(unsigned proposer,unsigned h,unsigned a,unsigned b,float native_value) {
        if(!open_)throw std::logic_error("no candidate");
        if(proposer>=255 || !authority_[proposer])
            throw std::logic_error("unauthorized candidate writer");
        if(!std::isfinite(native_value))throw std::invalid_argument("nonfinite value");
        candidate_.at(index(h,a,b))=native_value;
        ++writes_;
    }
    // Single-writer, externally leased transaction; not a concurrent storage API.
    TensorGateResult decide(const TensorMetaGate& gate) {
        if(!open_)throw std::logic_error("no candidate");
        TensorGateResult result{};
        result.generation=generation_;result.candidate_writes=writes_;
        for(auto bits:gate.triad_votes){
            if(bits>7){open_=false;return result;}
            const unsigned n=(bits&1u)+((bits>>1u)&1u)+((bits>>2u)&1u);
            if(n>=2u)++result.accepted_triads;
        }
        if(std::isfinite(gate.baseline_nll)&&std::isfinite(gate.candidate_nll))
            result.nll_improvement=gate.baseline_nll-gate.candidate_nll;
        const bool accepted=gate.base_sha256==base_sha256_
            && gate.overlay_sha256==overlay_sha256_
            && std::isfinite(gate.baseline_nll)&&std::isfinite(gate.candidate_nll)
            && result.nll_improvement>0.0 && result.accepted_triads>=43
            && gate.global_approved && gate.meta_approved && writes_>0;
        if(accepted){
            active_.swap(candidate_);
            result.promoted=true;result.generation=++generation_;
        }
        open_=false;writes_=0;
        return result;
    }
    void abort_candidate()noexcept{open_=false;writes_=0;}
    bool candidate_open()const noexcept{return open_;}
    std::uint64_t generation()const noexcept{return generation_;}
private:
    std::vector<float> active_,candidate_;
    std::array<bool,255> authority_{};
    std::string base_sha256_,overlay_sha256_;
    std::uint64_t generation_=0;
    std::size_t writes_=0;
    bool open_=false;
};
} // namespace nanlm
