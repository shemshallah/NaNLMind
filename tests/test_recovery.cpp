#include "nanlm/frame_sync.hpp"
#include "nanlm/global.hpp"
#include "nanlm/handoff.hpp"
#include "nanlm/head.hpp"
#include "test_util.hpp"

using namespace nanlm;

namespace {
std::vector<HeadPacket> packets_for(const HeadMap& map, std::uint8_t slot,
                                    std::uint64_t epoch) {
    std::vector<HeadPacket> out;
    for (std::uint8_t h : map.heads_for(slot)) {
        HeadPacket p;
        p.head = h;
        p.epoch = epoch;
        p.phase = static_cast<std::uint32_t>(h) * 0x0101u;
        p.transform_phase = static_cast<std::uint8_t>(h & 3u);
        p.state_hash = 0x5000u + h;
        p.output[0] = h;
        out.push_back(p);
    }
    return out;
}
} // namespace

int main() {
    GlobalTopology g(0x1234);
    HeadArray heads = g.root_heads();
    HeadMap map(6);
    HandoffRound round(10, 6);

    // Five slots prepare; the sixth is dropped.
    for (std::uint8_t r = 0; r < 5; ++r) {
        CHECK(round.prepare(r, packets_for(map, r, 10)));
    }
    CHECK(!round.ready());
    CHECK(!round.verify());

    // Forward +4 and rollback -3 meet at frame 4; the next runner wins.
    const FrameMeeting meet = FrameSync::meet({0, 0, +4, 0}, {1, 7, -3, 0}, 2);
    CHECK(meet.ok);
    CHECK_EQ(meet.frame, 4);
    CHECK_EQ(meet.winner, 2u);

    // Inverse restoration of a head that was touched before the drop.
    HeadView h = heads.at(3);
    const HeadFrame frame = capture_head(h);
    h.set_phase(HeadPhase::SignalingNegative);
    h.advance_transform_phase();
    h.scratch().work()[42] = 0x7F;
    restore_before(h, frame);
    CHECK(h.phase() == phase_of(frame.before_cell.s_plus().far_type()));
    CHECK_EQ(h.scratch().work()[42], frame.before_scratch.work()[42]);

    // The missing slot rejoins; the round verifies and commits once.
    CHECK(round.prepare(5, packets_for(map, 5, 10)));
    CHECK(round.ready());
    CHECK(round.verify());
    for (std::uint8_t r = 0; r < 6; ++r) CHECK(round.commit(r));
    CHECK(round.complete());
    std::string err;
    CHECK(record_handoff(g, round, 1, &err));
    CHECK_EQ(g.ledger().size(), 1u);
    CHECK_EQ(g.ledger().at(0).epoch, 10u);
    CHECK(g.ledger().verify());

    return test_done("dropped-slot recovery and reverse frame");
}
