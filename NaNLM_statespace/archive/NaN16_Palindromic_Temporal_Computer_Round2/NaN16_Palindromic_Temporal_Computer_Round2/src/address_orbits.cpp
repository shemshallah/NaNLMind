#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

namespace nan16 {

constexpr std::uint32_t kAddressCount = 1u << 16;

std::uint16_t reverse16(std::uint16_t x) {
    std::uint16_t y = 0;
    for (int i = 0; i < 16; ++i) {
        y = static_cast<std::uint16_t>((y << 1) | (x & 1u));
        x = static_cast<std::uint16_t>(x >> 1);
    }
    return y;
}

std::uint16_t byte_swap16(std::uint16_t x) {
    return static_cast<std::uint16_t>((x << 8) | (x >> 8));
}

std::uint16_t four_transform(std::uint16_t x, unsigned mask) {
    if (mask & 1u) x = byte_swap16(x);
    if (mask & 2u) x = reverse16(x);
    return x;
}

std::vector<std::uint16_t> orbit(std::uint16_t x) {
    std::set<std::uint16_t> members;
    for (unsigned mask = 0; mask < 4; ++mask)
        members.insert(four_transform(x, mask));
    return {members.begin(), members.end()};
}

struct Counts {
    std::uint32_t bit_fixed = 0;
    std::uint32_t bit_pairs = 0;
    std::uint32_t byte_fixed = 0;
    std::uint32_t byte_pairs = 0;
    std::uint32_t orbit1 = 0;
    std::uint32_t orbit2 = 0;
    std::uint32_t orbit4 = 0;
};

Counts enumerate() {
    Counts c;
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        auto a = static_cast<std::uint16_t>(i);
        if (reverse16(a) == a) ++c.bit_fixed;
        if (byte_swap16(a) == a) ++c.byte_fixed;
    }
    c.bit_pairs = (kAddressCount - c.bit_fixed) / 2;
    c.byte_pairs = (kAddressCount - c.byte_fixed) / 2;

    std::set<std::uint16_t> seen;
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        auto a = static_cast<std::uint16_t>(i);
        if (seen.count(a)) continue;
        auto members = orbit(a);
        for (auto m : members) seen.insert(m);
        if (members.size() == 1) ++c.orbit1;
        else if (members.size() == 2) ++c.orbit2;
        else if (members.size() == 4) ++c.orbit4;
        else throw std::runtime_error("unexpected orbit size");
    }
    if (seen.size() != kAddressCount)
        throw std::runtime_error("orbit partition did not cover address space");
    return c;
}

// A tiny temporal cell: shared payload, two directional ports, before-image log.
class TemporalPair {
public:
    struct Event { std::uint64_t epoch; std::uint32_t before; std::uint32_t after; };

    explicit TemporalPair(std::uint16_t address)
        : canonical_(std::min(address, reverse16(address))),
          mirror_(reverse16(canonical_)), value_(0), epoch_(0) {}

    void forward_write(std::uint32_t next) {
        log_.push_back(Event{++epoch_, value_, next});
        value_ = next;
    }

    bool reverse_one() {
        if (log_.empty()) return false;
        const Event e = log_.back();
        value_ = e.before;
        epoch_ = e.epoch - 1;
        log_.pop_back();
        return true;
    }

    std::uint16_t canonical() const { return canonical_; }
    std::uint16_t mirror() const { return mirror_; }
    std::uint32_t value() const { return value_; }
    std::uint64_t epoch() const { return epoch_; }
    std::size_t history_size() const { return log_.size(); }

private:
    std::uint16_t canonical_;
    std::uint16_t mirror_;
    std::uint32_t value_;
    std::uint64_t epoch_;
    std::vector<Event> log_;
};

} // namespace nan16

#ifndef NAN16_NO_MAIN
int main() {
    const auto c = nan16::enumerate();
    std::cout << "address_count=" << nan16::kAddressCount << '\n'
              << "bit_reverse_fixed_points=" << c.bit_fixed << '\n'
              << "bit_reverse_pairs=" << c.bit_pairs << '\n'
              << "byte_swap_fixed_points=" << c.byte_fixed << '\n'
              << "byte_swap_pairs=" << c.byte_pairs << '\n'
              << "combined_orbits_size_1=" << c.orbit1 << '\n'
              << "combined_orbits_size_2=" << c.orbit2 << '\n'
              << "combined_orbits_size_4=" << c.orbit4 << '\n'
              << "combined_orbit_count=" << (c.orbit1 + c.orbit2 + c.orbit4) << '\n';
}
#endif
