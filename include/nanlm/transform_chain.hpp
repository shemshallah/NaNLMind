// Four-NaN transform chain. The four legal NaN types select the four phases of
// the I -> B -> BR -> R oscillator; every transform has an exact inverse.
#pragma once

#include "nanlm/nan16.hpp"

#include <cstdint>

namespace nanlm {

class TransformChain {
public:
    static constexpr std::uint8_t phase_for(NanType type) {
        switch (type) {
            case NanType::QuietPositive: return 0;    // I  / quiet future
            case NanType::SignalPositive: return 1;   // B  / signaling future
            case NanType::QuietNegative: return 2;    // BR / quiet past
            case NanType::SignalNegative: return 3;   // R  / signaling past
        }
        return 0;
    }
    static constexpr std::uint16_t forward_phase(std::uint16_t address,
                                                  std::uint8_t phase) {
        return apply_transform_phase(address, static_cast<std::uint8_t>(phase & 3u));
    }
    static constexpr std::uint16_t inverse_phase(std::uint16_t address,
                                                  std::uint8_t phase) {
        // Klein-four: I, B, BR and R are all involutions.
        return apply_transform_phase(address, static_cast<std::uint8_t>(phase & 3u));
    }
    static constexpr std::uint16_t forward(std::uint16_t address, NanType type) {
        return forward_phase(address, phase_for(type));
    }
    static constexpr std::uint16_t inverse(std::uint16_t address, NanType type) {
        return inverse_phase(address, phase_for(type));
    }
};

} // namespace nanlm
