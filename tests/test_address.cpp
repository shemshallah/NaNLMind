#include "nanlm/nan16.hpp"
#include "test_util.hpp"

#include <set>

using namespace nanlm;

int main() {
    CHECK_EQ(kAddressCount, 65536u);
    CHECK_EQ(kFixedPointCount, 256u);
    CHECK_EQ(kMirrorPairCount, 32640u);
    CHECK_EQ(kCanonicalCount, 32896u);
    CHECK_EQ(kMirrorPairCount, (kFixedPointCount * (kFixedPointCount - 1)) / 2);

    // Involutions and canonicalization.
    std::uint32_t fixed = 0;
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        CHECK(reverse16(reverse16(a)) == a);
        CHECK(canonical16(canonical16(a)) == canonical16(a));
        CHECK(canonical16(a) <= a);
        CHECK(canonical16(a) <= reverse16(a));
        if (is_palindrome16(a)) {
            CHECK(canonical16(a) == a);
            ++fixed;
        }
        CHECK(byte_swap16(byte_swap16(a)) == a);
    }
    CHECK_EQ(fixed, 256u);

    // Matrix transposition theorem: reverse16(addr(a,b)) == addr(b,a).
    for (std::uint32_t a = 0; a < 256; ++a) {
        for (std::uint32_t b = 0; b < 256; ++b) {
            const auto ab = matrix_addr(static_cast<std::uint8_t>(a),
                                        static_cast<std::uint8_t>(b));
            const auto ba = matrix_addr(static_cast<std::uint8_t>(b),
                                        static_cast<std::uint8_t>(a));
            CHECK_EQ(reverse16(ab), ba);
            CHECK_EQ(matrix_row(ab), static_cast<std::uint8_t>(a));
            CHECK_EQ(matrix_col(ab), static_cast<std::uint8_t>(b));
        }
    }

    // Every palindromic address is on the diagonal.
    for (std::uint16_t a = 0; a < 65535; ++a) {
        const bool pal = is_palindrome16(a);
        const bool diag = matrix_row(a) == matrix_col(a);
        CHECK_EQ(pal, diag);
    }

    // Pair indexing is a bijection over C(256,2).
    std::set<std::uint32_t> seen;
    for (std::uint32_t a = 0; a < 256; ++a) {
        for (std::uint32_t b = a + 1; b < 256; ++b) {
            const std::uint32_t p = pair_index(static_cast<std::uint8_t>(a),
                                               static_cast<std::uint8_t>(b));
            CHECK(p < kMirrorPairCount);
            CHECK(pair_heads(p) == std::make_pair(static_cast<std::uint8_t>(a),
                                                  static_cast<std::uint8_t>(b)));
            CHECK(seen.insert(p).second);
        }
    }
    CHECK_EQ(seen.size(), static_cast<std::size_t>(kMirrorPairCount));

    // Pair address is the canonical address of the mirrored pair.
    for (std::uint32_t p = 0; p < kMirrorPairCount; ++p) {
        const auto [a, b] = pair_heads(p);
        const std::uint16_t addr = pair_address(p);
        CHECK_EQ(addr, canonical16(matrix_addr(a, b)));
        CHECK_EQ(addr, canonical16(matrix_addr(b, a)));
        CHECK_EQ(reverse16(addr), matrix_addr(b, a));
    }

    // Four orientations form a Klein-four orbit.
    for (std::uint32_t i = 0; i < 65536; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        for (int o = 0; o < 4; ++o) {
            const auto t = static_cast<Orientation>(o);
            CHECK_EQ(transform16(transform16(a, t), t), a);
        }
    }

    // Hamming distance is symmetric and zero only on equality.
    for (int a = 0; a < 256; ++a) {
        CHECK_EQ(hamming8(static_cast<std::uint8_t>(a), static_cast<std::uint8_t>(a)), 0u);
        for (int b = 0; b < 256; ++b) {
            CHECK_EQ(hamming8(static_cast<std::uint8_t>(a), static_cast<std::uint8_t>(b)),
                     hamming8(static_cast<std::uint8_t>(b), static_cast<std::uint8_t>(a)));
        }
    }

    return test_done("address algebra");
}
