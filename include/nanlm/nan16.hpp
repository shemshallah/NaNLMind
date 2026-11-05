// NaNLM Universal — core address algebra and NaN16 word model.
//
// The address space is the computer. A 16-bit address is a coordinate in a
// 256 x 256 matrix. Bit reversal is transposition:
//
//     addr(a, b) = (a << 8) | reverse8(b)
//     reverse16(addr(a, b)) = addr(b, a)
//
// The 256 diagonal addresses are fixed points of reversal. The 32,640
// off-diagonal addresses form mirror pairs and are exactly C(256, 2). Every
// unordered pair of heads has one canonical cell with two rails.
#pragma once

#include <bit>
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <utility>

namespace nanlm {

// ---------------------------------------------------------------------------
// Exact address-space constants
// ---------------------------------------------------------------------------

inline constexpr std::uint32_t kAddressBits = 16;
inline constexpr std::uint32_t kAddressCount = 1u << kAddressBits;          // 65,536
inline constexpr std::uint32_t kFixedPointCount = 1u << 8;                  // 256
inline constexpr std::uint32_t kMirrorPairCount = (kAddressCount - kFixedPointCount) / 2; // 32,640
inline constexpr std::uint32_t kCanonicalCount = kMirrorPairCount + kFixedPointCount;     // 32,896

static_assert(kAddressCount == 65536);
static_assert(kFixedPointCount == 256);
static_assert(kMirrorPairCount == 32640);
static_assert(kCanonicalCount == 32896);
static_assert(kMirrorPairCount == (kFixedPointCount * (kFixedPointCount - 1)) / 2);

constexpr std::uint8_t reverse8(std::uint8_t x) {
    x = static_cast<std::uint8_t>(((x & 0xF0u) >> 4) | ((x & 0x0Fu) << 4));
    x = static_cast<std::uint8_t>(((x & 0xCCu) >> 2) | ((x & 0x33u) << 2));
    x = static_cast<std::uint8_t>(((x & 0xAAu) >> 1) | ((x & 0x55u) << 1));
    return x;
}

constexpr std::uint16_t reverse16(std::uint16_t x) {
    return static_cast<std::uint16_t>(
        (static_cast<std::uint16_t>(reverse8(static_cast<std::uint8_t>(x & 0xFFu))) << 8) |
        reverse8(static_cast<std::uint8_t>(x >> 8)));
}

constexpr std::uint16_t byte_swap16(std::uint16_t x) {
    return static_cast<std::uint16_t>((x << 8) | (x >> 8));
}

constexpr std::uint16_t canonical16(std::uint16_t a) {
    return a <= reverse16(a) ? a : reverse16(a);
}

constexpr bool is_palindrome16(std::uint16_t a) {
    return reverse16(a) == a;
}

// Matrix view: row = high byte, column = reverse8(low byte).
constexpr std::uint16_t matrix_addr(std::uint8_t row, std::uint8_t col) {
    return static_cast<std::uint16_t>((static_cast<std::uint16_t>(row) << 8) |
                                      reverse8(col));
}

constexpr std::uint8_t matrix_row(std::uint16_t a) {
    return static_cast<std::uint8_t>(a >> 8);
}

constexpr std::uint8_t matrix_col(std::uint16_t a) {
    return reverse8(static_cast<std::uint8_t>(a & 0xFFu));
}

constexpr std::uint16_t transpose16(std::uint16_t a) {
    return reverse16(a);
}

// Dense index of the unordered pair {a, b}, a != b. Range: [0, 32,640).
constexpr std::uint32_t pair_index(std::uint8_t a, std::uint8_t b) {
    if (a > b) {
        const std::uint8_t t = a;
        a = b;
        b = t;
    }
    if (a == b) return kMirrorPairCount; // sentinel: not a pair
    return static_cast<std::uint32_t>(a) * 255u -
           (static_cast<std::uint32_t>(a) * static_cast<std::uint32_t>(a - 1u)) / 2u +
           static_cast<std::uint32_t>(b - a - 1u);
}

constexpr std::pair<std::uint8_t, std::uint8_t> pair_heads(std::uint32_t index) {
    std::uint32_t a = 0;
    while (true) {
        const std::uint32_t count = 255u - a;
        if (index < count) {
            return {static_cast<std::uint8_t>(a),
                    static_cast<std::uint8_t>(a + 1u + index)};
        }
        index -= count;
        ++a;
    }
}

constexpr std::uint16_t pair_address(std::uint32_t index) {
    const auto [a, b] = pair_heads(index);
    return canonical16(matrix_addr(a, b));
}

constexpr std::uint8_t hamming8(std::uint8_t a, std::uint8_t b) {
    return static_cast<std::uint8_t>(std::popcount(static_cast<unsigned>(a ^ b)));
}

// ---------------------------------------------------------------------------
// Four NaN types and the 16 Boolean functions
// ---------------------------------------------------------------------------
//
// The four legal NaN16 heads are the four NaN types. Each word has two faces
// (far and near), each face carries one of four types, so the class nibble
//
//     n = (near_class << 2) | far_class
//
// has 16 values. For BOOL, n is the truth table: bit k of n is f(a, b) with
// k = 2a + b. The four types x four values = the 16 Boolean functions.

enum class NanType : std::uint8_t {
    SignalPositive = 0, // 0x7FF1
    SignalNegative = 1, // 0xFFF1
    QuietPositive  = 2, // 0x7FF8
    QuietNegative  = 3, // 0xFFF8
};

constexpr std::uint16_t nan_head(NanType t) {
    switch (t) {
        case NanType::SignalPositive: return 0x7FF1;
        case NanType::SignalNegative: return 0xFFF1;
        case NanType::QuietPositive:  return 0x7FF8;
        case NanType::QuietNegative:  return 0xFFF8;
    }
    return 0;
}

constexpr std::uint8_t class_of_head(std::uint16_t head) {
    switch (head) {
        case 0x7FF1: return 0;
        case 0xFFF1: return 1;
        case 0x7FF8: return 2;
        case 0xFFF8: return 3;
        default:     return 0xFF;
    }
}

constexpr std::string_view nan_type_name(NanType t) {
    switch (t) {
        case NanType::SignalPositive: return "+sNaN";
        case NanType::SignalNegative: return "-sNaN";
        case NanType::QuietPositive:  return "+qNaN";
        case NanType::QuietNegative:  return "-qNaN";
    }
    return "invalid";
}

// 64-bit NaN16 word. Raw bytes are laid out as:
//   b0 b1      far head, big-endian
//   b2 b3 b4 b5 payload, little-endian
//   b6 b7      near head, little-endian
struct NanWord {
    std::uint64_t raw = 0;

