#include "nanlm/semiring.hpp"
#include "nanlm/sparse_exception.hpp"
#include "test_util.hpp"

#include <chrono>
#include <iostream>

using namespace nanlm;

int main() {
    constexpr std::uint32_t kKinds = 256;
    constexpr std::uint32_t kEntities = 20000;
    constexpr std::uint32_t kQueries = 2000;

    BoolMatrix kind_edges;
    for (std::uint32_t k = 0; k + 1 < kKinds; ++k) kind_edges[k].set(k + 1);
    const BoolMatrix closure = bool_closure(kind_edges);

    SparseBitset exception(kEntities);
    for (std::uint32_t e = 0; e < kEntities; e += 7) exception.set(e);

    std::uint32_t matches = 0;
    const auto start = std::chrono::steady_clock::now();
    for (std::uint32_t q = 0; q < kQueries; ++q) {
        const std::uint32_t e = (q * 97u + 3u) % kEntities;
        const std::uint32_t k = (e * 37u + 11u) % kKinds;
        const bool ability1 = (q % 5 == 0);

        bool closure_inherited = false;
        for (std::uint32_t parent = 0; parent < kKinds; ++parent) {
            if (bool_reachable(closure, static_cast<std::uint8_t>(k),
                               static_cast<std::uint8_t>(parent)) &&
                (!ability1 || parent % 10 == 0)) {
                closure_inherited = true;
                break;
            }
        }
        bool chain_inherited = !ability1;
        if (ability1) {
            for (std::uint32_t parent = k; parent < kKinds; ++parent) {
                if (parent % 10 == 0) { chain_inherited = true; break; }
            }
        }
        const bool exception_blocks = exception.test(e) && !ability1;
        const bool got = closure_inherited && !exception_blocks;
        const bool expected = chain_inherited && !exception_blocks;
        if (got == expected) ++matches;
    }
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    std::cout << "sparse-exceptions entities=" << kEntities
              << " exceptions=" << exception.count()
              << " closure_bytes=" << sizeof(closure)
              << " residual_bytes=" << exception.bytes()
              << " queries=" << kQueries << " matches=" << matches
              << " ms=" << ms << "\n";
    CHECK_EQ(exception.count(), (kEntities + 6) / 7);

    SparseBitset peer(kEntities);
    for (std::uint32_t e = 0; e < kEntities; e += 11) peer.set(e);
    SparseBitset merged = exception;
    merged.merge(peer);
    SparseBitset reverse = peer;
    reverse.merge(exception);
    CHECK(merged == reverse);
    for (std::uint32_t e = 0; e < kEntities; e += 37) {
        CHECK_EQ(merged.test(e), exception.test(e) || peer.test(e));
    }

    CHECK_EQ(matches, kQueries);
    CHECK(exception.bytes() < sizeof(closure));
    return test_done("sparse exception residual rows");
}
