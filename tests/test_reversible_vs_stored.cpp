#include "nanlm/reversible.hpp"
#include "test_util.hpp"

#include <cstdint>
#include <utility>
#include <vector>

using namespace nanlm;

int main() {
    constexpr int kLayers = 256;
    const std::uint16_t x1 = 0x1234;
    const std::uint16_t x2 = 0xABCD;

    // Stored-activation baseline: save every intermediate pair.
    std::vector<std::pair<std::uint16_t, std::uint16_t>> saved;
    saved.reserve(kLayers + 1);
    saved.emplace_back(x1, x2);
    auto p = std::make_pair(x1, x2);
    for (int i = 0; i < kLayers; ++i) {
        p = ReversibleCoupling::forward(p.first, p.second);
        saved.push_back(p);
    }
    std::pair<std::uint16_t, std::uint16_t> stored = p;
    for (int i = kLayers - 1; i >= 0; --i) {
        stored = ReversibleCoupling::inverse(stored.first, stored.second);
    }
    CHECK(stored.first == x1 && stored.second == x2);

    // Reversible path: only the final pair is retained.
    const auto reversible = ReversibleCoupling::forward_layers(x1, x2, kLayers);
    const auto restored = ReversibleCoupling::inverse_layers(
        reversible.first, reversible.second, kLayers);
    CHECK(restored.first == x1 && restored.second == x2);

    const std::size_t stored_bytes = saved.size() * sizeof(saved[0]);
    const std::size_t reversible_bytes = sizeof(reversible);
    CHECK(stored_bytes > reversible_bytes);
    return test_done("reversible coupling vs stored activations");
}
