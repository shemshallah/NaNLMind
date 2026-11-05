// Wall-time anchor and snapshot stamps.
//
// The logical clock orders state. The atomic anchor gives a wall-time estimate
// with an explicit uncertainty for snapshots and lease expiry. It is metadata,
// never a state-ordering authority.
#pragma once

#include "nanlm/sha256.hpp"

#include <cstdint>

namespace nanlm {

struct AtomicAnchor {
    std::uint64_t wall_ns = 0;
    std::uint64_t uncertainty_ns = 0;
    std::uint64_t captured_at_ns = 0;
    std::uint32_t source_mask = 0;
    bool valid = false;

    Hash256 digest() const;
};

struct SnapshotStamp {
    std::uint64_t wall_ns = 0;
    std::uint64_t uncertainty_ns = 0;
    std::uint64_t logical_tick = 0;
    std::uint8_t phase = 0;
    std::uint32_t anchor_id = 0;
    bool valid = false;
};

class AtomicClock {
public:
    void set(const AtomicAnchor& anchor) { anchor_ = anchor; }
    void clear() { anchor_ = AtomicAnchor{}; }
    const AtomicAnchor& anchor() const { return anchor_; }
    bool valid() const { return anchor_.valid; }
    SnapshotStamp stamp(std::uint64_t tick, std::uint8_t phase) const;
    Hash256 digest() const { return anchor_.digest(); }

private:
    AtomicAnchor anchor_{};
};

} // namespace nanlm
