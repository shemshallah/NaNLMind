#include "nanlm/ntt257.hpp"

#include <algorithm>

namespace nanlm {
namespace {
std::int32_t mod_pow(std::int32_t base, std::int32_t exp) {
    std::int64_t result = 1;
    std::int64_t b = base;
    while (exp > 0) {
        if (exp & 1) result = (result * b) % kNttPrime;
        b = (b * b) % kNttPrime;
        exp >>= 1;
    }
    return static_cast<std::int32_t>(result);
}
std::int32_t inverse_root() { return mod_pow(kNttRoot, kNttPrime - 2); }
} // namespace

void ntt257(std::vector<std::int32_t>& a, bool inverse) {
    if (a.size() != kNttSize) a.resize(kNttSize, 0);
    for (std::size_t i = 0; i < a.size(); ++i) a[i] = ((a[i] % kNttPrime) + kNttPrime) % kNttPrime;
    for (std::int32_t i = 1, j = 0; i < kNttSize; ++i) {
        std::int32_t bit = kNttSize >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(a[i], a[j]);
    }
    for (std::int32_t len = 2; len <= kNttSize; len <<= 1) {
        std::int32_t wlen = mod_pow(inverse ? inverse_root() : kNttRoot,
                                    kNttSize / len);
        for (std::int32_t i = 0; i < kNttSize; i += len) {
            std::int64_t w = 1;
            for (std::int32_t j = 0; j < len / 2; ++j) {
                const std::int32_t u = a[i + j];
                const std::int32_t v = static_cast<std::int32_t>(
                    (static_cast<std::int64_t>(a[i + j + len / 2]) * w) % kNttPrime);
                a[i + j] = static_cast<std::int32_t>((u + v) % kNttPrime);
                a[i + j + len / 2] = static_cast<std::int32_t>(
                    (u - v + kNttPrime) % kNttPrime);
                w = (w * wlen) % kNttPrime;
            }
        }
    }
    if (inverse) {
        const std::int32_t inv_n = mod_pow(kNttSize, kNttPrime - 2);
        for (auto& x : a) x = static_cast<std::int32_t>(
            (static_cast<std::int64_t>(x) * inv_n) % kNttPrime);
    }
}

std::vector<std::int32_t> cyclic_convolution_ntt(
    const std::vector<std::int32_t>& a, const std::vector<std::int32_t>& b) {
    std::vector<std::int32_t> fa = a, fb = b;
    fa.resize(kNttSize, 0);
    fb.resize(kNttSize, 0);
    ntt257(fa, false);
    ntt257(fb, false);
    for (int i = 0; i < kNttSize; ++i) {
        fa[i] = static_cast<std::int32_t>(
            (static_cast<std::int64_t>(fa[i]) * fb[i]) % kNttPrime);
    }
    ntt257(fa, true);
    return fa;
}

std::vector<std::int32_t> cyclic_convolution_naive(
    const std::vector<std::int32_t>& a, const std::vector<std::int32_t>& b) {
    std::vector<std::int32_t> out(kNttSize, 0);
    for (int k = 0; k < kNttSize; ++k) {
        std::int64_t sum = 0;
        for (int i = 0; i < kNttSize; ++i) {
            sum += static_cast<std::int64_t>(a[i]) * b[(k - i + kNttSize) % kNttSize];
        }
        out[k] = static_cast<std::int32_t>(sum % kNttPrime);
    }
    return out;
}

} // namespace nanlm
