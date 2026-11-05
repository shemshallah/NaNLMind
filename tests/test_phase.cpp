#include "nanlm/head.hpp"
#include "nanlm/schedule.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    // The four transform images form a reversible 4-phase oscillator.
    std::uint32_t count4 = 0, count2 = 0, count1 = 0;
    for (std::uint32_t i = 0; i < 65536; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        const std::uint8_t size = transform_orbit_size(a);
        if (size == 4) ++count4;
        else if (size == 2) ++count2;
        else if (size == 1) ++count1;
        else CHECK(false);

        // x -> Bx -> BRx -> Rx -> x, with alternating B, R, B, R.
        CHECK_EQ(apply_transform_phase(a, 0), a);
        CHECK_EQ(apply_transform_phase(a, 1), byte_swap16(a));
        CHECK_EQ(apply_transform_phase(a, 2), reverse16(byte_swap16(a)));
        CHECK_EQ(apply_transform_phase(a, 3), reverse16(a));
        std::uint16_t x = a;
        std::uint8_t phase = 0;
        for (int s = 0; s < 4; ++s) {
            x = advance_transform_phase(x, phase);
            phase = next_transform_phase(phase);
            CHECK_EQ(x, apply_transform_phase(a, phase));
        }
        CHECK_EQ(x, a);
        CHECK_EQ(phase, 0);
    }
    CHECK_EQ(count4, 65040u);
    CHECK_EQ(count2, 480u);
    CHECK_EQ(count1, 16u);

    // The 256 palindromic head anchors: 240 half-rate, 16 static.
    std::uint32_t half = 0, fixed = 0;
    for (std::uint32_t i = 0; i < 65536; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        if (!is_palindrome16(a)) continue;
        const std::uint8_t s = transform_orbit_size(a);
        if (s == 1) ++fixed;
        else if (s == 2) ++half;
        else CHECK(false);
    }
    CHECK_EQ(fixed, 16u);
    CHECK_EQ(half, 240u);

    // Bit-reversed wake slots stay evenly spread for any power-of-two subset.
    const auto bits8 = bit_reversed_wake_slots(8);
    const auto linear8 = linear_wake_slots(8);
    CHECK_EQ(max_wake_gap(bits8), 32);
    CHECK_EQ(max_wake_gap(linear8), 249);
    CHECK_EQ(max_wake_gap(bit_reversed_wake_slots(16)), 16);
    CHECK_EQ(max_wake_gap(linear_wake_slots(16)), 241);
    CHECK_EQ(max_wake_gap(bit_reversed_wake_slots(32)), 8);
    CHECK_EQ(max_wake_gap(linear_wake_slots(32)), 225);
    CHECK_EQ(max_wake_gap(bit_reversed_wake_slots(5)), 64);
    CHECK_EQ(ideal_max_gap(5), 52);

    // The 16-bit palindromic ticks are irregular self-dual markers.
    const auto epochs = palindromic_epochs();
    CHECK_EQ(epochs.size(), 256u);
    CHECK(is_palindromic_tick(0));
    CHECK(is_palindromic_tick(0x0180));
    CHECK(!is_palindromic_tick(0x0001));
    return test_done("transform phase and wake scheduling");
}
