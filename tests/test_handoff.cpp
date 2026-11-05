#include "nanlm/global.hpp"
#include "nanlm/handoff.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    HeadMap map(6);
    CHECK(map.valid());
    CHECK_EQ(map.runners(), 6u);
    std::uint32_t total = 0;
    for (std::uint8_t r = 0; r < 6; ++r) {
        const auto& hs = map.heads_for(r);
        CHECK(!hs.empty());
        total += static_cast<std::uint32_t>(hs.size());
        for (std::uint8_t h : hs) CHECK_EQ(map.owner_of(h), r);
    }
    CHECK_EQ(total, 256u);
    CHECK_EQ(map.heads_for(0).size(), 43u);
    CHECK_EQ(map.heads_for(4).size(), 42u);

    HandoffRound round(7, 6);
    CHECK(!round.ready());
    CHECK(!round.complete());

    std::vector<std::vector<HeadPacket>> by_runner(6);
    for (std::uint8_t r = 0; r < 6; ++r) {
        for (std::uint8_t h : map.heads_for(r)) {
            HeadPacket p;
            p.head = h;
            p.epoch = 7;
            p.phase = static_cast<std::uint32_t>(h) * 0x0101u;
            p.transform_phase = static_cast<std::uint8_t>(h & 3u);
            p.self_error = h;
            p.scratch_used = h;
            p.state_hash = 0x1000u + h;
            p.output[0] = h;
            by_runner[r].push_back(p);
        }
        CHECK(round.prepare(r, by_runner[r]));
    }
    CHECK(round.ready());
    CHECK(!round.complete());
    CHECK(round.verify());
    CHECK_EQ(round.all_packets().size(), 256u);

    for (std::uint8_t r = 0; r < 6; ++r) CHECK(round.commit(r));
    CHECK(round.complete());

    // A stale epoch is rejected.
    HandoffRound stale(8, 6);
    CHECK(!stale.prepare(0, by_runner[0]));
    CHECK(!stale.verify());

    // Wrong owner is rejected.
    HandoffRound wrong(7, 6);
    std::vector<HeadPacket> bad;
    HeadPacket p;
    p.head = 1;
    p.epoch = 7;
    bad.push_back(p);
    CHECK(!wrong.prepare(0, bad)); // head 1 belongs to runner 1

    // Duplicate prepare is rejected.
    CHECK(!round.prepare(0, by_runner[0]));

    // The round is recorded as one ledger event in the one history.
    GlobalTopology g(0x1234);
    std::string err;
    CHECK(record_handoff(g, round, 1, &err));
    CHECK_EQ(g.ledger().size(), 1u);
    CHECK_EQ(g.ledger().at(0).epoch, 7u);
    CHECK_EQ(g.ledger().at(0).kind, kEventHandoff);
    CHECK(g.ledger().verify());

    // An incomplete round is not recorded.
    HandoffRound incomplete(9, 6);
    CHECK(!record_handoff(g, incomplete, 1, &err));
    CHECK_EQ(g.ledger().size(), 1u);

    return test_done("6-runner synchronous head handoff");
}
