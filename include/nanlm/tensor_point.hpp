// Canonical 256^3 tensor point identity.
//
// A point is (head, a, b) with all axes in 0..254.  The encoded reference is
//   tag 'N' | head << 16 | addr16(a,b)
// where addr16(u,v) = (tp_reverse8(u) << 8) | v.  The low byte is v, so the
// mirror point (b,a) is the byte-swap of addr16(a,b).
#pragma once
#include <compare>
#include <cstddef>
#include <cstdint>
#include <optional>

namespace nanlm {

inline constexpr std::uint32_t kTensorPointTag = 0x4E000000u; // 'N'
inline constexpr std::uint32_t kTensorHeadSlots = 1u << 16;
inline constexpr std::uint32_t kTensorBankBytes = 1u << 26;

constexpr std::uint8_t tp_reverse8(std::uint8_t v) noexcept {
    std::uint8_t r = 0;
    for (unsigned i = 0; i < 8; ++i) {
        r = static_cast<std::uint8_t>((r << 1) | (v & 1u));
        v = static_cast<std::uint8_t>(v >> 1);
    }
    return r;
}
constexpr std::uint16_t pal16(std::uint8_t anchor) noexcept {
    return static_cast<std::uint16_t>((tp_reverse8(anchor) << 8) | anchor);
}
constexpr std::uint16_t addr16(std::uint8_t u, std::uint8_t v) noexcept {
    return static_cast<std::uint16_t>((tp_reverse8(u) << 8) | v);
}

struct TensorPointRef {
    std::uint32_t bits = 0;

    static constexpr std::optional<TensorPointRef>
    make(unsigned h, unsigned a, unsigned b) noexcept {
        if (h >= 255u || a >= 255u || b >= 255u) return std::nullopt;
        return TensorPointRef{kTensorPointTag |
            (static_cast<std::uint32_t>(h) << 16) |
            addr16(static_cast<std::uint8_t>(a),
                   static_cast<std::uint8_t>(b))};
    }
    static constexpr std::optional<TensorPointRef>
    from_bits(std::uint32_t bits) noexcept {
        if ((bits & 0xFF000000u) != kTensorPointTag) return std::nullopt;
        const unsigned h = (bits >> 16) & 0xFFu;
        const unsigned a = tp_reverse8(static_cast<std::uint8_t>((bits >> 8) & 0xFFu));
        const unsigned b = bits & 0xFFu;
        if (h >= 255u || a >= 255u || b >= 255u) return std::nullopt;
        return TensorPointRef{bits};
    }
    constexpr bool valid() const noexcept {
        return (bits & 0xFF000000u) == kTensorPointTag &&
            ((bits >> 16) & 0xFFu) < 255u &&
            tp_reverse8(static_cast<std::uint8_t>((bits >> 8) & 0xFFu)) < 255u &&
            (bits & 0xFFu) < 255u;
    }
    constexpr std::uint8_t h() const noexcept {
        return static_cast<std::uint8_t>((bits >> 16) & 0xFFu);
    }
    constexpr std::uint8_t a() const noexcept {
        return tp_reverse8(static_cast<std::uint8_t>((bits >> 8) & 0xFFu));
    }
    constexpr std::uint8_t b() const noexcept {
        return static_cast<std::uint8_t>(bits & 0xFFu);
    }
    constexpr std::uint16_t pair_addr() const noexcept {
        return static_cast<std::uint16_t>(bits & 0xFFFFu);
    }
    constexpr std::uint16_t head_pal() const noexcept { return pal16(h()); }
    constexpr TensorPointRef mirror() const noexcept {
        auto p = from_bits(bits);
        if (!p) return *this;
        return *make(p->h(), p->b(), p->a());
    }
    constexpr std::size_t slot() const noexcept {
        const unsigned hi = a() > b() ? a() : b();
        const unsigned lo = a() < b() ? a() : b();
        if (a() == b()) return a();
        const std::size_t pair = (std::size_t(lo) * (511u - lo)) / 2u + hi - lo - 1u;
        return 256u + 2u * pair + (a() > b() ? 1u : 0u);
    }
    constexpr std::size_t index() const noexcept {
        return (std::size_t(h()) << 16) + slot();
    }
    constexpr std::size_t byte_offset(unsigned bank) const noexcept {
        return std::size_t(bank) * kTensorBankBytes + 4u * index();
    }
    friend constexpr bool operator==(TensorPointRef, TensorPointRef) = default;
    friend constexpr auto operator<=>(TensorPointRef, TensorPointRef) = default;
};

constexpr std::size_t tensor_index(unsigned h, unsigned a, unsigned b) {
    return TensorPointRef::make(h, a, b)->index();
}
constexpr std::size_t tensor_byte_offset(unsigned h, unsigned a, unsigned b,
                                         unsigned bank) {
    return TensorPointRef::make(h, a, b)->byte_offset(bank);
}

} // namespace nanlm