    constexpr NanWord() = default;
    constexpr explicit NanWord(std::uint64_t v) : raw(v) {}

    static constexpr NanWord make(NanType far, NanType near, std::uint32_t payload) {
        const std::uint16_t f = nan_head(far);
        const std::uint16_t n = nan_head(near);
        std::uint64_t v = static_cast<std::uint64_t>((f >> 8) & 0xFFu);
        v |= static_cast<std::uint64_t>(f & 0xFFu) << 8;
        v |= static_cast<std::uint64_t>(payload) << 16;
        v |= static_cast<std::uint64_t>(n & 0xFFu) << 48;
        v |= static_cast<std::uint64_t>((n >> 8) & 0xFFu) << 56;
        return NanWord(v);
    }

    constexpr std::uint16_t far_head() const {
        return static_cast<std::uint16_t>(((raw & 0xFFu) << 8) | ((raw >> 8) & 0xFFu));
    }
    constexpr std::uint16_t near_head() const {
        return static_cast<std::uint16_t>((raw >> 48) & 0xFFFFu);
    }
    constexpr std::uint8_t far_class() const { return class_of_head(far_head()); }
    constexpr NanType far_type() const {
        const std::uint8_t c = far_class();
        return c == 0xFF ? NanType::QuietPositive : static_cast<NanType>(c);
    }
    constexpr std::uint8_t near_class() const { return class_of_head(near_head()); }
    constexpr std::uint8_t opcode() const {
        return static_cast<std::uint8_t>((near_class() << 2) | far_class());
    }
    constexpr std::uint32_t payload() const {
        return static_cast<std::uint32_t>((raw >> 16) & 0xFFFFFFFFu);
    }
    constexpr bool valid() const {
        return far_class() != 0xFF && near_class() != 0xFF;
    }
    // BSWAPM: reverse all eight bytes, swapping the faces and reversing the
    // payload bytes. The mirror law is BOOL.rot2(n)(a,b) == BOOL.n(~a,b).
    constexpr NanWord bswap() const { return NanWord(__builtin_bswap64(raw)); }

