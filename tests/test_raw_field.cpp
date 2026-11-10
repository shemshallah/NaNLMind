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

    // Exact T=1 expectation under the non-identity matrices: context = v,
    // h = x + Wout v, output = h + W2 tanh(W1 h).
    auto linear = [](const float* w, const float* x, float* y,
                     std::size_t rows, std::size_t cols) {
        for (std::size_t r = 0; r < rows; ++r) {
            float sum = 0.0f;
            for (std::size_t c = 0; c < cols; ++c) {
                sum += w[r * cols + c] * x[c];
            }
            y[r] = sum;
        }
    };
    std::array<float, 8> q{}, k{}, v{}, projected{}, h{}, mlp{};
    std::array<float, 16> hidden{};
    linear(weights.wq.data(), one_token[0].data(), q.data(), 8, 8);
    linear(weights.wk.data(), one_token[0].data(), k.data(), 8, 8);
    linear(weights.wv.data(), one_token[0].data(), v.data(), 8, 8);
    linear(weights.wout.data(), v.data(), projected.data(), 8, 8);
    for (std::size_t d = 0; d < 8; ++d) {
        h[d] = one_token[0][d] + projected[d];
    }
    linear(weights.w1.data(), h.data(), hidden.data(), 16, 8);
    for (float& value : hidden) value = std::tanh(value);
    linear(weights.w2.data(), hidden.data(), mlp.data(), 8, 16);
    CHECK(vm.causal_trunk(one_token, weights, one_feature));
    CHECK(std::fabs(one_feature[0] - (h[0] + mlp[0])) < 2e-3f);

    // The supported 256-token context scale.  The input, scores, values and
    // weights must remain within their fixed guest regions.
    causal_tokens.resize(256);
    for (std::size_t tkn = 48; tkn < 256; ++tkn) {
        std::array<float, kRawFeatureDim> v{};
        for (std::size_t d = 0; d < kRawFeatureDim; ++d) {
            v[d] = 0.05f + 0.001f * static_cast<float>((tkn + d) % 17);
        }
        causal_tokens[tkn] = v;
    }
    CHECK(vm.causal_trunk(causal_tokens, weights, causal_feature));
    CHECK(std::isfinite(causal_feature[0]));

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

    // Raw local credit update for Wout/W1/W2 after a readout step.
    CHECK(vm.trunk_credit(1, 0, 0.05f));
    // QKV credit uses the last fixed-trunk forward.  T=8 makes the softmax
    // gradient non-trivial for Wq/Wk as well as Wv.
    CHECK(vm.causal_trunk(causal_tokens, weights, causal_feature));
    causal_tokens.resize(8);
    CHECK(vm.causal_trunk(causal_tokens, weights, causal_feature));
    const float before_qkv_credit = causal_feature[0];
    std::array<float, kRawFeatureDim> target_row{};
    std::array<float, kRawFeatureDim> wrong_row{};
    target_row[0] = 1.0f;
    wrong_row[0] = -1.0f;
    CHECK(vm.set_readout_row(1, target_row));
    CHECK(vm.set_readout_row(0, wrong_row));

    // Functional QKV credit update: the raw guest must change at least one
    // Q/K/V coefficient and the cached forward must see the update.
    TrunkWeights qkv_before{};
    CHECK(vm.read_trunk_weights(qkv_before));
    CHECK(vm.qkv_credit(1, 0, 0.5f));
    TrunkWeights qkv_after{};
    CHECK(vm.read_trunk_weights(qkv_after));
    bool qkv_changed = false;
    for (std::size_t i = 0; i < qkv_before.wq.size(); ++i) {
        if (std::fabs(qkv_before.wq[i] - qkv_after.wq[i]) > 1e-6f ||
            std::fabs(qkv_before.wk[i] - qkv_after.wk[i]) > 1e-6f ||
            std::fabs(qkv_before.wv[i] - qkv_after.wv[i]) > 1e-6f) {
            qkv_changed = true;
        }
    }
    CHECK(qkv_changed);
    CHECK(vm.causal_trunk_cached(causal_tokens, causal_feature));
    CHECK(std::fabs(causal_feature[0] - before_qkv_credit) > 1e-7f);

    // Native readout training over the raw trunk feature.
    vm.reset_readout();
    bool correct = true;
    float target_score = 0.0f, best_wrong = 0.0f, loss = 0.0f;
    CHECK(vm.readout_train(one_token, weights, 1, 0.5f,
                           correct, target_score, best_wrong, loss));
    CHECK(!correct);
    CHECK(loss >= 0.0f);
    CHECK(vm.readout_train(one_token, weights, 1, 0.0f,
                           correct, target_score, best_wrong, loss));
    CHECK(correct);
    CHECK(target_score > best_wrong);

    // Wide causal trunk: runtime D/H and 1024-token context.  Use a
    // diagonal core so the expected one-token result is checkable.
    WideTrunkWeights wide;
    wide.dim = 16;
    wide.hidden = 64;
    wide.wq.assign(wide.dim * wide.dim, 0.0f);
    wide.wk = wide.wq;
    wide.wv = wide.wq;
    wide.wout = wide.wq;
    for (std::size_t i = 0; i < wide.dim; ++i) {
        wide.wq[i * wide.dim + i] = 1.0f;
        wide.wk[i * wide.dim + i] = 1.0f;
        wide.wv[i * wide.dim + i] = 1.0f;
        wide.wout[i * wide.dim + i] = 1.0f;
    }
    wide.w1.assign(wide.hidden * wide.dim, 0.0f);
    wide.w2.assign(wide.dim * wide.hidden, 0.0f);
    for (std::size_t i = 0; i < wide.dim; ++i) {
        wide.w1[i * wide.dim + i] = 1.0f;
        wide.w2[i * wide.hidden + i] = 1.0f;
    }
    std::vector<float> wide_tokens(wide.dim);
    for (std::size_t d = 0; d < wide.dim; ++d) {
        wide_tokens[d] = 0.25f + 0.01f * static_cast<float>(d);
    }
    std::vector<float> wide_out;
    CHECK(vm.causal_trunk_wide(wide_tokens, 1, wide, wide_out));
    CHECK_EQ(wide_out.size(), wide.dim);
    const float wide_expected = 2.0f * wide_tokens[0] +
                                std::tanh(2.0f * wide_tokens[0]);
    CHECK(std::fabs(wide_out[0] - wide_expected) < 2e-3f);

    wide_tokens.assign(1024 * wide.dim, 0.0f);
    for (std::size_t tkn = 0; tkn < 1024; ++tkn) {
        for (std::size_t d = 0; d < wide.dim; ++d) {
            wide_tokens[tkn * wide.dim + d] =
                0.1f + 0.001f * static_cast<float>((tkn + d) % 13);
        }
    }
    CHECK(vm.causal_trunk_wide(wide_tokens, 1024, wide, wide_out));
    CHECK_EQ(wide_out.size(), wide.dim);
    CHECK(std::isfinite(wide_out[0]));

    std::vector<float> wide_target(wide.dim, 0.0f);
    std::vector<float> wide_wrong(wide.dim, 0.0f);
    wide_target[0] = 1.0f;
    wide_wrong[0] = -1.0f;
    CHECK(vm.set_wide_readout_row(1, wide_target.data(), wide.dim));
    CHECK(vm.set_wide_readout_row(0, wide_wrong.data(), wide.dim));
    const float wide_before_credit = wide_out[0];
    CHECK(vm.qkv_credit_wide(1, 0, 0.5f));
    CHECK(vm.causal_trunk_wide_cached(wide_tokens, 1024, wide.dim, wide_out));
    CHECK(std::fabs(wide_out[0] - wide_before_credit) > 1e-7f);

    // Readout-only path: the same update without recomputing the trunk.
    vm.reset_readout();
    std::array<float, kRawFeatureDim> cached_feature{};
    CHECK(vm.causal_trunk(one_token, weights, cached_feature));
    CHECK(vm.readout_only(cached_feature, 1, 0.5f, correct,
                          target_score, best_wrong, loss));
    CHECK(!correct);
    CHECK(vm.readout_only(cached_feature, 1, 0.0f, correct,
                          target_score, best_wrong, loss));
    CHECK(correct);

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
    CHECK(feature_field.configure(wide.dim, 4, 8));
    feature_field.seed(0x1234);
    for (std::size_t i = 0; i < wide.dim; ++i) {
        q16[i] = static_cast<std::int32_t>(std::lrintf(wide_out[i] * 65536.0f));
    }
    CHECK(feature_field.forward(q16, feature_result));
    CHECK_EQ(feature_result.count, SparseField::kActive);

    return test_done("raw NaN16 field VM bridge");
}
