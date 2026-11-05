#include "nanlm/atomic.hpp"

namespace nanlm {

Hash256 AtomicAnchor::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'A', 'T', 'O', 'M', '1'};
    h.update(tag, sizeof(tag));
    h.update(&wall_ns, sizeof(wall_ns));
    h.update(&uncertainty_ns, sizeof(uncertainty_ns));
    h.update(&captured_at_ns, sizeof(captured_at_ns));
    h.update(&source_mask, sizeof(source_mask));
    const std::uint8_t v = valid ? 1u : 0u;
    h.update(&v, sizeof(v));
    return h.final();
}

SnapshotStamp AtomicClock::stamp(std::uint64_t tick, std::uint8_t phase) const {
    SnapshotStamp s;
    s.logical_tick = tick;
    s.phase = phase;
    s.valid = anchor_.valid;
    if (anchor_.valid) {
        s.wall_ns = anchor_.wall_ns;
        s.uncertainty_ns = anchor_.uncertainty_ns;
        const Hash256 d = anchor_.digest();
        s.anchor_id = static_cast<std::uint32_t>(d[0]) |
                      (static_cast<std::uint32_t>(d[1]) << 8) |
                      (static_cast<std::uint32_t>(d[2]) << 16) |
                      (static_cast<std::uint32_t>(d[3]) << 24);
    } else {
        s.wall_ns = 0;
        s.uncertainty_ns = ~0ull; // unknown
    }
    return s;
}

} // namespace nanlm
