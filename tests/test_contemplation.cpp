#include "nanlm/head.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    auto u = std::make_unique<Universe>(0x1234);
    HeadArray heads(*u, PageId::root());
    HeadView h = heads.at(11);
    h.reset_boolean_learner();
    const auto before_rule = h.boolean_rule();
    const auto before_phase = h.phase();

    const HeadMutation mutation = [](HeadView& v) {
        for (int rep = 0; rep < 20; ++rep) {
            for (std::uint32_t a = 0; a < 2; ++a) {
                for (std::uint32_t b = 0; b < 2; ++b) {
                    v.train_boolean(a, b, (a & b) != 0);
                }
            }
        }
        v.set_phase(HeadPhase::SignalingNegative);
        v.advance_transform_phase();
        v.note_scratch_used(321);
        v.scratch().work()[77] = 0x5A;
    };

    // Contemplate without commit: forward is evaluated, inverse restores the
    // exact before-frame, and the head stays at before.
    const ContemplationResult r1 = contemplate(h, mutation, false);
    CHECK(r1.ok);
    CHECK(r1.inverse_ok);
    CHECK(!r1.committed);
    CHECK(r1.forward_hash != r1.inverse_hash);
    CHECK_EQ(h.boolean_rule(), before_rule);
    CHECK(h.phase() == before_phase);
    CHECK_EQ(h.scratch_used(), 0u);
    CHECK_EQ(h.scratch().work()[77], 0u);
    CHECK(heads.verify());

    // Contemplate with commit: after-frame is kept.
    const ContemplationResult r2 = contemplate(h, mutation, true);
    CHECK(r2.ok);
    CHECK(r2.inverse_ok);
    CHECK(r2.committed);
    CHECK_EQ(h.boolean_rule(), 8u); // AND
    CHECK(h.phase() == HeadPhase::SignalingNegative);
    CHECK_EQ(h.scratch_used(), 321u);
    CHECK_EQ(h.scratch().work()[77], 0x5Au);
    CHECK(heads.verify());

    // Explicit frame computation: forward -> reverse -> forward.
    HeadFrame f = capture_head(h);
    h.set_phase(HeadPhase::QuietPositive);
    h.scratch().work()[77] = 0x11;
    capture_after(f, h);
    compute_reverse_frame(h, f);
    CHECK(h.phase() == HeadPhase::SignalingNegative);
    CHECK_EQ(h.scratch().work()[77], 0x5Au);
    compute_forward_frame(h, f);
    CHECK(h.phase() == HeadPhase::QuietPositive);
    CHECK_EQ(h.scratch().work()[77], 0x11u);
    CHECK(heads.verify());

    return test_done("contemplation and reverse-frame computation");
}
