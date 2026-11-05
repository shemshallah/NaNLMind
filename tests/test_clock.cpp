#include "nanlm/clock.hpp"
#include "nanlm/global.hpp"
#include "nanlm/head.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    TemporalClock c;
    CHECK_EQ(c.tick(), 0u);
    CHECK(c.future() == ClockState::Halt);
    CHECK(c.past_rewrite() == ClockState::Halt);
    CHECK(c.signal() == ClockSignal::QnanPositive);
    CHECK_EQ(c.signal_bits(), TemporalClock::kQnanPositive);
    CHECK_EQ(c.event_count(), 1u);

    c.step();
    CHECK(c.future() == ClockState::Halt);
    CHECK(c.past_rewrite() == ClockState::Loop);
    CHECK(c.contradiction());
    CHECK(c.signal() == ClockSignal::QnanPositive);
    CHECK_EQ(c.tick(), 1u);
    CHECK_EQ(c.history_count(), 2u);

    c.step();
    CHECK(c.future() == ClockState::Loop);
    CHECK(c.past_rewrite() == ClockState::Halt);
    CHECK(c.contradiction());
    CHECK(c.signal() == ClockSignal::SnanNegative);
    CHECK_EQ(c.signal_bits(), TemporalClock::kSnanNegative);
    CHECK_EQ(c.tick(), 2u);

    c.step();
    CHECK(c.past_rewrite() == ClockState::Loop);
    CHECK_EQ(c.tick(), 3u);

    std::uint64_t start = 0, length = 0;
    CHECK(c.cycle(start, length));
    CHECK_EQ(length, 2u);
    CHECK(start < c.history_count());

    TemporalClock e;
    TemporalClock f;
    CHECK(e.digest() == f.digest());
    TemporalClock d;
    d.run(10);
    std::uint64_t s2 = 0, l2 = 0;
    CHECK(d.cycle(s2, l2));
    CHECK_EQ(l2, 2u);
    CHECK(d.event_count() > 10u);

    TemporalClock a;
    for (int i = 0; i < 5; ++i) a.step();
    TemporalClock b;
    CHECK(b.observe(a.stamp()));
    CHECK(b.stamp() == a.stamp());
    CHECK(b.digest() == a.digest());
    LogicalStamp stamp1{1, 0};
    LogicalStamp stamp2{1, 1};
    LogicalStamp stamp3{2, 0};
    CHECK(stamp1 < stamp2);
    CHECK(stamp2 < stamp3);
    CHECK(!(stamp1 == a.stamp()));

    // Exact event names and directions.
    CHECK_EQ(std::string(clock_state_name(ClockState::Halt)), std::string("HALT"));
    CHECK_EQ(std::string(clock_signal_name(ClockSignal::SnanNegative)), std::string("-sNaN"));
    CHECK_EQ(std::string(clock_direction_name(ClockDirection::Past)), std::string("LE/PAST"));
    CHECK_EQ(std::string(clock_event_name(ClockEventKind::Contradiction)),
             std::string("CONTRADICTION"));

    // The clock is a field of the one object and is included in the digest.
    GlobalTopology g(0x1234);
    const Hash256 before = g.global_digest();
    g.clock().step();
    CHECK_EQ(g.clock().tick(), 1u);
    CHECK(!(g.global_digest() == before));

    // Runner handoff is stamped by the clock.
    HeadArray heads = g.root_heads();
    HeadRunner runner(heads, PageId::root(), &g.temporal(), &g.clock());
    HeadToken token;
    token.payload = 0x21;
    token.epoch = 0;
    token.phase = 0;
    const std::uint32_t clock_phase = g.clock().phase();
    const RunnerResult r = runner.run(0, token);
    CHECK(r.ok);
    CHECK(g.clock().tick() >= 2u);
    CHECK(r.out.epoch >= 2u);
    CHECK_EQ(r.out.phase, static_cast<std::uint32_t>(((clock_phase << 8) + 0x21u) & 0xFFFFu));
    CHECK_EQ(heads.history(0).size(), 1u);

    return test_done("temporal clock");
}
