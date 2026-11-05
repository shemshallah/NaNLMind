#include "nanlm/global.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    GlobalTopology g(0x1234);
    const PageId root = PageId::root();
    GrowthPolicy policy;

    HeadArray heads = g.root_heads();
    HeadView h0 = heads.at(0);
    for (int i = 0; i < 3; ++i) h0.note_self_model_error(40000, policy.self_error_threshold,
                                                         policy.error_streak_required);
    CHECK_EQ(h0.self_error(), 40000);
    CHECK_EQ(h0.error_streak(), 3);
    CHECK(h0.should_grow(policy.self_error_threshold, policy.error_streak_required,
                         policy.scratch_threshold));

    const GrowthDecision d0 = g.evaluate_growth(root, 0, policy);
    CHECK(d0.grow);
    CHECK(d0.reason == "sustained self-model error");

    const PageId child0 = g.grow_head(root, 0, policy, 0x99);
    CHECK_EQ(child0.depth, 1u);
    CHECK_EQ(child0.path[0], 0u);
    CHECK(g.has_chart(child0));
    CHECK_EQ(g.chart_count(), 2u);
    CHECK(g.manifest().generation >= 1u);
    CHECK(g.ledger().verify());

    HeadArray root_heads = g.root_heads();
    CHECK(root_heads.at(0).has_child());
    CHECK(root_heads.at(0).self_error() == 0);
    CHECK(root_heads.at(0).error_streak() == 0);
    CHECK(!g.evaluate_growth(root, 0, policy).grow);

    // Scratch overflow path.
    HeadView h1 = root_heads.at(1);
    h1.note_scratch_used(768);
    CHECK(h1.should_grow(policy.self_error_threshold, policy.error_streak_required,
                         policy.scratch_threshold));
    const GrowthDecision d1 = g.evaluate_growth(root, 1, policy);
    CHECK(d1.grow);
    CHECK(d1.reason == "scratch high-water mark");
    const PageId child1 = g.grow_head(root, 1, policy);
    CHECK(g.has_chart(child1));
    CHECK_EQ(child1.path[0], 1u);

    // A chart at the policy depth limit cannot grow further.
    GrowthPolicy shallow = policy;
    shallow.max_depth = 1;
    HeadArray child_heads = g.head_array(child0);
    HeadView ch = child_heads.at(0);
    for (int i = 0; i < 3; ++i) ch.note_self_model_error(40000, shallow.self_error_threshold,
                                                         shallow.error_streak_required);
    const GrowthDecision deep = g.evaluate_growth(child0, 0, shallow);
    CHECK(!deep.grow);
    CHECK(deep.reason == "max depth reached");

    // No head remains over threshold after growth.
    CHECK_EQ(g.scan_growth(root, policy).size(), 0u);
    CHECK(g.root_heads().verify());

    return test_done("growth policy and child materialization");
}
