#include "nanlm/atomic.hpp"
#include "nanlm/global.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    AtomicClock c;
    CHECK(!c.valid());
    const SnapshotStamp unknown = c.stamp(7, 1);
    CHECK(!unknown.valid);
    CHECK_EQ(unknown.logical_tick, 7u);
    CHECK_EQ(unknown.phase, 1u);
    CHECK_EQ(unknown.uncertainty_ns, ~0ull);

    AtomicAnchor a;
    a.wall_ns = 1793860000000000000ull;
    a.uncertainty_ns = 500000000ull;
    a.captured_at_ns = 1793860001000000000ull;
    a.source_mask = 0b101;
    a.valid = true;
    c.set(a);
    CHECK(c.valid());
    const SnapshotStamp s = c.stamp(42, 0);
    CHECK(s.valid);
    CHECK_EQ(s.wall_ns, a.wall_ns);
    CHECK_EQ(s.uncertainty_ns, a.uncertainty_ns);
    CHECK_EQ(s.logical_tick, 42u);
    CHECK_EQ(s.phase, 0u);
    CHECK(s.anchor_id != 0);
    CHECK(c.digest() == a.digest());

    AtomicAnchor b = a;
    b.wall_ns += 1;
    CHECK(!(b.digest() == a.digest()));

    GlobalTopology g(0x1234);
    g.set_atomic_anchor(a);
    const SnapshotStamp gs = g.stamp_snapshot();
    CHECK(gs.valid);
    CHECK_EQ(gs.wall_ns, a.wall_ns);
    CHECK_EQ(gs.logical_tick, g.clock().tick());
    CHECK_EQ(gs.phase, static_cast<std::uint8_t>(g.clock().phase()));

    return test_done("atomic anchor and snapshot stamps");
}
