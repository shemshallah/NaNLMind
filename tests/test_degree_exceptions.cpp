#include "test_util.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {
using Truth = std::vector<std::uint8_t>;

Truth anf_transform(const Truth& truth, int n) {
    Truth anf = truth;
    for (int i = 0; i < n; ++i) {
        for (std::uint32_t mask = 0; mask < (1u << n); ++mask) {
            if (mask & (1u << i)) anf[mask] ^= anf[mask ^ (1u << i)];
        }
    }
    return anf;
}

Truth from_anf(Truth anf, int n) {
    for (int i = 0; i < n; ++i) {
        for (std::uint32_t mask = 0; mask < (1u << n); ++mask) {
            if (mask & (1u << i)) anf[mask] ^= anf[mask ^ (1u << i)];
        }
    }
    return anf;
}

double accuracy_for_degree(const Truth& truth, int n, int max_degree) {
    Truth anf = anf_transform(truth, n);
    for (std::uint32_t mask = 0; mask < (1u << n); ++mask) {
        if (__builtin_popcount(mask) > max_degree) anf[mask] = 0;
    }
    const Truth predicted = from_anf(anf, n);
    std::size_t correct = 0;
    for (std::uint32_t mask = 0; mask < (1u << n); ++mask) {
        if (predicted[mask] == truth[mask]) ++correct;
    }
    return static_cast<double>(correct) / (1u << n);
}
} // namespace

int main() {
    constexpr int n = 8;
    for (int depth = 1; depth <= 4; ++depth) {
        Truth truth(1u << n, 0);
        for (std::uint32_t mask = 0; mask < (1u << n); ++mask) {
            const bool bird = (mask & 1u) != 0;
            const std::uint32_t exceptions = (mask >> 1) & ((1u << depth) - 1u);
            truth[mask] = static_cast<std::uint8_t>(bird && exceptions == 0);
        }
        std::array<double, 7> acc{};
        for (int d = 0; d <= 6; ++d) acc[d] = accuracy_for_degree(truth, n, d);
        std::cout << "depth=" << depth << " target_degree=" << depth + 1
                  << " acc=";
        for (int d = 0; d <= 6; ++d) std::cout << acc[d] << ",";
        std::cout << "\n";
        CHECK_EQ(acc[depth + 1], 1.0);
        CHECK(acc[depth] < 1.0);
    }
    return test_done("degree-limited nested exception learner");
}
