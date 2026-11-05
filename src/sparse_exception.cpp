#include "nanlm/sparse_exception.hpp"

namespace nanlm {

void SparseBitset::merge(const SparseBitset& other) {
    const std::size_t n = std::min(words_.size(), other.words_.size());
    for (std::size_t i = 0; i < n; ++i) words_[i] |= other.words_[i];
}

std::size_t SparseBitset::count() const {
    std::size_t n = 0;
    for (auto w : words_) n += __builtin_popcountll(w);
    return n;
}

} // namespace nanlm
