#pragma once
// NaN16 PTC — Round 15: Continuity of State
//
//  * Sha256            : self-contained SHA-256 (tamper-evident chain)
//  * full_digest()     : digest of EVERY mutable field of every canonical cell + the cognitive KB
//                        (Topology::state_hash() is blind to rail swaps and to cog_kb_; see tests)
//  * Matrix view       : mirror pairing == transposition on a 256x256 grid.
//                        W[a][b] lives in cell(a,b).state if a<=b else cell(b,a).aux.
//                        diagonal cells are the 256 bit-palindromic fixed points.
//  * Machine           : Topology + integer-only competitive head pool. Deterministic by construction.
//  * Ledger            : one totally ordered, hash-chained transition log.
//                        S(t+1) = T(S(t), E_t); chain_t = H(chain_{t-1} || E_t || delta_t [|| checkpoint])
//                        Identity := genesis + chain head.  Branches are workspaces that commit or abort.

#include "nan16_ptc.hpp"

#include <array>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace nan16 {

using Digest = std::array<std::uint8_t, 32>;

// ---------------------------------------------------------------- SHA-256
class Sha256 {
public:
    Sha256() { reset(); }
    void reset() {
        static const std::uint32_t iv[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
        std::memcpy(h_, iv, sizeof h_);
        len_ = 0; n_ = 0;
    }
    void update(const void* data, std::size_t len) {
        const auto* p = static_cast<const std::uint8_t*>(data);
        len_ += len;
        while (len > 0) {
            std::size_t take = std::min<std::size_t>(64 - n_, len);
            std::memcpy(buf_ + n_, p, take);
            n_ += take; p += take; len -= take;
            if (n_ == 64) { block(buf_); n_ = 0; }
        }
    }
    void update(const std::vector<std::uint8_t>& v) { update(v.data(), v.size()); }
    void update(const Digest& d) { update(d.data(), d.size()); }
    Digest final() {
        std::uint64_t bits = len_ * 8;
        std::uint8_t pad = 0x80;
        update(&pad, 1);
        std::uint8_t z = 0;
        while (n_ != 56) update(&z, 1);
        std::uint8_t lb[8];
        for (int i = 0; i < 8; ++i) lb[i] = static_cast<std::uint8_t>(bits >> (56 - 8 * i));
        update(lb, 8);
        Digest out{};
        for (int i = 0; i < 8; ++i)
            for (int j = 0; j < 4; ++j) out[i * 4 + j] = static_cast<std::uint8_t>(h_[i] >> (24 - 8 * j));
        return out;
    }
    static Digest of(const std::string& s) { Sha256 h; h.update(s.data(), s.size()); return h.final(); }

private:
    static std::uint32_t rotr(std::uint32_t x, int r) { return (x >> r) | (x << (32 - r)); }
    void block(const std::uint8_t* p) {
        static const std::uint32_t K[64] = {
            0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
            0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
            0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
            0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
            0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
            0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
            0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
            0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
        std::uint32_t w[64];
        for (int i = 0; i < 16; ++i)
            w[i] = (std::uint32_t)p[i*4] << 24 | (std::uint32_t)p[i*4+1] << 16 | (std::uint32_t)p[i*4+2] << 8 | p[i*4+3];
        for (int i = 16; i < 64; ++i) {
            std::uint32_t s0 = rotr(w[i-15], 7) ^ rotr(w[i-15], 18) ^ (w[i-15] >> 3);
            std::uint32_t s1 = rotr(w[i-2], 17) ^ rotr(w[i-2], 19) ^ (w[i-2] >> 10);
            w[i] = w[i-16] + s0 + w[i-7] + s1;
        }
        std::uint32_t a=h_[0],b=h_[1],c=h_[2],d=h_[3],e=h_[4],f=h_[5],g=h_[6],hh=h_[7];
        for (int i = 0; i < 64; ++i) {
            std::uint32_t S1 = rotr(e,6) ^ rotr(e,11) ^ rotr(e,25);
            std::uint32_t ch = (e & f) ^ (~e & g);
            std::uint32_t t1 = hh + S1 + ch + K[i] + w[i];
            std::uint32_t S0 = rotr(a,2) ^ rotr(a,13) ^ rotr(a,22);
            std::uint32_t mj = (a & b) ^ (a & c) ^ (b & c);
            std::uint32_t t2 = S0 + mj;
            hh=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2;
        }
        h_[0]+=a; h_[1]+=b; h_[2]+=c; h_[3]+=d; h_[4]+=e; h_[5]+=f; h_[6]+=g; h_[7]+=hh;
    }
    std::uint32_t h_[8];
    std::uint8_t buf_[64];
    std::uint64_t len_;
    std::size_t n_;
};

inline std::string hex(const Digest& d, std::size_t nbytes = 32) {
    static const char* x = "0123456789abcdef";
    std::string s;
    for (std::size_t i = 0; i < nbytes && i < d.size(); ++i) { s += x[d[i] >> 4]; s += x[d[i] & 15]; }
    return s;
}

// ---------------------------------------------------------------- byte IO
struct ByteWriter {
    std::vector<std::uint8_t> b;
    void u8(std::uint8_t v) { b.push_back(v); }
    void u16(std::uint16_t v) { u8(v & 255); u8(v >> 8); }
    void u32(std::uint32_t v) { u16(v & 0xFFFF); u16(static_cast<std::uint16_t>(v >> 16)); }
    void u64(std::uint64_t v) { u32(static_cast<std::uint32_t>(v)); u32(static_cast<std::uint32_t>(v >> 32)); }
    void bytes(const std::vector<std::uint8_t>& v) { u32(static_cast<std::uint32_t>(v.size())); b.insert(b.end(), v.begin(), v.end()); }
    void digest(const Digest& d) { b.insert(b.end(), d.begin(), d.end()); }
};
struct ByteReader {
    const std::vector<std::uint8_t>& b; std::size_t i = 0;
    explicit ByteReader(const std::vector<std::uint8_t>& v) : b(v) {}
    std::uint8_t u8() { return i < b.size() ? b[i++] : 0; }
    std::uint16_t u16() { std::uint16_t lo = u8(); return static_cast<std::uint16_t>(lo | (std::uint16_t)u8() << 8); }
    std::uint32_t u32() { std::uint32_t lo = u16(); return lo | (std::uint32_t)u16() << 16; }
    std::uint64_t u64() { std::uint64_t lo = u32(); return lo | (std::uint64_t)u32() << 32; }
    std::vector<std::uint8_t> bytes() {
        std::uint32_t n = u32();
        std::vector<std::uint8_t> v;
        for (std::uint32_t k = 0; k < n && i < b.size(); ++k) v.push_back(b[i++]);
        return v;
    }
};

// ---------------------------------------------------------------- state digest / checkpoint
// Digest over everything that can differ between two Topology instances.
inline Digest full_digest(const Topology& T) {
    Sha256 h;
    std::uint8_t buf[40];
    for (std::uint32_t a = 0; a < 65536; ++a) {
        auto c = static_cast<std::uint16_t>(a);
        if (canonical_of(c) != c) continue;
        const Cell& x = T.at_canonical(c);
        std::size_t n = 0;
        auto put = [&](std::uint64_t v, int bytes) { for (int k = 0; k < bytes; ++k) buf[n++] = (std::uint8_t)(v >> (8 * k)); };
        put(x.canonical, 2); put(x.mirror, 2); put((std::uint8_t)x.orient, 1); put(x.generation, 8);
        put(x.state, 4); put(x.aux, 4); put(x.signal, 1); put(x.rule_id, 1); put(x.flags, 1);
        h.update(buf, n);
    }
    ByteWriter w;
    w.u64(T.global_tick());
    w.u32(static_cast<std::uint32_t>(T.cog_kb_ref().size()));
    for (const auto& t : T.cog_kb_ref()) { w.u16(t.s); w.u8(t.r); w.u16(t.o); w.u8(t.active); }
    h.update(w.b);
    return h.final();
}

inline std::vector<std::uint8_t> checkpoint_bytes(const Topology& T) {
    ByteWriter w;
    w.u64(T.global_tick());
    for (std::uint32_t a = 0; a < 65536; ++a) {
        auto c = static_cast<std::uint16_t>(a);
        if (canonical_of(c) != c) continue;
        const Cell& x = T.at_canonical(c);
        w.u64(x.generation); w.u32(x.state); w.u32(x.aux);
        w.u8(x.signal); w.u8(x.rule_id); w.u8(x.flags); w.u8((std::uint8_t)x.orient);
    }
    w.u32(static_cast<std::uint32_t>(T.cog_kb_ref().size()));
    for (const auto& t : T.cog_kb_ref()) { w.u16(t.s); w.u8(t.r); w.u16(t.o); w.u8(t.active); }
    return w.b;
}
inline void restore_bytes(Topology& T, const std::vector<std::uint8_t>& bytes) {
    ByteReader r(bytes);
    T.restore_tick(r.u64());
    for (std::uint32_t a = 0; a < 65536; ++a) {
        auto c = static_cast<std::uint16_t>(a);
        if (canonical_of(c) != c) continue;
        Cell& x = T.at_canonical(c);
        x.generation = r.u64(); x.state = r.u32(); x.aux = r.u32();
        x.signal = r.u8(); x.rule_id = r.u8(); x.flags = r.u8();
        x.orient = static_cast<Orientation>(r.u8());
    }
    std::uint32_t nk = r.u32();
    T.cog_kb_mut().clear();
    for (std::uint32_t k = 0; k < nk; ++k) {
        Topology::Triple t; t.s = r.u16(); t.r = r.u8(); t.o = r.u16(); t.active = r.u8() != 0;
        T.cog_kb_mut().push_back(t);
    }
}

// ---------------------------------------------------------------- 256x256 matrix view of the address space
constexpr unsigned kHeads = 256;
inline std::uint8_t reverse8(std::uint8_t x) {
    x = static_cast<std::uint8_t>((x & 0xF0) >> 4 | (x & 0x0F) << 4);
    x = static_cast<std::uint8_t>((x & 0xCC) >> 2 | (x & 0x33) << 2);
    x = static_cast<std::uint8_t>((x & 0xAA) >> 1 | (x & 0x55) << 1);
    return x;
}
inline std::uint16_t addr_of(unsigned a, unsigned b) {
    return static_cast<std::uint16_t>(a << 8 | reverse8(static_cast<std::uint8_t>(b)));
}
// W[a][b] (int32): stored in cell(min,max).state if a<=b, else .aux  (diagonal aux is free: head load)
inline std::uint32_t& mat_ref(Topology& T, unsigned a, unsigned b) {
    if (a <= b) return T.at_canonical(canonical_of(addr_of(a, b))).state;
    return T.at_canonical(canonical_of(addr_of(a, b))).aux;
}
inline std::uint32_t mat_get(const Topology& T, unsigned a, unsigned b) {
    if (a <= b) return T.at_canonical(canonical_of(addr_of(a, b))).state;
    return T.at_canonical(canonical_of(addr_of(a, b))).aux;
}
inline std::uint32_t& head_load_ref(Topology& T, unsigned a) {
    return T.at_canonical(canonical_of(addr_of(a, a))).aux;
}

// ---------------------------------------------------------------- Machine
enum class HeadMode : std::uint8_t { WTA = 0, Inhibit = 1, Frozen = 2, RandomRoute = 3 };
enum class EvType : std::uint8_t { HeadInput = 1, CogAssert = 2, BranchCommit = 3, BranchAbort = 4 };

inline std::uint64_t splitmix(std::uint64_t& s) {
    std::uint64_t z = (s += 0x9E3779B97F4A7C15ull);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
    return z ^ (z >> 31);
}

struct Machine {
    Topology T;
    HeadMode mode = HeadMode::Inhibit;
    std::int64_t penalty = 100'000'000;  // conscience strength (same units as squared distance)
    int lr_num = 3, lr_shift = 6;        // learning rate 3/64
    // derived caches (recomputable from cells; verified by tests)
    std::vector<std::int64_t> norm2 = std::vector<std::int64_t>(kHeads, 0);
    std::uint64_t total_wins = 0;

    Digest genesis() const {
        ByteWriter w;
        for (char c : std::string("NaN16-R15-genesis")) w.u8((std::uint8_t)c);
        w.u8((std::uint8_t)mode); w.u64((std::uint64_t)penalty); w.u8((std::uint8_t)lr_num); w.u8((std::uint8_t)lr_shift);
        Sha256 h; h.update(w.b); return h.final();
    }
    void rebuild_caches() {
        total_wins = 0;
        for (unsigned a = 0; a < kHeads; ++a) {
            std::int64_t n = 0;
            for (unsigned f = 0; f < kHeads; ++f) { auto v = (std::int64_t)(std::int32_t)mat_get(T, a, f); n += v * v; }
            norm2[a] = n;
            total_wins += head_load_ref(T, a);
        }
    }

    struct Applied { Digest delta{}; int winner = -1; };

    // One transition. `prev` is the chain head BEFORE this event; it seeds the per-head tie-break,
    // so the symmetry-breaker is the causal history itself (deterministic, but history-dependent).
    Applied apply(EvType type, const std::vector<std::uint8_t>& payload, const Digest& prev) {
        Applied r;
        ByteReader rd(payload);
        switch (type) {
        case EvType::HeadInput: {
            std::int32_t x[kHeads] = {0};
            std::uint16_t n = rd.u16();
            for (std::uint16_t k = 0; k < n; ++k) { std::uint16_t f = rd.u16(); std::uint16_t v = rd.u16(); x[f & 255] = v; }
            r.winner = head_step(x, prev);
            Sha256 h;
            ByteWriter w; w.u16((std::uint16_t)r.winner); w.u32(head_load_ref(T, (unsigned)r.winner));
            h.update(w.b);
            for (unsigned f = 0; f < kHeads; ++f) { std::uint32_t v = mat_get(T, (unsigned)r.winner, f); h.update(&v, 4); }
            r.delta = h.final();
            break; }
        case EvType::CogAssert: {
            std::uint16_t s = rd.u16(); std::uint8_t rel = rd.u8(); std::uint16_t o = rd.u16();
            T.cog_assert(s, rel, o);
            ByteWriter w; w.u32((std::uint32_t)T.cog_triple_count());
            for (const auto& t : T.cog_kb_ref()) { w.u16(t.s); w.u8(t.r); w.u16(t.o); w.u8(t.active); }
            Sha256 h; h.update(w.b); r.delta = h.final();
            break; }
        case EvType::BranchCommit:
        case EvType::BranchAbort: {
            // payload: list of inner events. Run on this machine (commit) or on a scratch copy (abort).
            Machine scratch = *this;
            Machine& tgt = (type == EvType::BranchCommit) ? *this : scratch;
            std::uint32_t cnt = rd.u32();
            for (std::uint32_t i = 0; i < cnt; ++i) {
                auto et = static_cast<EvType>(rd.u8());
                auto pl = rd.bytes();
                tgt.apply(et, pl, inner_prev(prev, i));
            }
            r.delta = full_digest(tgt.T);   // commit: new state; abort: digest of the DISCARDED counterfactual
            break; }
        }
        return r;
    }
    static Digest inner_prev(const Digest& base, std::uint32_t i) {
        Sha256 h; h.update(base); std::uint8_t b[4] = {(std::uint8_t)i, (std::uint8_t)(i >> 8), (std::uint8_t)(i >> 16), (std::uint8_t)(i >> 24)};
        h.update(b, 4); return h.final();
    }

private:
    int head_step(const std::int32_t* x, const Digest& prev) {
        std::uint64_t seed = 0;
        for (int i = 0; i < 8; ++i) seed |= (std::uint64_t)prev[i] << (8 * i);
        // sparse x
        unsigned nz[kHeads]; unsigned nn = 0;
        for (unsigned f = 0; f < kHeads; ++f) if (x[f]) nz[nn++] = f;
        int best = -1; std::int64_t best_s = 0;
        std::uint64_t sd = seed;
        for (unsigned a = 0; a < kHeads; ++a) {
            std::uint64_t pr = splitmix(sd) & 0xFFFF;      // tie-break priority from history
            std::int64_t s;
            if (mode == HeadMode::RandomRoute) {
                s = -(std::int64_t)pr;                      // input-independent routing
            } else {
                std::int64_t dot = 0;
                for (unsigned k = 0; k < nn; ++k) dot += (std::int64_t)(std::int32_t)mat_get(T, a, nz[k]) * x[nz[k]];
                s = norm2[a] - 2 * dot;                     // squared distance up to a constant
                if (mode == HeadMode::Inhibit) {
                    std::int64_t load = head_load_ref(T, a);
                    s += penalty * load * (std::int64_t)kHeads / (std::int64_t)(kHeads + total_wins);
                }
                s = s * 65536 + (std::int64_t)pr;                          // exact ties -> history-derived priority
            }
            if (best < 0 || s < best_s) { best = (int)a; best_s = s; }
        }
        auto w = (unsigned)best;
        head_load_ref(T, w) += 1; total_wins += 1;
        if (mode != HeadMode::Frozen) {
            std::int64_t n2 = 0;
            for (unsigned f = 0; f < kHeads; ++f) {
                std::int32_t cur = (std::int32_t)mat_get(T, w, f);
                std::int32_t d = x[f] - cur;
                std::int32_t nv = cur + ((d * lr_num) >> lr_shift);
                mat_ref(T, w, f) = (std::uint32_t)nv;
                n2 += (std::int64_t)nv * nv;
            }
            norm2[w] = n2;
        }
        return best;
    }
};

// ---------------------------------------------------------------- Ledger
struct Entry {
    std::uint64_t idx = 0;
    EvType type = EvType::HeadInput;
    std::vector<std::uint8_t> payload;
    Digest delta{};
    Digest chain{};
    bool has_cp = false;
    Digest cp{};
};

struct ReplayReport {
    bool ok = true;
    long first_bad = -1;
    std::string why;
    Digest head{};
    Digest final_state{};
};

class Ledger {
public:
    explicit Ledger(const Machine& m, std::uint64_t checkpoint_every = 500)
        : gen_(m.genesis()), head_(gen_), cp_every_(checkpoint_every) {}

    const Digest& head() const { return head_; }
    const Digest& genesis() const { return gen_; }
    std::size_t size() const { return log_.size(); }
    std::vector<Entry>& entries() { return log_; }
    const std::vector<Entry>& entries() const { return log_; }

    static Digest chain_of(const Digest& prev, const Entry& e) {
        Sha256 h; h.update(prev);
        h.update(&e.type, 1);
        ByteWriter w; w.bytes(e.payload); h.update(w.b);
        h.update(e.delta);
        if (e.has_cp) h.update(e.cp);
        return h.final();
    }

    // Append: apply to the machine, record delta, extend the chain. If `expect` is given it must equal the
    // current head, otherwise the append is REJECTED (a second writer holding a stale head cannot fork history).
    bool append(Machine& m, EvType type, std::vector<std::uint8_t> payload, int* winner = nullptr, const Digest* expect = nullptr) {
        if (expect && *expect != head_) return false;
        Entry e; e.idx = log_.size(); e.type = type; e.payload = std::move(payload);
        auto ap = m.apply(type, e.payload, head_);
        e.delta = ap.delta;
        if (winner) *winner = ap.winner;
        if (cp_every_ && (e.idx + 1) % cp_every_ == 0) { e.has_cp = true; e.cp = full_digest(m.T); }
        e.chain = chain_of(head_, e);
        head_ = e.chain;
        log_.push_back(std::move(e));
        return true;
    }

    // Re-derive everything from genesis on a fresh machine. Detects: edited events, edited deltas,
    // edited chain links, wrong checkpoints. `pinned_head` (optional) detects a self-consistent forgery.
    ReplayReport replay_verify(Machine fresh, const Digest* pinned_head = nullptr) const {
        ReplayReport rep;
        Digest prev = fresh.genesis();
        if (prev != gen_) { rep.ok = false; rep.first_bad = -1; rep.why = "genesis mismatch (different transition function)"; return rep; }
        for (const auto& e : log_) {
            auto ap = fresh.apply(e.type, e.payload, prev);
            if (ap.delta != e.delta) { rep.ok = false; rep.first_bad = (long)e.idx; rep.why = "delta mismatch (event or state diverged)"; return rep; }
            if (e.has_cp && full_digest(fresh.T) != e.cp) { rep.ok = false; rep.first_bad = (long)e.idx; rep.why = "checkpoint mismatch"; return rep; }
            if (chain_of(prev, e) != e.chain) { rep.ok = false; rep.first_bad = (long)e.idx; rep.why = "chain link mismatch"; return rep; }
            prev = e.chain;
        }
        rep.head = prev; rep.final_state = full_digest(fresh.T);
        if (pinned_head && *pinned_head != prev) { rep.ok = false; rep.first_bad = (long)log_.size(); rep.why = "head differs from pinned head (consistent forgery)"; }
        return rep;
    }

    // ---- branches: temporary workspaces that must return to the one history
    struct Workspace {
        Machine m;                       // private copy
        Digest base;                     // chain head it was forked from
        std::vector<std::pair<EvType, std::vector<std::uint8_t>>> events;
        std::uint32_t n = 0;
        int run(EvType t, std::vector<std::uint8_t> pl) {
            auto ap = m.apply(t, pl, Machine::inner_prev(base, n++));
            events.emplace_back(t, std::move(pl));
            return ap.winner;
        }
    };
    Workspace fork(const Machine& m) const { return Workspace{m, head_, {}, 0}; }
    static std::vector<std::uint8_t> pack(const Workspace& ws) {
        ByteWriter w; w.u32((std::uint32_t)ws.events.size());
        for (const auto& ev : ws.events) { w.u8((std::uint8_t)ev.first); w.bytes(ev.second); }
        return w.b;
    }
    // Commit: only if the workspace was forked from the CURRENT head (otherwise it is stale and must be rebased).
    bool commit(Machine& m, const Workspace& ws) {
        if (ws.base != head_) return false;
        return append(m, EvType::BranchCommit, pack(ws));
    }
    // Abort: history records that the counterfactual happened and what it would have produced; state is unchanged.
    bool abort(Machine& m, const Workspace& ws) {
        if (ws.base != head_) return false;
        return append(m, EvType::BranchAbort, pack(ws));
    }

private:
    Digest gen_, head_;
    std::uint64_t cp_every_;
    std::vector<Entry> log_;
};

}  // namespace nan16
