#include "nanlm/head.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    auto u = std::make_unique<Universe>(0x1234);
    HeadArray heads(*u, PageId::root());
    HeadView h = heads.at(9);

    h.scratch().clear();
    h.reset_boolean_learner();
    HeadFrame f = capture_head(h);

    // Forward computation: train, change phase, advance transform, write scratch.
    for (int i = 0; i < 20; ++i) {
        for (std::uint32_t a = 0; a < 2; ++a) {
            for (std::uint32_t b = 0; b < 2; ++b) {
                h.train_boolean(a, b, (a & b) != 0);
            }
        }
    }
    h.set_phase(HeadPhase::SignalingNegative);
    h.advance_transform_phase();
    h.note_self_model_error(40000, 32768, 3);
    h.note_scratch_used(300);
    h.scratch().work()[100] = 0xA5;
    capture_after(f, h);

    CHECK(h.boolean_rule() == 8u);
    CHECK(h.phase() == HeadPhase::SignalingNegative);

    // Inverse: restore the exact before-frame.
    restore_before(h, f);
    CHECK_EQ(h.boolean_rule(), f.before_cell.rule);
    CHECK_EQ(h.boolean_mask(), f.before_cell.ops);
    CHECK(h.phase() == phase_of(f.before_cell.s_plus().far_type()));
    CHECK_EQ(h.self_error(), f.before_head.self_error);
    CHECK_EQ(h.scratch_used(), f.before_head.scratch_used);
    CHECK_EQ(h.scratch().work()[100], f.before_scratch.work()[100]);
    CHECK(heads.verify());

    // Re-applying the after-frame is the forward direction again.
    restore_after(h, f);
    CHECK_EQ(h.boolean_rule(), f.after_cell.rule);
    CHECK_EQ(h.scratch().work()[100], 0xA5u);
    CHECK(heads.verify());

    return test_done("inverse head frames");
}
