#include "nanlm/nan16.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    // The four legal heads.
    CHECK_EQ(nan_head(NanType::SignalPositive), 0x7FF1u);
    CHECK_EQ(nan_head(NanType::SignalNegative), 0xFFF1u);
    CHECK_EQ(nan_head(NanType::QuietPositive), 0x7FF8u);
    CHECK_EQ(nan_head(NanType::QuietNegative), 0xFFF8u);
    for (int t = 0; t < 4; ++t) {
        CHECK_EQ(class_of_head(nan_head(static_cast<NanType>(t))), t);
    }
    CHECK_EQ(class_of_head(0x1234), 0xFFu);

    // Word layout and payload.
    for (int far = 0; far < 4; ++far) {
        for (int near = 0; near < 4; ++near) {
            const std::uint32_t payload = 0xA5C3F00Du ^ static_cast<std::uint32_t>(far * 17 + near);
            const NanWord w = NanWord::make(static_cast<NanType>(far),
                                            static_cast<NanType>(near), payload);
            CHECK(w.valid());
            CHECK_EQ(w.far_class(), static_cast<std::uint8_t>(far));
            CHECK_EQ(w.near_class(), static_cast<std::uint8_t>(near));
            CHECK_EQ(w.opcode(), static_cast<std::uint8_t>((near << 2) | far));
            CHECK_EQ(w.payload(), payload);
            CHECK(w.bswap().valid());
            CHECK_EQ(w.bswap().bswap().raw, w.raw);
            CHECK_EQ(w.bswap().opcode(), rot2(w.opcode()));
        }
    }

    // All 16 Boolean functions match the scalar truth table.
    for (int n = 0; n < 16; ++n) {
        const std::uint32_t a = 0xCCCCCCCCu;
        const std::uint32_t b = 0xAAAAAAAAu;
        CHECK_EQ(NanWord::eval_bool(static_cast<std::uint8_t>(n), a, b),
                 static_cast<std::uint32_t>(n) * 0x11111111u);
        for (int lane = 0; lane < 32; ++lane) {
            const std::uint32_t av = (a >> lane) & 1u;
            const std::uint32_t bv = (b >> lane) & 1u;
            const std::uint32_t out = (NanWord::eval_bool(static_cast<std::uint8_t>(n), a, b) >>
                                       lane) & 1u;
            CHECK_EQ(out, (static_cast<std::uint32_t>(n) >> (2u * av + bv)) & 1u);
        }
    }

    // Mirror law and rot2 involution.
    for (int n = 0; n < 16; ++n) {
        CHECK_EQ(rot2(rot2(static_cast<std::uint8_t>(n))), static_cast<std::uint8_t>(n));
        CHECK_EQ(NanWord::eval_bool(rot2(static_cast<std::uint8_t>(n)), 0xCCCCCCCCu, 0xAAAAAAAAu),
                 NanWord::eval_bool(static_cast<std::uint8_t>(n), ~0xCCCCCCCCu, 0xAAAAAAAAu));
    }

    // Named functions and a few known values.
    CHECK_EQ(NanWord::eval_bool(0, 0xFFFFFFFFu, 0x00000000u), 0u);
    CHECK_EQ(NanWord::eval_bool(15, 0x00000000u, 0xFFFFFFFFu), 0xFFFFFFFFu);
    CHECK_EQ(NanWord::eval_bool(6, 0xF0F0F0F0u, 0xFFFF0000u), 0x0F0FF0F0u);
    CHECK_EQ(NanWord::eval_bool(8, 0xF0F0F0F0u, 0xFF00FF00u), 0xF000F000u);

    // Four orientations are involutions and commute as expected.
    for (std::uint32_t i = 0; i < 65536; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        for (int o = 0; o < 4; ++o) {
            const auto t = static_cast<Orientation>(o);
            CHECK_EQ(transform16(transform16(a, t), t), a);
        }
    }

    return test_done("NaN16 word and Boolean algebra");
}
