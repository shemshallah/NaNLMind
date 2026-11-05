// Sparse per-entity exception residual over a dense kind-inheritance closure.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace nanlm {

class SparseBitset {
public:
    explicit SparseBitset(std::size_t bits = 0)
        : bits_(bits), words_((bits + 63) / 64, 0) {}
    void set(std::size_t i) { words_[i >> 6] |= (1ull << (i & 63)); }
    void reset(std::size_t i) { words_[i >> 6] &= ~(1ull << (i & 63)); }
    bool test(std::size_t i) const { return (words_[i >> 6] >> (i & 63)) & 1ull; }
    std::size_t size() const { return bits_; }
    std::size_t bytes() const { return words_.size() * sizeof(std::uint64_t); }
    std::size_t count() const;

private:
    std::size_t bits_;
    std::vector<std::uint64_t> words_;
};

} // namespace nanlm
