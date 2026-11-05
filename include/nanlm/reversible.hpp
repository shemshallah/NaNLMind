// Reversible 16-bit additive/XOR coupling. No activations need to be stored.
#pragma once

#include <cstdint>
#include <utility>

namespace nanlm {

class ReversibleCoupling {
public:
    static std::uint16_t f(std::uint16_t x) {
        x = static_cast<std::uint16_t>(x ^ (x >> 7));
        x = static_cast<std::uint16_t>(x * 0x9E37u);
        return static_cast<std::uint16_t>((x << 5) | (x >> 11));
    }
    static std::pair<std::uint16_t, std::uint16_t> forward(
        std::uint16_t x1, std::uint16_t x2) {
        return {x1, static_cast<std::uint16_t>(x2 ^ f(x1))};
    }
    static std::pair<std::uint16_t, std::uint16_t> inverse(
        std::uint16_t y1, std::uint16_t y2) {
        return {y1, static_cast<std::uint16_t>(y2 ^ f(y1))};
    }
    static std::pair<std::uint16_t, std::uint16_t> forward_layers(
        std::uint16_t x1, std::uint16_t x2, int layers) {
        for (int i = 0; i < layers; ++i) {
            const auto p = forward(x1, x2);
            x1 = p.first;
            x2 = p.second;
        }
        return {x1, x2};
    }
    static std::pair<std::uint16_t, std::uint16_t> inverse_layers(
        std::uint16_t y1, std::uint16_t y2, int layers) {
        for (int i = 0; i < layers; ++i) {
            const auto p = inverse(y1, y2);
            y1 = p.first;
            y2 = p.second;
        }
        return {y1, y2};
    }
};

} // namespace nanlm
