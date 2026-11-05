#include "nanlm/semiring.hpp"

namespace nanlm {

BoolMatrix bool_transpose(const BoolMatrix& a) {
    BoolMatrix out;
    for (std::uint32_t i = 0; i < 256; ++i) {
        for (std::uint32_t j = 0; j < 256; ++j) {
            if (a[i].test(j)) out[j].set(i);
        }
    }
    return out;
}

BoolMatrix bool_multiply(const BoolMatrix& a, const BoolMatrix& b) {
    BoolMatrix out;
    for (std::uint32_t i = 0; i < 256; ++i) {
        for (std::uint32_t k = 0; k < 256; ++k) {
            if (a[i].test(k)) out[i] |= b[k];
        }
    }
    return out;
}

BoolMatrix bool_closure(BoolMatrix a) {
    // Reflexive-transitive closure via Warshall.
    for (std::uint32_t k = 0; k < 256; ++k) {
        for (std::uint32_t i = 0; i < 256; ++i) {
            if (a[i].test(k)) a[i] |= a[k];
        }
    }
    return a;
}

bool bool_reachable(const BoolMatrix& closure, std::uint8_t from, std::uint8_t to) {
    return closure[from].test(to);
}

} // namespace nanlm
