#include "nanlm/hypervector.hpp"

#include <algorithm>

namespace nanlm {
namespace {
std::uint64_t splitmix(std::uint64_t x) {
    x += 0x9E3779B97F4A7C15ull;
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ull;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBull;
    return x ^ (x >> 31);
}
bool bit_of(const Hyper& h, unsigned i) {
    return ((h[i / 64] >> (i % 64)) & 1ull) != 0;
}
void set_bit(Hyper& h, unsigned i, bool value) {
    if (value) h[i / 64] |= (1ull << (i % 64));
    else h[i / 64] &= ~(1ull << (i % 64));
}
} // namespace

Hyper hyper_from_hash(std::uint64_t seed) {
    Hyper h{};
    for (std::size_t i = 0; i < h.size(); ++i) h[i] = splitmix(seed + i * 0x9E3779B97F4A7C15ull);
    return h;
}

Hyper hyper_bind(const Hyper& a, const Hyper& b) {
    Hyper h{};
    for (std::size_t i = 0; i < h.size(); ++i) h[i] = a[i] ^ b[i];
    return h;
}

Hyper hyper_permute(const Hyper& a, unsigned shift) {
    Hyper out{};
    shift %= kHyperBits;
    for (unsigned i = 0; i < kHyperBits; ++i) set_bit(out, (i + shift) % kHyperBits, bit_of(a, i));
    return out;
}

unsigned hyper_hamming(const Hyper& a, const Hyper& b) {
    unsigned n = 0;
    for (std::size_t i = 0; i < a.size(); ++i) n += __builtin_popcountll(a[i] ^ b[i]);
    return n;
}

void HyperBundle::add(const Hyper& h, std::int32_t weight) {
    for (unsigned i = 0; i < kHyperBits; ++i) {
        if (bit_of(h, i)) counters_[i] += weight;
    }
}

void HyperBundle::merge(const HyperBundle& other) {
    for (std::size_t i = 0; i < counters_.size(); ++i) counters_[i] += other.counters_[i];
}

Hyper HyperBundle::threshold() const {
    Hyper h{};
    for (unsigned i = 0; i < kHyperBits; ++i) set_bit(h, i, counters_[i] > 0);
    return h;
}

Hyper HyperTripleStore::code(const std::string& item) const {
    const auto it = codes_.find(item);
    if (it != codes_.end()) return it->second;
    std::uint64_t seed = 1469598103934665603ull;
    for (unsigned char c : item) { seed ^= c; seed *= 1099511628211ull; }
    const Hyper h = hyper_from_hash(seed);
    codes_[item] = h;
    return h;
}

void HyperTripleStore::add(const std::string& subject, const std::string& relation,
                           const std::string& object) {
    const Hyper h = hyper_bind(code(subject), hyper_bind(code(relation), code(object)));
    bundle_.add(h);
    ++triples_;
}

std::string HyperTripleStore::query(const std::string& subject,
                                    const std::string& relation) const {
    const Hyper q = hyper_bind(bundle_.threshold(),
                               hyper_bind(code(subject), code(relation)));
    std::string best;
    unsigned best_d = kHyperBits + 1;
    for (const auto& kv : codes_) {
        const unsigned d = hyper_hamming(q, kv.second);
        if (d < best_d) { best_d = d; best = kv.first; }
    }
    return best;
}

void HyperTripleStore::merge(const HyperTripleStore& other) {
    bundle_.merge(other.bundle_);
    for (const auto& kv : other.codes_) codes_.insert(kv);
    triples_ += other.triples_;
}

} // namespace nanlm
