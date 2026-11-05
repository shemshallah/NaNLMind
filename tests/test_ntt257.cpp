#include "nanlm/ntt257.hpp"
#include "test_util.hpp"

#include <vector>

using namespace nanlm;

int main() {
    std::vector<std::int32_t> a(kNttSize), b(kNttSize);
    for (int i = 0; i < kNttSize; ++i) {
        a[i] = (i * 17 + 3) % kNttPrime;
        b[i] = (i * 29 + 7) % kNttPrime;
    }
    std::vector<std::int32_t> fa = a;
    ntt257(fa, false);
    ntt257(fa, true);
    for (int i = 0; i < kNttSize; ++i) CHECK_EQ(fa[i], a[i]);

    const auto ntt = cyclic_convolution_ntt(a, b);
    const auto naive = cyclic_convolution_naive(a, b);
    for (int i = 0; i < kNttSize; ++i) CHECK_EQ(ntt[i], naive[i]);
    return test_done("exact 256-point NTT over F257");
}
