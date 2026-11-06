// Stable 64-bit NaN16 identities for the four persistent storage tiers.
#pragma once

#include "nanlm/nan16.hpp"

#include <charconv>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace nanlm {

enum class VolumeTier : std::uint8_t {
    BS0 = 1,
    MC0 = 2,
    SC0 = 3,
    GM0 = 4,
};

inline constexpr std::uint8_t kVolumeAddressFormat = 1;
inline constexpr std::uint8_t kVolumeAddressMagic = 0x4E; // 'N'
inline constexpr NanType kVolumeAddressNanType = NanType::SignalPositive;

// CRC-8/ATM (poly 0x07, init 0, no reflection, xorout 0). This is a
// transcription/error detector, not an authentication mechanism.
constexpr std::uint8_t volume_address_crc8(std::uint32_t upper24) {
    std::uint8_t crc = 0;
    for (int byte = 2; byte >= 0; --byte) {
        crc ^= static_cast<std::uint8_t>(upper24 >> (byte * 8));
        for (int bit = 0; bit < 8; ++bit) {
            crc = (crc & 0x80u)
                ? static_cast<std::uint8_t>((crc << 1) ^ 0x07u)
                : static_cast<std::uint8_t>(crc << 1);
        }
    }
    return crc;
}

constexpr bool valid_volume_tier(VolumeTier tier) {
    const auto value = static_cast<std::uint8_t>(tier);
    return value >= 1 && value <= 4;
}

struct VolumeAddress {
    NanWord word{};

    static constexpr VolumeAddress make(VolumeTier tier, std::uint8_t shard = 0) {
        if (!valid_volume_tier(tier)) return {};
        const std::uint32_t upper24 =
            (static_cast<std::uint32_t>(kVolumeAddressMagic) << 16) |
            (static_cast<std::uint32_t>(kVolumeAddressFormat) << 12) |
            (static_cast<std::uint32_t>(tier) << 8) |
            static_cast<std::uint32_t>(shard);
        const std::uint32_t payload =
            (upper24 << 8) | volume_address_crc8(upper24);
        return {NanWord::make(kVolumeAddressNanType,
                              kVolumeAddressNanType, payload)};
    }

    constexpr std::uint32_t payload() const { return word.payload(); }
    constexpr std::uint8_t shard() const {
        return static_cast<std::uint8_t>((payload() >> 8) & 0xFFu);
    }
    constexpr VolumeTier tier() const {
        return static_cast<VolumeTier>((payload() >> 16) & 0x0Fu);
    }
    constexpr std::uint8_t format() const {
        return static_cast<std::uint8_t>((payload() >> 20) & 0x0Fu);
    }
    constexpr bool valid() const {
        if (!word.valid() ||
            word.far_type() != kVolumeAddressNanType ||
            word.near_class() != static_cast<std::uint8_t>(kVolumeAddressNanType)) {
            return false;
        }
        const std::uint32_t upper24 = payload() >> 8;
        return ((upper24 >> 16) & 0xFFu) == kVolumeAddressMagic &&
               format() == kVolumeAddressFormat &&
               valid_volume_tier(tier()) &&
               static_cast<std::uint8_t>(payload()) == volume_address_crc8(upper24);
    }

    // Canonical 64-bit integer spelling: /0x + 16 uppercase hex digits.
    // The two heads are the same +sNaN type. NanWord::make handles the
    // far-head BE and near-head LE byte placement.
    std::string path() const {
        static constexpr char digits[] = "0123456789ABCDEF";
        std::string out = "/0x0000000000000000";
        if (!valid()) return {};
        std::uint64_t value = word.raw;
        for (int i = 17; i >= 3; --i) {
            out[static_cast<std::size_t>(i)] = digits[value & 0x0Fu];
            value >>= 4;
        }
        return out;
    }

    static std::optional<VolumeAddress> parse(std::string_view text) {
        if (text.size() != 19 || text.substr(0, 3) != "/0x") return std::nullopt;
        std::uint64_t raw = 0;
        const char* first = text.data() + 3;
        const char* last = text.data() + text.size();
        const auto result = std::from_chars(first, last, raw, 16);
        if (result.ec != std::errc{} || result.ptr != last) return std::nullopt;
        VolumeAddress address{NanWord(raw)};
        if (!address.valid()) return std::nullopt;
        return address;
    }
};

constexpr VolumeAddress bs0_volume_address(std::uint8_t shard = 0) {
    return VolumeAddress::make(VolumeTier::BS0, shard);
}
constexpr VolumeAddress mc0_volume_address(std::uint8_t shard = 0) {
    return VolumeAddress::make(VolumeTier::MC0, shard);
}
constexpr VolumeAddress sc0_volume_address(std::uint8_t shard = 0) {
    return VolumeAddress::make(VolumeTier::SC0, shard);
}
constexpr VolumeAddress gm0_volume_address(std::uint8_t shard = 0) {
    return VolumeAddress::make(VolumeTier::GM0, shard);
}

} // namespace nanlm