    static constexpr std::uint32_t eval_bool(std::uint8_t n, std::uint32_t a,
                                             std::uint32_t b) {
        std::uint32_t out = 0;
        for (int lane = 0; lane < 32; ++lane) {
            const std::uint32_t av = (a >> lane) & 1u;
            const std::uint32_t bv = (b >> lane) & 1u;
            const std::uint32_t idx = 2u * av + bv;
            if ((n >> idx) & 1u) out |= (1u << lane);
        }
        return out;
    }
    constexpr std::uint32_t eval_bool(std::uint32_t a, std::uint32_t b) const {
        return eval_bool(opcode(), a, b);
    }
};

constexpr std::uint8_t rot2(std::uint8_t n) {
    return static_cast<std::uint8_t>(((n & 0x3u) << 2) | (n >> 2));
}

constexpr std::string_view bool_op_name(std::uint8_t n) {
    switch (n & 0xFu) {
        case 0:  return "CONST0";
        case 1:  return "NOR";
        case 2:  return "ANDN";      // ~A & B
        case 3:  return "NOTA";
        case 4:  return "NADN";      // A & ~B
        case 5:  return "NOTB";
        case 6:  return "XOR";
        case 7:  return "NAND";
        case 8:  return "AND";
        case 9:  return "XNOR";
        case 10: return "B";
        case 11: return "IMPLA";     // ~A | B
        case 12: return "A";
        case 13: return "IMPLB";     // A | ~B
        case 14: return "OR";
        case 15: return "CONST1";
    }
    return "INVALID";
}

// ---------------------------------------------------------------------------
// Four orientations of an address / word
// ---------------------------------------------------------------------------

enum class Orientation : std::uint8_t {
    Identity = 0,
    ByteSwap = 1,
    BitReverse = 2,
    ByteAndBitReverse = 3,
};

constexpr std::uint16_t transform16(std::uint16_t a, Orientation o) {
    std::uint16_t x = a;
    if ((static_cast<std::uint8_t>(o) & 1u) != 0) x = byte_swap16(x);
    if ((static_cast<std::uint8_t>(o) & 2u) != 0) x = reverse16(x);
    return x;
}

// The four images of an address under the Klein-four action. This is a
// different "4" from the four NaN head classes:
//   phase 0 = I, 1 = B, 2 = B∘R, 3 = R.
// Alternating B and R gives x -> Bx -> BRx -> Rx -> x.
enum class TransformPhase : std::uint8_t {
    Identity = 0,
    ByteSwap = 1,
    Both = 2,
    BitReverse = 3,
};

constexpr std::uint16_t apply_transform_phase(std::uint16_t a, std::uint8_t phase) {
    switch (phase & 3u) {
        case 0: return a;
        case 1: return byte_swap16(a);
        case 2: return transform16(a, Orientation::ByteAndBitReverse);
        case 3: return reverse16(a);
    }
    return a;
}

constexpr std::uint8_t next_transform_phase(std::uint8_t phase) {
    return static_cast<std::uint8_t>((phase + 1u) & 3u);
}

// Advance the oscillator by one tick: alternating B, R, B, R.
// phase 0 (I) -> B, phase 1 (B) -> R, phase 2 (BR) -> B, phase 3 (R) -> R.
constexpr std::uint16_t advance_transform_phase(std::uint16_t a, std::uint8_t phase) {
    return (phase & 1u) ? reverse16(a) : byte_swap16(a);
}

// Orbit size under the Klein-four action {I, B, R, B∘R}.
constexpr std::uint8_t transform_orbit_size(std::uint16_t a) {
    const bool b = byte_swap16(a) == a;
    const bool r = reverse16(a) == a;
    if (b && r) return 1;
    if (b || r) return 2;
    return 4;
}

constexpr bool transform_static(std::uint16_t a) {
    return byte_swap16(a) == a && reverse16(a) == a;
}

constexpr std::string_view transform_phase_name(std::uint8_t phase) {
    switch (phase & 3u) {
        case 0: return "I";
        case 1: return "B";
        case 2: return "BR";
        case 3: return "R";
    }
    return "?";
}

constexpr std::string_view orientation_name(Orientation o) {
    switch (o) {
        case Orientation::Identity: return "I";
        case Orientation::ByteSwap: return "B";
        case Orientation::BitReverse: return "R";
        case Orientation::ByteAndBitReverse: return "BR";
    }
    return "?";
}

// Deterministic 32-bit mixer used by the genesis state space.
constexpr std::uint32_t mix32(std::uint32_t x) {
    x ^= x >> 16;
    x *= 0x7FEB352Du;
    x ^= x >> 15;
    x *= 0x846CA68Bu;
    x ^= x >> 16;
    return x;
}

constexpr std::uint32_t mix_pair(std::uint8_t a, std::uint8_t b) {
    return mix32(static_cast<std::uint32_t>(a) * 0x9E3779B9u ^
                 static_cast<std::uint32_t>(b) * 0x85EBCA6Bu ^ 0xA5A5A5A5u);
}

} // namespace nanlm
