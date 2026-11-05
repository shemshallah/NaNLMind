// Wake-slot scheduling for replicas / heads.
//
// Assigning wake slots in bit-reversed order keeps any surviving subset of a
// power-of-two size evenly spread. This is the scheduling result that applies
// directly to the five staggered ring runners.
#pragma once

#include "nanlm/nan16.hpp"

#include <cstdint>
#include <vector>

namespace nanlm {

std::vector<std::uint8_t> bit_reversed_wake_slots(int count);
std::vector<std::uint8_t> linear_wake_slots(int count);
std::vector<std::uint8_t> random_wake_slots(int count, std::uint64_t seed);

// Largest circular gap between occupied slots.
int max_wake_gap(const std::vector<std::uint8_t>& slots, int slot_count = 256);
int ideal_max_gap(int count, int slot_count = 256);

// A 16-bit palindromic tick is a self-dual epoch marker. There are 256 of
// them, irregularly spaced; they are markers, not a regular clock.
inline bool is_palindromic_tick(std::uint64_t tick) {
    return (tick & 0xFFFFu) == reverse16(static_cast<std::uint16_t>(tick & 0xFFFFu));
}

std::vector<std::uint16_t> palindromic_epochs();

} // namespace nanlm
