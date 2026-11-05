// Exact 256-point NTT over the Fermat prime 257 (multiplicative group order 256).
#pragma once

#include <cstdint>
#include <vector>

namespace nanlm {
inline constexpr int kNttPrime = 257;
inline constexpr int kNttSize = 256;
inline constexpr int kNttRoot = 3;

void ntt257(std::vector<std::int32_t>& a, bool inverse);
std::vector<std::int32_t> cyclic_convolution_ntt(const std::vector<std::int32_t>& a,
                                                 const std::vector<std::int32_t>& b);
std::vector<std::int32_t> cyclic_convolution_naive(const std::vector<std::int32_t>& a,
                                                   const std::vector<std::int32_t>& b);
} // namespace nanlm
