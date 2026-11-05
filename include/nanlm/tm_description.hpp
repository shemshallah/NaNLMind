// Versioned TM description grammar used by the universal interpreter.
#pragma once

#include "nanlm/turing_machine.hpp"

#include <cstdint>
#include <optional>
#include <vector>

namespace nanlm {

struct TmDescription {
    static constexpr std::uint16_t kVersion = 1;
    std::uint16_t states = 16;
    std::uint16_t alphabet = 4;
    std::vector<TmTransition> transitions;

    std::vector<std::uint8_t> encode() const;
    static std::optional<TmDescription> decode(const std::uint8_t* data, std::size_t len);
    bool valid() const;
};

} // namespace nanlm
