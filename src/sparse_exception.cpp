#include "nanlm/sparse_exception.hpp"

namespace nanlm {

std::size_t SparseBitset::count() const {
    std::size_t n = 0;
    for (auto w : words_) n += __builtin_popcountll(w);
    return n;
}

} // namespace nanlm
