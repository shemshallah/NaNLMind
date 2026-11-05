#include "nanlm/ntt257.hpp"
#include "test_util.hpp"

#include <fstream>
#include <iterator>
#include <vector>

using namespace nanlm;

int main() {
    std::ifstream f("data/alice_excerpt.txt", std::ios::binary);
    CHECK(f.good());
    const std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                         std::istreambuf_iterator<char>());
    if (data.size() < kNttSize * 2) return test_done("NTT sequence (skipped)");

    for (int window = 0; window < 8; ++window) {
        const std::size_t base = static_cast<std::size_t>(window) * 733u;
        std::vector<std::int32_t> a(kNttSize), b(kNttSize);
        for (int i = 0; i < kNttSize; ++i) {
            a[i] = data[(base + i) % data.size()];
            b[i] = data[(base + 97u + i * 3u) % data.size()];
        }
        const auto ntt = cyclic_correlation_ntt(a, b);
        const auto naive = cyclic_correlation_naive(a, b);
        for (int i = 0; i < kNttSize; ++i) CHECK_EQ(ntt[i], naive[i]);
    }
    return test_done("NTT cyclic correlation on Alice windows");
}
