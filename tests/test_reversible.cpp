#include "nanlm/reversible.hpp"
#include "test_util.hpp"

#include <cstdint>

using namespace nanlm;

int main() {
    for (std::uint32_t a = 0; a < 65536; a += 97) {
        for (std::uint32_t b = 0; b < 65536; b += 389) {
            const auto f = ReversibleCoupling::forward_layers(
                static_cast<std::uint16_t>(a), static_cast<std::uint16_t>(b), 7);
            const auto inv = ReversibleCoupling::inverse_layers(f.first, f.second, 7);
            CHECK_EQ(inv.first, static_cast<std::uint16_t>(a));
            CHECK_EQ(inv.second, static_cast<std::uint16_t>(b));
        }
    }
    return test_done("reversible integer coupling");
}
