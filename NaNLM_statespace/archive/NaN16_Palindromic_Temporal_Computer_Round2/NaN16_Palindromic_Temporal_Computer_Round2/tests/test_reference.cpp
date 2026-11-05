#define NAN16_NO_MAIN
#include "../src/address_orbits.cpp"
#include <cassert>
#include <iostream>

int main() {
    using namespace nan16;

    // Involution and commutation checks across the complete 16-bit domain.
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        assert(reverse16(reverse16(a)) == a);
        assert(byte_swap16(byte_swap16(a)) == a);
        assert(reverse16(byte_swap16(a)) == byte_swap16(reverse16(a)));
    }

    const auto c = enumerate();
    assert(c.bit_fixed == 256);
    assert(c.bit_pairs == 32640);
    assert(c.byte_fixed == 256);
    assert(c.byte_pairs == 32640);

    // Burnside result / exact orbit-size distribution for {I, B, R, B o R}.
    assert(c.orbit1 == 16);
    assert(c.orbit2 == 360);
    assert(c.orbit4 == 16200);
    assert(c.orbit1 + c.orbit2 + c.orbit4 == 16576);
    assert(c.orbit1 + 2*c.orbit2 + 4*c.orbit4 == 65536);

    // Every orbit member maps back into the same orbit.
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        const auto o = orbit(a);
        assert(o.size() == 1 || o.size() == 2 || o.size() == 4);
        for (auto m : o) {
            const auto om = orbit(m);
            assert(om == o);
        }
    }

    // Shared-state temporal pair: forward writes retain before-images;
    // reverse traversal restores the exact previous values.
    TemporalPair p(0x1234);
    assert(p.canonical() == std::min<std::uint16_t>(0x1234, reverse16(0x1234)));
    assert(p.mirror() == reverse16(p.canonical()));
    assert(p.value() == 0 && p.epoch() == 0);
    p.forward_write(0xABCD);
    p.forward_write(0x5678);
    assert(p.value() == 0x5678 && p.epoch() == 2 && p.history_size() == 2);
    assert(p.reverse_one());
    assert(p.value() == 0xABCD && p.epoch() == 1);
    assert(p.reverse_one());
    assert(p.value() == 0 && p.epoch() == 0);
    assert(!p.reverse_one());

    // A bit-palindromic address is its own mirror.
    TemporalPair fixed(0x8001); // 1000 0000 0000 0001
    assert(reverse16(0x8001) == 0x8001);
    assert(fixed.canonical() == 0x8001);
    assert(fixed.mirror() == 0x8001);

    std::cout << "PASS: exhaustive 16-bit transform identities\n"
              << "PASS: bit/byte fixed-point and pair counts\n"
              << "PASS: combined four-transform orbit partition\n"
              << "PASS: temporal shared-pair forward/reverse restoration\n"
              << "PASS: palindromic fixed-point cell\n";
}
