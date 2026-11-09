#include "nanlm/raw_field.hpp"
#include "nanlm/sparse_field.hpp"
#include "test_util.hpp"

#include <cmath>

#include <array>

using namespace nanlm;

int main() {
    RawFieldVM vm("build/field_driver.nan");
    CHECK(vm.ready());
    if (!vm.ready()) return test_done("raw NaN16 field VM bridge");

    RawProposalResult proposal;
    CHECK(vm.proposal(0x0001, 0x0003, {0x0001, 0x0002, 0x0002},
                      0, 0, true, proposal));
    CHECK_EQ(proposal.votes, 6u);
    CHECK(proposal.accepted);
    CHECK_EQ(proposal.candidate_mask, 0x0002u);
    CHECK_EQ(proposal.candidate_rule, 1u);

    std::array<std::uint8_t, kTriadCount> masks{};
    for (std::size_t i = 0; i < 43; ++i) masks[i] = 6;
    std::uint16_t count = 0;
    bool field_ok = false;
    CHECK(vm.field_vote(masks, count, field_ok));
    CHECK_EQ(count, 43u);
    CHECK(field_ok);

    std::array<std::uint16_t, kTriadMemberCount> phases{};
    std::int32_t coherence = 0;
    CHECK(vm.coherence(phases, coherence));
    CHECK(coherence >= 65500);

    std::array<std::uint16_t, 6> remap_masks = {
        0x8000, 0, 0, 0x8000, 0, 0};
    bool improved = false;
    std::int32_t before = 0, after = 0;
    CHECK(vm.remap(remap_masks, 0, 0, true, improved, before, after));
    CHECK(improved);
    CHECK_EQ(before, 2);
    CHECK_EQ(after, 4);

    // Chart bridge: the guest decision changes only the proposer's mask and
    // updates the chart's integer credit fields.
    Universe universe;
    HeadArray heads(universe, PageId::root());
    CHECK(heads.at(3).set_boolean_mask(0x0001));
    CHECK(heads.at(4).set_boolean_mask(0x0002));
    CHECK(heads.at(5).set_boolean_mask(0x0002));
    RawProposalResult chart_result;
    CHECK(vm.propose(universe, heads, 3, 0x0003, 0, 0, true, chart_result));
    CHECK(chart_result.accepted);
    CHECK_EQ(heads.at(3).boolean_mask(), 0x0002u);
    CHECK_EQ(heads.at(4).boolean_mask(), 0x0002u);
    CHECK_EQ(heads.at(5).boolean_mask(), 0x0002u);
    CHECK_EQ(universe.head_credit()[3], 1);
    CHECK_EQ(universe.triad_credit()[1], 1);

    // General remap bridge: swap a member between triads only when the raw
    // guest says the combined majority objective improves.
    Universe map_universe;
    HeadArray map_heads(map_universe, PageId::root());
    CHECK(map_heads.at(3).set_boolean_mask(0x8000));
    CHECK(map_heads.at(4).set_boolean_mask(0x0000));
    CHECK(map_heads.at(5).set_boolean_mask(0x0000));
    CHECK(map_heads.at(6).set_boolean_mask(0x8000));
    CHECK(map_heads.at(7).set_boolean_mask(0x0000));
    CHECK(map_heads.at(8).set_boolean_mask(0x0000));
    bool chart_improved = false;
    std::int32_t chart_before = 0, chart_after = 0;
    CHECK(vm.remap_chart(map_universe, map_heads, 1, 1, 2, 0, 0, 0, true,
                         chart_improved, chart_before, chart_after));
    CHECK(chart_improved);
    CHECK_EQ(map_universe.triad_of()[6], 1);
    CHECK_EQ(map_universe.triad_slot()[6], 1);
    CHECK_EQ(map_universe.triad_of()[4], 2);
    CHECK_EQ(map_universe.triad_slot()[4], 0);
    CHECK_EQ(map_universe.triad_credit()[1], 1);
    CHECK_EQ(map_universe.triad_credit()[2], 1);

    // Deterministic autonomous scheduler: lowest-credit triads are tried.
    Universe auto_universe;
    HeadArray auto_heads(auto_universe, PageId::root());
    CHECK(auto_heads.at(3).set_boolean_mask(0x8000));
    CHECK(auto_heads.at(4).set_boolean_mask(0x0000));
    CHECK(auto_heads.at(5).set_boolean_mask(0x0000));
    CHECK(auto_heads.at(6).set_boolean_mask(0x8000));
    CHECK(auto_heads.at(7).set_boolean_mask(0x0000));
    CHECK(auto_heads.at(8).set_boolean_mask(0x0000));
    auto_universe.triad_credit()[1] = -5;
    auto_universe.triad_credit()[2] = -4;
    AutoRemapResult auto_result;
    CHECK(vm.auto_remap(auto_universe, auto_heads, 256, 0, 0, true,
                        auto_result));
    CHECK(auto_result.attempted);
    CHECK(auto_result.improved);
    CHECK_EQ(auto_result.triad_a, 1);
    CHECK_EQ(auto_result.triad_b, 2);
    CHECK_EQ(auto_result.slot_a, 1);
    CHECK_EQ(auto_result.slot_b, 0);
    CHECK_EQ(auto_universe.triad_of()[6], 1);
    CHECK_EQ(auto_universe.triad_of()[4], 2);

    // Raw hot-head scan: three hot individuals become one hot triad, and the
    // guest writes a unique 85x3 auto-mapping.
    std::array<std::int32_t, kTriadMemberCount> credits{};
    credits[3] = 100;
    credits[17] = 90;
    credits[99] = 80;
    HotTriheadResult hot;
    CHECK(vm.hot_triheads(credits, 10, hot));
    CHECK_EQ(hot.hot_heads, 3u);
    CHECK_EQ(hot.hot_triads, 1u);
    CHECK(!hot.field_hot);
    CHECK_EQ(hot.members[0], 3u);
    CHECK_EQ(hot.members[1], 17u);
    CHECK_EQ(hot.members[2], 99u);
    std::array<bool, kTriadMemberCount> seen{};
    for (std::uint8_t h : hot.members) {
        CHECK(h < kTriadMemberCount);
        CHECK(!seen[h]);
        seen[h] = true;
    }

    // 129 hot heads -> 43 complete hot triads -> global field flag.
    std::array<std::int32_t, kTriadMemberCount> many{};
    for (std::size_t i = 0; i < 129; ++i) many[i] = 50;
    CHECK(vm.hot_triheads(many, 10, hot));
    CHECK_EQ(hot.hot_heads, 129u);
    CHECK_EQ(hot.hot_triads, 43u);
    CHECK(hot.field_hot);

    // Chart bridge commits the raw mapping and reverses it for all heads.
    Universe hot_universe;
    HotTriheadResult mapped;
    CHECK(vm.hot_triheads(hot_universe, credits, 10, mapped));
    CHECK(mapped.mapped);
    CHECK_EQ(hot_universe.triad_members()[0], 3u);
    CHECK_EQ(hot_universe.triad_members()[1], 17u);
    CHECK_EQ(hot_universe.triad_members()[2], 99u);
    CHECK_EQ(hot_universe.triad_of()[3], 0u);
    CHECK_EQ(hot_universe.triad_of()[17], 0u);
    CHECK_EQ(hot_universe.triad_of()[99], 0u);
    CHECK_EQ(hot_universe.triad_slot()[99], 2u);

    // Raw two-token QKV/softmax/tanh feature feed into the native sparse
    // head/field bank.  Identity QKV is the P1 bridge point; learned matrices
    // replace it without changing the output contract.
    std::array<float, kRawFeatureDim> x0{};
    std::array<float, kRawFeatureDim> x1{};
    std::array<float, kRawFeatureDim> feature{};
    for (std::size_t i = 0; i < kRawFeatureDim; ++i) {
        x0[i] = 1.0f + static_cast<float>(i) * 0.125f;
        x1[i] = 0.5f - static_cast<float>(i) * 0.03125f;
    }
    CHECK(vm.micro_feature(x0, x1, feature));
    CHECK(std::isfinite(feature[0]));
    CHECK(std::fabs(feature[0]) <= 1.0f);

    // Learned QKV/MLP causal trunk: identity matrices first, then arbitrary
    // weights.  Context lengths 1, 8 and 48 exercise the causal loop.
    TrunkWeights weights;
    for (std::size_t i = 0; i < 64; ++i) {
        weights.wq[i] = (i / 8 == i % 8) ? 1.0f : 0.0f;
        weights.wk[i] = weights.wq[i];
        weights.wv[i] = weights.wq[i];
        weights.wout[i] = weights.wq[i];
    }
    for (std::size_t i = 0; i < 128; ++i) {
        weights.w1[i] = 0.0f;
        weights.w2[i] = 0.0f;
    }
    for (std::size_t i = 0; i < 8; ++i) {
        weights.w1[i * 8 + i] = 1.0f;   // 16x8: first 8 rows identity
        weights.w2[i * 16 + i] = 1.0f;  // 8x16: first 8 cols identity
    }
    std::vector<std::array<float, kRawFeatureDim>> causal_tokens;
    for (std::size_t tkn = 0; tkn < 8; ++tkn) {
        std::array<float, kRawFeatureDim> v{};
        for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
            v[d] = 0.25f + 0.03125f * static_cast<float>(tkn + d);
        }
        causal_tokens.push_back(v);
    }
    std::vector<std::array<float, kRawFeatureDim>> one_token = {causal_tokens[0]};
    std::array<float, kRawFeatureDim> one_feature{};
    CHECK(vm.causal_trunk(one_token, weights, one_feature));
    const float expected_one = 2.0f * causal_tokens[0][0] +
                               std::tanh(2.0f * causal_tokens[0][0]);
    CHECK(std::fabs(one_feature[0] - expected_one) < 1e-3f);

    std::array<float, kRawFeatureDim> causal_feature{};
    CHECK(vm.causal_trunk(causal_tokens, weights, causal_feature));
    const float identity_first = causal_feature[0];
    // Non-identity learned matrices must change the feature; this is not an
    // identity-only code path.
    for (std::size_t i = 0; i < weights.wq.size(); ++i) {
        weights.wq[i] = 0.01f * static_cast<float>((i % 7) + 1);
        weights.wk[i] = 0.02f * static_cast<float>((i % 5) + 1);
        weights.wv[i] = 0.03f * static_cast<float>((i % 3) + 1);
        weights.wout[i] = 0.04f * static_cast<float>((i % 4) + 1);
    }
    for (std::size_t i = 0; i < weights.w1.size(); ++i) {
        weights.w1[i] = 0.05f * static_cast<float>((i % 6) + 1);
        weights.w2[i] = 0.06f * static_cast<float>((i % 9) + 1);
    }
    CHECK(vm.causal_trunk(causal_tokens, weights, causal_feature));
    CHECK(std::isfinite(causal_feature[0]));
    CHECK(std::fabs(causal_feature[0] - identity_first) > 1e-5f);

    CHECK(std::isfinite(causal_feature[0]));
    causal_tokens.resize(48);
    for (std::size_t tkn = 8; tkn < 48; ++tkn) {
        std::array<float, kRawFeatureDim> v{};
        for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
            v[d] = 0.1f + 0.01f * static_cast<float>(tkn + d);
        }
        causal_tokens[tkn] = v;
    }
    CHECK(vm.causal_trunk(causal_tokens, weights, causal_feature));
    CHECK(std::isfinite(causal_feature[0]));

    Universe feature_universe;
    SparseField feature_field(feature_universe);
    CHECK(feature_field.configure(8, 2, 8));
    feature_field.seed(0xFEED);
    SparseField::Feature q16{};
    for (std::size_t i = 0; i < kRawFeatureDim; ++i) {
        q16[i] = static_cast<std::int32_t>(std::lrintf(feature[i] * 65536.0f));
    }
    SparseField::Result feature_result;
    CHECK(feature_field.forward(q16, feature_result));
    CHECK_EQ(feature_result.count, SparseField::kActive);
    for (std::size_t i = 0; i < kRawFeatureDim; ++i) {
        q16[i] = static_cast<std::int32_t>(std::lrintf(causal_feature[i] * 65536.0f));
    }
    CHECK(feature_field.forward(q16, feature_result));
    CHECK_EQ(feature_result.count, SparseField::kActive);

    return test_done("raw NaN16 field VM bridge");
}
