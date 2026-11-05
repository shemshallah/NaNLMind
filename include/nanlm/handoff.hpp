// Synchronous head handoff across the 6-runner ring.
//
// A HeadMap assigns every one of the 256 palindromic heads to exactly one
// runner. A HandoffRound is a two-phase barrier:
//
//   prepare: each runner publishes the packets for the heads it owns
//   commit:  each runner confirms its share after the packets validate
//
// The epoch is the logical clock tick. All packets in a round must carry the
// same epoch. No runner starts before the previous round is complete.
#pragma once

#include "nanlm/nan16.hpp"
#include "nanlm/sha256.hpp"

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace nanlm {

class GlobalTopology;

inline constexpr std::uint8_t kEventHandoff = 6;
inline constexpr std::uint8_t kMaxRunners = 6;

struct HeadPacket {
    std::uint8_t head = 0;
    std::uint64_t epoch = 0;
    std::uint32_t phase = 0;          // Q16.16 head phase
    std::uint8_t transform_phase = 0; // I/B/BR/R, 2 bits
    std::uint16_t self_error = 0;
    std::uint16_t scratch_used = 0;
    std::uint64_t state_hash = 0;
    std::array<std::uint8_t, 32> output{};
};

class HeadMap {
public:
    explicit HeadMap(std::uint8_t runners = kMaxRunners);

    bool valid() const { return valid_; }
    std::uint8_t runners() const { return runners_; }
    const std::vector<std::uint8_t>& heads_for(std::uint8_t runner) const;
    std::uint8_t owner_of(std::uint8_t head) const;
    const std::vector<std::uint8_t>& owners() const { return owner_; }
    std::string error() const { return error_; }

private:
    std::uint8_t runners_ = kMaxRunners;
    bool valid_ = false;
    std::string error_;
    std::vector<std::vector<std::uint8_t>> heads_;
    std::vector<std::uint8_t> owner_;
};

class HandoffRound {
public:
    HandoffRound(std::uint64_t epoch, std::uint8_t runners = kMaxRunners);

    std::uint64_t epoch() const { return epoch_; }
    std::uint8_t runners() const { return runners_; }

    bool prepare(std::uint8_t runner, const std::vector<HeadPacket>& packets,
                 std::string* error = nullptr);
    bool commit(std::uint8_t runner, std::string* error = nullptr);
    bool ready() const;
    bool complete() const;

    const std::vector<HeadPacket>& packets(std::uint8_t runner) const;
    std::vector<HeadPacket> all_packets() const;
    bool verify(std::string* error = nullptr) const;
    Hash256 digest() const;

private:
    std::uint64_t epoch_ = 0;
    std::uint8_t runners_ = kMaxRunners;
    std::array<std::vector<HeadPacket>, kMaxRunners> packets_{};
    std::array<bool, kMaxRunners> prepared_{};
    std::array<bool, kMaxRunners> committed_{};
    std::string error_;
};

// Append the round to the one global ledger. The before/after hashes are the
// round digest; the epoch is the round epoch.
bool record_handoff(GlobalTopology& topology, const HandoffRound& round,
                    std::uint8_t actor, std::string* error = nullptr);

} // namespace nanlm
