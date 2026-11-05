// XOR-bound hypervector triples. Bind is XOR; bundle is integer counters;
// cleanup is nearest Hamming code. Merge is addition of bundles.
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <unordered_map>

namespace nanlm {

inline constexpr unsigned kHyperBits = 4096;
using Hyper = std::array<std::uint64_t, kHyperBits / 64>;

Hyper hyper_from_hash(std::uint64_t seed);
Hyper hyper_bind(const Hyper& a, const Hyper& b);
Hyper hyper_permute(const Hyper& a, unsigned shift);
unsigned hyper_hamming(const Hyper& a, const Hyper& b);

class HyperBundle {
public:
    void add(const Hyper& h, std::int32_t weight = 1);
    void merge(const HyperBundle& other);
    Hyper threshold() const;
    const std::array<std::int32_t, kHyperBits>& counters() const { return counters_; }

private:
    std::array<std::int32_t, kHyperBits> counters_{};
};

class HyperTripleStore {
public:
    void add(const std::string& subject, const std::string& relation,
             const std::string& object);
    std::string query(const std::string& subject, const std::string& relation) const;
    std::size_t triples() const { return triples_; }
    void merge(const HyperTripleStore& other);

private:
    Hyper code(const std::string& item) const;
    mutable std::unordered_map<std::string, Hyper> codes_;
    HyperBundle bundle_;
    std::size_t triples_ = 0;
};

} // namespace nanlm
