#include "nanlm/semiring.hpp"
#include "test_util.hpp"

#include <chrono>
#include <cstdint>
#include <iostream>
#include <string>

using namespace nanlm;

int main() {
    constexpr std::uint32_t kKinds = 256;
    constexpr std::uint32_t kEntities = 20000;
    constexpr std::uint32_t kQueries = 2000;

    BoolMatrix edges;
    for (std::uint32_t k = 0; k + 1 < kKinds; ++k) edges[k].set(k + 1);
    const BoolMatrix closure = bool_closure(edges);

    std::uint32_t matches = 0;
    std::uint32_t true_cases = 0;
    const auto start = std::chrono::steady_clock::now();
    for (std::uint32_t q = 0; q < kQueries; ++q) {
        const std::uint32_t e = (q * 97u + 3u) % kEntities;
        const std::uint32_t k = (e * 37u + 11u) % kKinds;
        const bool ability1 = (q % 5 == 0);

        bool closure_can = false;
        for (std::uint32_t parent = 0; parent < kKinds; ++parent) {
            if (bool_reachable(closure, static_cast<std::uint8_t>(k),
                               static_cast<std::uint8_t>(parent)) &&
                (!ability1 || parent % 10 == 0)) {
                closure_can = true;
                break;
            }
        }
        bool symbolic_can = !ability1;
        if (ability1) {
            for (std::uint32_t parent = k; parent < kKinds; ++parent) {
                if (parent % 10 == 0) { symbolic_can = true; break; }
            }
        }
        const bool exception = (e % 7 == 0) && !ability1;
        const bool got = closure_can && !exception;
        const bool expected = symbolic_can && !exception;
        if (got == expected) ++matches;
        if (expected) ++true_cases;
    }
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    std::cout << "semiring-inheritance entities=" << kEntities
              << " kinds=" << kKinds << " queries=" << kQueries
              << " matches=" << matches << " true_cases=" << true_cases
              << " ms=" << ms << "\n";
    CHECK_EQ(matches, kQueries);
    // The closure is reflexive-transitive and the chain reaches its end.
    CHECK(bool_reachable(closure, 0, 255));
    CHECK(bool_reachable(closure, 42, 255));
    CHECK(!bool_reachable(closure, 255, 0));
    CHECK(closure[0].test(0));
    return test_done("semiring inheritance closure over 256 kinds");
}
