#include "nanlm/global.hpp"
#include "nanlm/head.hpp"
#include "test_util.hpp"

#include <bit>
#include <set>

using namespace nanlm;

int main() {
    auto u = std::make_unique<Universe>(0x1234);
    HeadArray heads(*u, PageId::root());
    std::string err;
    CHECK(heads.verify(&err));

    CHECK_EQ(HeadArray::size(), 256u);
    std::set<std::uint16_t> addresses;
    for (std::uint32_t i = 0; i < 256; ++i) {
        const auto idx = static_cast<std::uint8_t>(i);
        HeadView h = heads.at(idx);
        CHECK_EQ(h.index(), idx);
        CHECK_EQ(h.address().value, matrix_addr(idx, idx));
        CHECK(HeadAddress::valid(h.address().value));
        CHECK(addresses.insert(h.address().value).second);
        CHECK_EQ(heads.by_address(h.address().value).index(), idx);
        CHECK(h.record().fixed_addr == h.address().value);
        CHECK(h.cell().is_head());
        CHECK_EQ(h.links().total(), 255u);
        CHECK_EQ(h.links().row_count, static_cast<std::uint16_t>(255u - idx));
        CHECK_EQ(h.links().col_count, static_cast<std::uint16_t>(idx));
        CHECK(h.adjacent_to(static_cast<std::uint8_t>((idx + 1u) & 0xFFu)));
    }
    CHECK_EQ(addresses.size(), 256u);

    // Phase engine: QNaN/SNaN transitions are raw word classes.
    HeadView h3 = heads.at(3);
    const HeadPhase original = h3.phase();
    h3.set_phase(HeadPhase::SignalingNegative);
    CHECK(h3.phase() == HeadPhase::SignalingNegative);
    CHECK_EQ(h3.cell().s_plus().far_class(), 1u); // -sNaN
    CHECK_EQ(h3.cell().s_minus().far_class(), 1u);
    h3.set_phase(HeadPhase::QuietPositive);
    CHECK(h3.phase() == HeadPhase::QuietPositive);
    CHECK_EQ(h3.cell().s_plus().far_class(), 2u); // +qNaN
    h3.set_phase(original);
    CHECK(heads.verify(&err));

    // Per-head scratchpad: local + work areas are independent.
    HeadView hs = heads.at(5);
    hs.scratch().clear();
    hs.scratch().local()[0] = 0xA5;
    hs.scratch().work()[0] = 0x5A;
    CHECK_EQ(hs.scratch().local()[0], 0xA5u);
    CHECK_EQ(hs.scratch().work()[0], 0x5Au);
    CHECK_EQ(hs.scratch().bytes[256], 0x5Au);
    hs.scratch().clear();

    // Boolean self-modification: a capability-gated XOR of the 16-bit mask.
    HeadView hb = heads.at(6);
    const std::uint16_t mask_before = hb.boolean_mask();
    CHECK(hb.self_modify_boolean(0x000F));
    CHECK_EQ(hb.boolean_mask(), static_cast<std::uint16_t>(mask_before ^ 0x000Fu));
    CHECK_EQ(hb.boolean_rule(), static_cast<std::uint8_t>(std::countr_zero(hb.boolean_mask())));
    CHECK(hb.history().size() >= 1);
    CHECK(heads.verify(&err));

    // A read-only address cannot self-modify.
    CHECK(u->set_capability(hb.address().value, 0));
    CHECK(!hb.self_modify_boolean(0x0001));
    CHECK(u->set_capability(hb.address().value, 0x7));
    u->clear_address_dirty();
    CHECK(heads.verify(&err));

    // Runner handoff: follows the first topology edge and preserves the epoch.
    BidirectionalMemory temporal;
    HeadRunner runner(heads, PageId::root(), &temporal);
    HeadToken token;
    token.id = 7;
    token.payload = 0x42;
    token.epoch = 0;
    token.phase = 0x1000;
    const RunnerResult first = runner.run(0, token);
    CHECK(first.ok);
    CHECK_EQ(first.next, 1u); // first row edge of head 0 is (0,1)
    CHECK_EQ(first.out.epoch, 1u);
    CHECK_EQ(first.out.phase, 0x1042u);
    CHECK_EQ(temporal.size(), 1u);
    Ref future;
    CHECK(temporal.forward(Ref::from_bit({PageId::root(), matrix_addr(0, 0), 0, 0}), future, 0));
    CHECK(future == Ref::from_bit({PageId::root(), matrix_addr(1, 1), 0, 0}));
    CHECK_EQ(heads.history(0).size(), 1u);
    CHECK(heads.verify(&err));

    // A stale token is rejected.
    const RunnerResult stale = runner.run(0, token);
    CHECK(!stale.ok);

    // A chain of handoffs keeps epochs monotonic and phases bounded.
    HeadToken t = first.out;
    std::uint8_t at = first.next;
    for (int i = 0; i < 32; ++i) {
        const RunnerResult r = runner.run(at, t);
        CHECK(r.ok);
        CHECK(r.out.epoch == t.epoch + 1);
        CHECK(r.out.phase <= 0xFFFFu);
        at = r.next;
        t = r.out;
    }
    CHECK_EQ(temporal.size(), 33u);
    CHECK(heads.verify(&err));

    // History ring wraps and stays bounded.
    for (int i = 0; i < 64; ++i) {
        HeadToken x;
        x.epoch = 100 + i;
        x.payload = i;
        runner.run(0, x);
    }
    CHECK_EQ(heads.history(0).size(), HeadHistory::kCapacity);
    CHECK(heads.history_digest().size() == 32);

    // Runner-driven Boolean self-modification + scratchpad output.
    HeadView h7 = heads.at(7);
    const std::uint16_t h7_before = h7.boolean_mask();
    HeadToken patch;
    patch.epoch = 200;
    patch.payload = 0x8000000Fu;
    const RunnerResult patched = runner.run(7, patch);
    CHECK(patched.ok);
    CHECK(patched.modified);
    CHECK_EQ(h7.boolean_mask(), static_cast<std::uint16_t>(h7_before ^ 0x000Fu));
    CHECK_EQ(h7.scratch().local()[0], 0x0Fu);
    const std::uint8_t* sl = h7.scratch().local();
    const std::uint32_t sa = static_cast<std::uint32_t>(sl[0]) |
                             (static_cast<std::uint32_t>(sl[1]) << 8) |
                             (static_cast<std::uint32_t>(sl[2]) << 16) |
                             (static_cast<std::uint32_t>(sl[3]) << 24);
    const std::uint32_t sb = static_cast<std::uint32_t>(sl[4]) |
                             (static_cast<std::uint32_t>(sl[5]) << 8) |
                             (static_cast<std::uint32_t>(sl[6]) << 16) |
                             (static_cast<std::uint32_t>(sl[7]) << 24);
    const std::uint32_t expected = NanWord::eval_bool(h7.boolean_rule(), sa, sb);
    CHECK_EQ(h7.scratch().work()[4], static_cast<std::uint8_t>(expected & 0xFFu));
    CHECK(h7.history().size() >= 1);
    CHECK(heads.verify(&err));

    // Continual learning: accumulated Boolean evidence can decay away from
    // int16 saturation so a later relation batch can change the selected rule.
    HeadView adaptive = heads.at(9);
    adaptive.reset_boolean_learner();
    for (int i = 0; i < 32; ++i) adaptive.train_boolean(0, 0, true);
    const std::int16_t saturated_candidate = adaptive.boolean_score(1);
    CHECK(saturated_candidate > 0);
    adaptive.decay_boolean_scores(1);
    CHECK_EQ(adaptive.boolean_score(1), static_cast<std::int16_t>(saturated_candidate / 2));
    const std::int16_t decayed_score = adaptive.boolean_score(1);
    adaptive.train_boolean(0, 0, false);
    CHECK(adaptive.boolean_score(1) < decayed_score);
    CHECK(heads.verify(&err));

    // Serialization reconstructs the same head layer.
    const auto bytes = u->serialize();
    auto u2 = Universe::from_bytes(bytes.data(), bytes.size());
    CHECK(u2 != nullptr);
    if (u2) {
        HeadArray heads2(*u2, PageId::root());
        CHECK(heads2.verify(&err));
        CHECK(heads.digest() == heads2.digest());
    }

    // One global topology exposes the same array as a view, not a copy.
    GlobalTopology g(0x1234);
    HeadArray root = g.root_heads();
    CHECK(root.verify(&err));
    CHECK_EQ(root.size(), 256u);
    CHECK(root.universe().head(0).fixed_addr == matrix_addr(0, 0));

    return test_done("256-head palindromic layer");
}
