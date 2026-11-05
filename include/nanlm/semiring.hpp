// Boolean semiring closure over a 256-node chart.
#pragma once

#include <array>
#include <bitset>
#include <cstdint>

namespace nanlm {

using BoolMatrix = std::array<std::bitset<256>, 256>;

BoolMatrix bool_transpose(const BoolMatrix& a);
BoolMatrix bool_multiply(const BoolMatrix& a, const BoolMatrix& b);
BoolMatrix bool_closure(BoolMatrix a);
bool bool_reachable(const BoolMatrix& closure, std::uint8_t from, std::uint8_t to);

} // namespace nanlm
