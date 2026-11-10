// Canonical compact head catalog.
//
// All cognitive heads are exactly 0..254. The list is the identity mapping, so
// no per-head 256-bit leaf mask or separate leaf table is needed for the full
// set. Head 255 remains the field/network head and is not a leaf.
#pragma once

#include <cstddef>
#include <cstdint>

namespace nanlm {

class HeadCatalog {
public:
    static constexpr std::uint8_t kFirst = 0;
    static constexpr std::uint8_t kLast = 254;
    static constexpr std::uint8_t kField = 255;
    static constexpr std::size_t kCount = 255;
    // The full set is represented by the range identity, not a 32-byte mask.
    static constexpr std::size_t kFullSetLeafBytes = 0;

    static constexpr bool contains(std::uint8_t head) noexcept {
        return head <= kLast;
    }
    static constexpr std::uint8_t at(std::size_t index) noexcept {
        return index < kCount ? static_cast<std::uint8_t>(index) : kField;
    }
    static constexpr std::uint8_t index_of(std::uint8_t head) noexcept {
        return contains(head) ? head : kField;
    }
    static constexpr std::uint8_t leaf_of(std::uint8_t head) noexcept {
        return index_of(head);
    }
    static constexpr bool head_of(std::uint8_t leaf, std::uint8_t& head) noexcept {
        if (!contains(leaf)) return false;
        head = leaf;
        return true;
    }
};

} // namespace nanlm
