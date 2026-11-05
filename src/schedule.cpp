#include "nanlm/schedule.hpp"

#include <algorithm>

namespace nanlm {
namespace {

std::uint64_t splitmix64(std::uint64_t& x) {
    std::uint64_t z = (x += 0x9E3779B97F4A7C15ull);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
    return z ^ (z >> 31);
}

} // namespace

std::vector<std::uint8_t> bit_reversed_wake_slots(int count) {
    count = std::max(0, std::min(count, 256));
    std::vector<std::uint8_t> out;
    out.reserve(static_cast<std::size_t>(count));
    for (int i = 0; i < count; ++i) {
        out.push_back(reverse8(static_cast<std::uint8_t>(i)));
    }
    return out;
}

std::vector<std::uint8_t> linear_wake_slots(int count) {
    count = std::max(0, std::min(count, 256));
    std::vector<std::uint8_t> out;
    out.reserve(static_cast<std::size_t>(count));
    for (int i = 0; i < count; ++i) out.push_back(static_cast<std::uint8_t>(i));
    return out;
}

std::vector<std::uint8_t> random_wake_slots(int count, std::uint64_t seed) {
    count = std::max(0, std::min(count, 256));
    std::vector<std::uint8_t> all(256);
    for (int i = 0; i < 256; ++i) all[i] = static_cast<std::uint8_t>(i);
    std::uint64_t state = seed;
    for (int i = 255; i > 0; --i) {
        const int j = static_cast<int>(splitmix64(state) % static_cast<std::uint64_t>(i + 1));
        std::swap(all[i], all[j]);
    }
    all.resize(static_cast<std::size_t>(count));
    return all;
}

int max_wake_gap(const std::vector<std::uint8_t>& slots, int slot_count) {
    if (slots.empty()) return slot_count;
    if (slots.size() == 1) return slot_count;
    std::vector<int> s;
    s.reserve(slots.size());
    for (std::uint8_t x : slots) s.push_back(x % slot_count);
    std::sort(s.begin(), s.end());
    int best = 0;
    for (std::size_t i = 1; i < s.size(); ++i) best = std::max(best, s[i] - s[i - 1]);
    best = std::max(best, slot_count - s.back() + s.front());
    return best;
}

int ideal_max_gap(int count, int slot_count) {
    if (count <= 0) return slot_count;
    return (slot_count + count - 1) / count;
}

std::vector<std::uint16_t> palindromic_epochs() {
    std::vector<std::uint16_t> out;
    out.reserve(256);
    for (std::uint32_t i = 0; i < 65536; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        if (is_palindrome16(a)) out.push_back(a);
    }
    return out;
}

} // namespace nanlm
