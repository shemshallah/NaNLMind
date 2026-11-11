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

    // CFT-gated local credit: positive residual passes the gate; negative
    // residual is rejected before any local update.
    bool cft_applied = false;
    CHECK(vm.cft_trunk_credit(1, 0, 32768, 0, 65536, 65536, 65536,
                              65536, 32768, cft_applied));
    CHECK(cft_applied);
    CHECK(vm.cft_trunk_credit(1, 0, 32768, 0, -65536, -65536, -65536,
                              65536, 32768, cft_applied));
    CHECK(!cft_applied);

    // Wide-path exact local-credit parity at a small D/H/T.  This compares
    // the raw wide QKV and output/MLP updates against the same float32
    // equations used by the autograd reference.
    WideTrunkWeights pwide;
    pwide.dim = 4;
    pwide.hidden = 8;
    pwide.wq.resize(16);
    pwide.wk.resize(16);
    pwide.wv.resize(16);
    pwide.wout.resize(16);
    pwide.w1.resize(32);
    pwide.w2.resize(32);
    for (std::size_t i = 0; i < 16; ++i) {
        pwide.wq[i] = 0.01f * static_cast<float>((i % 5) + 1);
        pwide.wk[i] = 0.02f * static_cast<float>((i % 3) + 1);
        pwide.wv[i] = 0.03f * static_cast<float>((i % 4) + 1);
        pwide.wout[i] = 0.04f * static_cast<float>((i % 2) + 1);
    }
    for (std::size_t i = 0; i < 32; ++i) {
        pwide.w1[i] = 0.05f * static_cast<float>((i % 6) + 1);
        pwide.w2[i] = 0.06f * static_cast<float>((i % 7) + 1);
    }
    std::vector<float> ptokens(4 * 4);
    for (std::size_t i = 0; i < ptokens.size(); ++i) {
        ptokens[i] = 0.1f + 0.01f * static_cast<float>(i);
    }
    std::vector<float> pout;
    CHECK(vm.causal_trunk_wide(ptokens, 4, pwide, pout));
    std::vector<float> ptarget(4, 0.0f), pwrong(4, 0.0f);
    ptarget[0] = 1.0f;
    pwrong[0] = -1.0f;
    CHECK(vm.set_wide_readout_row(1, ptarget.data(), 4));
    CHECK(vm.set_wide_readout_row(0, pwrong.data(), 4));

    WideTrunkWeights pbefore{}, pqkv_after{}, pmlp_after{};
    CHECK(vm.read_wide_weights(4, 8, pbefore));
    CHECK(vm.qkv_credit_wide(1, 0, 1.0f));
    CHECK(vm.read_wide_weights(4, 8, pqkv_after));
    CHECK(vm.trunk_credit_wide(1, 0, 1.0f));
    CHECK(vm.read_wide_weights(4, 8, pmlp_after));

    auto mv = [](const std::vector<float>& w, const float* x, float* y,
                 std::size_t rows, std::size_t cols) {
        for (std::size_t r = 0; r < rows; ++r) {
            float sum = 0.0f;
            for (std::size_t c = 0; c < cols; ++c) sum += w[r * cols + c] * x[c];
            y[r] = sum;
        }
    };
    std::array<float, 4> pq4{}, xlast{}, context{}, ph4{};
    std::array<float, 8> phid4{};
    std::array<std::array<float, 4>, 4> ktab{}, vtab{};
    for (std::size_t d = 0; d < 4; ++d) xlast[d] = ptokens[3 * 4 + d];
    mv(pbefore.wq, xlast.data(), pq4.data(), 4, 4);
    float scores[4]{};
    float max_score = -1e30f;
    for (std::size_t s = 0; s < 4; ++s) {
        mv(pbefore.wk, &ptokens[s * 4], ktab[s].data(), 4, 4);
        mv(pbefore.wv, &ptokens[s * 4], vtab[s].data(), 4, 4);
        for (std::size_t d = 0; d < 4; ++d) scores[s] += pq4[d] * ktab[s][d];
        max_score = std::max(max_score, scores[s]);
    }
    float alpha[4]{}, sum_exp = 0.0f;
    for (std::size_t s = 0; s < 4; ++s) {
        alpha[s] = std::exp(scores[s] - max_score);
        sum_exp += alpha[s];
    }
    for (std::size_t s = 0; s < 4; ++s) {
        alpha[s] /= sum_exp;
        for (std::size_t d = 0; d < 4; ++d) context[d] += alpha[s] * vtab[s][d];
    }
    std::array<float, 4> proj{};
    mv(pbefore.wout, context.data(), proj.data(), 4, 4);
    for (std::size_t d = 0; d < 4; ++d) ph4[d] = xlast[d] + proj[d];
    mv(pbefore.w1, ph4.data(), phid4.data(), 8, 4);
    for (float& value : phid4) value = std::tanh(value);
    std::array<float, 4> pe{}, pherr{}, pdc{};
    std::array<float, 8> pg{};
    for (std::size_t d = 0; d < 4; ++d) pe[d] = ptarget[d] - pwrong[d];
    for (std::size_t j = 0; j < 8; ++j) {
        float sum = 0.0f;
        for (std::size_t d = 0; d < 4; ++d) sum += pe[d] * pbefore.w2[d * 8 + j];
        pg[j] = sum * (1.0f - phid4[j] * phid4[j]);
    }
    for (std::size_t d = 0; d < 4; ++d) {
        float sum = pe[d];
        for (std::size_t j = 0; j < 8; ++j) sum += pbefore.w1[j * 4 + d] * pg[j];
        pherr[d] = sum;
    }
    for (std::size_t kk = 0; kk < 4; ++kk) {
        float sum = 0.0f;
        for (std::size_t i = 0; i < 4; ++i) sum += pherr[i] * pbefore.wout[i * 4 + kk];
        pdc[kk] = sum;
    }
    float dalpha[4]{}, sum_ad = 0.0f;
    for (std::size_t s = 0; s < 4; ++s) {
        for (std::size_t d = 0; d < 4; ++d) dalpha[s] += pdc[d] * vtab[s][d];
        sum_ad += alpha[s] * dalpha[s];
    }
    std::array<float, 4> pdq{};
    for (std::size_t s = 0; s < 4; ++s) {
        const float dz = alpha[s] * (dalpha[s] - sum_ad);
        for (std::size_t d = 0; d < 4; ++d) pdq[d] += dz * ktab[s][d];
    }
    for (std::size_t d = 0; d < 4; ++d) {
        for (std::size_t i = 0; i < 4; ++i) {
            const float expected_wq = pbefore.wq[d * 4 + i] + pdq[d] * xlast[i];
            CHECK(std::fabs(pqkv_after.wq[d * 4 + i] - expected_wq) < 3e-3f);
            const float expected_wout = pbefore.wout[d * 4 + i] + pherr[d] * context[i];
            CHECK(std::fabs(pmlp_after.wout[d * 4 + i] - expected_wout) < 3e-3f);
        }
    }
    for (std::size_t j = 0; j < 8; ++j) {
        for (std::size_t i = 0; i < 4; ++i) {
            const float expected_w1 = pbefore.w1[j * 4 + i] + pg[j] * ph4[i];
            CHECK(std::fabs(pmlp_after.w1[j * 4 + i] - expected_w1) < 3e-3f);
        }
    }
    for (std::size_t d = 0; d < 4; ++d) {
        for (std::size_t j = 0; j < 8; ++j) {
            const float expected_w2 = pbefore.w2[d * 8 + j] + pe[d] * phid4[j];
            CHECK(std::fabs(pmlp_after.w2[d * 8 + j] - expected_w2) < 3e-3f);
        }
    }

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
    const float wide_before_mlp = wide_out[0];
    CHECK(vm.trunk_credit_wide(1, 0, 0.5f));
    CHECK(vm.causal_trunk_wide_cached(wide_tokens, 1024, wide.dim, wide_out));
    CHECK(std::fabs(wide_out[0] - wide_before_mlp) > 1e-7f);

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

    // Raw contextual role/sense steps (encoder + local gradients).
    std::vector<std::array<float, kRawFeatureDim>> ctx_words(64);
    std::array<std::array<float, kRawFeatureDim>, 4> ctx_gates{};
    ctx_words[0][0] = 1.0f;
    ctx_gates[0][0] = 1.0f;
    std::array<float, kRawFeatureDim> ctx_bias{}, ctx_order{}, rel{};
    std::array<float, kRawFeatureDim> enc_dbg{};
    CHECK(vm.context_encode(1, {0}, {0}, ctx_words, ctx_gates, ctx_bias, ctx_order, 1.0f, enc_dbg));
    rel[0] = 1.0f;
    float rp1 = 0.0f, rp2 = 0.0f, rd = 0.0f, rb = 0.0f;
    CHECK(vm.role_step(1, {0}, {0}, ctx_words, ctx_gates, ctx_bias, ctx_order,
                       rel, 0.0f, 1.0f, 0.5f, 1.0f, rp1, rd));
    CHECK(vm.read_role_state(rel, rb));
    CHECK(vm.role_step(1, {0}, {0}, ctx_words, ctx_gates, ctx_bias, ctx_order,
                       rel, rb, 1.0f, 0.5f, 1.0f, rp2, rd));
    CHECK(rp2 > rp1);
    std::vector<std::array<float, kRawFeatureDim>> senses(2);
    senses[1][0] = 1.0f;
    std::vector<float> sbias(2, 0.0f);
    float sp1 = 0.0f, sp2 = 0.0f, sl = 0.0f;
    CHECK(vm.sense_step(1, {0}, {0}, ctx_words, ctx_gates, ctx_bias, ctx_order,
                        senses, sbias, 1, 0.5f, 1.0f, sp1, sl));
    CHECK(vm.read_sense_state(2, senses, sbias));
    CHECK(vm.sense_step(1, {0}, {0}, ctx_words, ctx_gates, ctx_bias, ctx_order,
                        senses, sbias, 1, 0.5f, 1.0f, sp2, sl));
    CHECK(sp2 > sp1);

    // D=24 raw contextual training loop. The host only stages tokens and
    // reads probabilities; all forward, softmax, and local-gradient work is
    // executed by the raw NaN16 guest.
    std::vector<std::array<float, 24>> ctx24_words(64);
    std::array<std::array<float, 24>, 4> ctx24_gates{};
    ctx24_words[0][0] = 1.0f;
    ctx24_gates[0][0] = 1.0f;
    std::array<float, 24> ctx24_bias{}, ctx24_order{}, rel24{};
    CHECK(vm.init_context24(ctx24_words, ctx24_gates, ctx24_bias, ctx24_order));
    rel24[0] = 1.0f;
    CHECK(vm.init_role24(rel24, 0.0f));
    float r24_prev = 0.0f;
    for (int step = 0; step < 4; ++step) {
        float p = 0.0f, d = 0.0f;
        CHECK(vm.role_step24_cached(1, {0}, {0}, 1.0f, 0.5f, 1.0f, p, d));
        CHECK(std::isfinite(p) && std::isfinite(d));
        CHECK(p > r24_prev);
        r24_prev = p;
    }

    // Multiple relation heads: reset the encoder and train relation 0 while
    // relation 1 provides a competing score.
    CHECK(vm.init_context24(ctx24_words, ctx24_gates, ctx24_bias, ctx24_order));
    std::vector<std::array<float, 24>> rel24_heads(2);
    rel24_heads[1][0] = -1.0f;
    std::vector<float> rel24_bias(2, 0.0f);
    CHECK(vm.init_role24k(rel24_heads, rel24_bias));
    float r24k_prev = 0.0f;
    for (int step = 0; step < 4; ++step) {
        float p = 0.0f, d = 0.0f;
        CHECK(vm.role_step24k_cached(1, {0}, {0}, 0, 1.0f, 0.5f, 1.0f, p, d));
        CHECK(std::isfinite(p) && std::isfinite(d));
        CHECK(p > r24k_prev);
        r24k_prev = p;
    }

    std::vector<std::array<float, 24>> senses24(2);
    senses24[1][0] = 1.0f;
    std::vector<float> sbias24(2, 0.0f);
    CHECK(vm.init_sense24(senses24, sbias24));
    float s24_prev = 0.0f;
    for (int step = 0; step < 4; ++step) {
        float p = 0.0f, loss = 0.0f;
        CHECK(vm.sense_step24_cached(1, {0}, {0}, 1, 0.5f, 1.0f, p, loss));
        CHECK(std::isfinite(p) && std::isfinite(loss));
        CHECK(p > s24_prev);
        s24_prev = p;
    }

    // Phase-vector layer pipeline: trig encode, rotation, PQ, spectral
    // iteration and sparse k-NN all execute in the raw guest.
    const std::array<std::uint8_t, 6> phase_batch_bytes = {1, 2, 3, 4, 5, 6};
    std::vector<std::int32_t> phase_batch;
    CHECK(vm.phase_encode_batch(phase_batch_bytes.data(), 2, 3, 4, phase_batch));
    CHECK_EQ(phase_batch.size(), 16u);
    bool phase_batch_nonzero = false;
    for (std::int32_t value : phase_batch) phase_batch_nonzero |= value != 0;
    CHECK(phase_batch_nonzero);
    const std::array<std::uint8_t, 4> phase_bytes = {1, 2, 3, 4};
    std::vector<std::int32_t> phase_vector;
    std::uint32_t phase_shard = 0;
    CHECK(vm.phase_encode_wide(phase_bytes.data(), phase_bytes.size(), 4,
                               phase_vector, phase_shard));
    CHECK_EQ(phase_vector.size(), 8u);
    CHECK(phase_shard < 16u);
    bool phase_nonzero = false;
    for (std::int32_t value : phase_vector) phase_nonzero |= value != 0;
    CHECK(phase_nonzero);

    std::vector<std::int32_t> rotated;
    CHECK(vm.phase_rotate(phase_vector, 0, rotated));
    CHECK_EQ(rotated.size(), phase_vector.size());
    for (std::size_t i = 0; i < rotated.size(); ++i)
        CHECK(std::abs(rotated[i] - phase_vector[i]) <= 1024);

    const std::vector<std::int32_t> pq_query = {65536, 0};
    const std::vector<std::int32_t> pq_book = {65536, 0, 0, 65536};
    std::uint32_t pq_code = 99;
    std::int32_t pq_distance = -1;
    CHECK(vm.pq_encode(pq_query, pq_book, 2, 2, pq_code, pq_distance));
    CHECK_EQ(pq_code, 0u);
    CHECK(std::abs(pq_distance) <= 1);

    std::array<std::int32_t, 64> spectrum_adjacency{};
    std::array<std::int32_t, 8> spectrum_in{}, spectrum_out{};
    for (std::size_t i = 0; i < 8; ++i) {
        spectrum_adjacency[i * 8 + i] = 65536;
        spectrum_in[i] = static_cast<std::int32_t>((i + 1) * 4096);
    }
    CHECK(vm.spectral_iter(spectrum_adjacency, spectrum_in, spectrum_out));
    for (std::size_t i = 0; i < 8; ++i)
        CHECK(std::abs(spectrum_out[i] - spectrum_in[i]) <= 2);

    const std::vector<std::int32_t> knn_query = {65536, 0};
    const std::vector<std::int32_t> knn_bank = {65536, 0, 0, 65536};
    std::vector<std::uint32_t> knn_indices;
    std::vector<std::int32_t> knn_scores;
    CHECK(vm.sparse_knn(knn_query, knn_bank, 2, 2, 1, knn_indices,
                        knn_scores));
    CHECK_EQ(knn_indices.size(), 1u);
    CHECK_EQ(knn_indices[0], 0u);
    CHECK(knn_scores[0] >= 65535);

    // Trained codebook: two well-separated samples must stay put after one
    // raw Lloyd iteration.
    {
        const std::vector<std::int32_t> train_samples = {0, 0, 100, 100};
        std::vector<std::int32_t> trained_codebook;
        CHECK(vm.pq_train(train_samples, 2, 2, 2, 1, trained_codebook));
        CHECK_EQ(trained_codebook.size(), 4u);
        CHECK_EQ(trained_codebook[0], 0);
        CHECK_EQ(trained_codebook[1], 0);
        CHECK_EQ(trained_codebook[2], 100);
        CHECK_EQ(trained_codebook[3], 100);
        std::vector<std::int32_t> warm_codebook = {10, 10, 90, 90};
        CHECK(vm.pq_update(train_samples, 2, 2, 2, 1, warm_codebook));
        CHECK_EQ(warm_codebook[0], 0);
        CHECK_EQ(warm_codebook[1], 0);
        CHECK_EQ(warm_codebook[2], 100);
        CHECK_EQ(warm_codebook[3], 100);
        const std::vector<std::int32_t> residual_samples = {5, 7, 100, 100};
        const std::vector<std::uint32_t> residual_codes = {0, 1};
        std::vector<std::int32_t> residuals;
        CHECK(vm.pq_residuals(residual_samples, residual_codes, 2, 2,
                              trained_codebook, residuals));
        CHECK_EQ(residuals.size(), 4u);
        CHECK_EQ(residuals[0], 5);
        CHECK_EQ(residuals[1], 7);
        CHECK_EQ(residuals[2], 0);
        CHECK_EQ(residuals[3], 0);
        bool leaf_ok = false;
        std::int32_t leaf_error = -1;
        CHECK(vm.leaf_verify(residual_samples, trained_codebook, residuals, 0,
                             2, 0, leaf_ok, leaf_error));
        CHECK(leaf_ok);
        CHECK_EQ(leaf_error, 0);
        const std::vector<std::int32_t> bad_residual = {0, 0};
        CHECK(vm.leaf_verify(residual_samples, trained_codebook, bad_residual,
                             1, 2, 0, leaf_ok, leaf_error));
        CHECK(!leaf_ok);
        CHECK_EQ(leaf_error, 188);
        const std::vector<std::int32_t> hash_payload = {1, 2, 3, 4};
        std::uint32_t digest_a = 0, digest_b = 0;
        CHECK(vm.raw_hash(hash_payload, digest_a));
        CHECK(vm.raw_hash(hash_payload, digest_b));
        CHECK_EQ(digest_a, digest_b);
        auto changed_hash = hash_payload;
        changed_hash[0] ^= 1;
        CHECK(vm.raw_hash(changed_hash, digest_b));
        CHECK(digest_a != digest_b);
    }

    // Raw tokenizer and 3-word meta-context -> trihead bridge.
    {
        std::vector<std::uint32_t> words, subwords, meta;
        std::size_t word_count = 0, subword_count = 0;
        CHECK(vm.tokenize("Hello, world!", 16, words, subwords, meta,
                          word_count, subword_count));
        CHECK_EQ(word_count, 2u);
        CHECK_EQ(subword_count, 26u);
        CHECK_EQ(words.size(), 2u);
        CHECK_EQ(meta.size(), 12u);
        CHECK(vm.meta_trihead_reset());
        std::size_t contexts = 0;
        CHECK(vm.meta_trihead_observe_batch(words, contexts));
        CHECK_EQ(contexts, 2u);
        std::vector<std::int32_t> meta_votes, meta_credits;
        CHECK(vm.read_meta_trihead(meta_votes, meta_credits));
        CHECK_EQ(meta_votes.size(), 85u);
        CHECK_EQ(meta_credits.size(), 255u);
        std::size_t nonzero_votes = 0;
        for (std::int32_t vote : meta_votes) nonzero_votes += vote != 0;
        CHECK(nonzero_votes >= 1);

        // Temporally split slots: past, current field head 255, future.
        std::vector<std::uint32_t> t_words, t_subwords, t_meta;
        std::size_t tw = 0, ts = 0;
        CHECK(vm.tokenize("one two three four", 16, t_words, t_subwords,
                          t_meta, tw, ts));
        CHECK_EQ(tw, 4u);
        CHECK(vm.temporal_slots_reset());
        std::size_t t_contexts = 0;
        CHECK(vm.temporal_slots_observe_batch(t_words, t_contexts));
        CHECK_EQ(t_contexts, 4u);
        std::vector<std::int32_t> pv, pc, fv, fc, slots;
        std::vector<std::uint32_t> current_words;
        std::array<std::int32_t, 4> head255{};
        CHECK(vm.read_temporal_slots(tw, pv, pc, fv, fc, current_words,
                                     head255, slots));
        CHECK_EQ(head255[1], -1);
        CHECK_EQ(head255[0], static_cast<std::int32_t>(t_words.back()));
        CHECK_EQ(slots.size(), tw * 3);
        CHECK(vm.temporal_slots_project());
        std::vector<std::int32_t> projected_votes, projected_credits;
        CHECK(vm.read_meta_trihead(projected_votes, projected_credits));
        std::size_t projected_nonzero = 0;
        for (std::int32_t vote : projected_votes) projected_nonzero += vote != 0;
        CHECK(projected_nonzero >= 1);
    }

    // Byte n-gram trainer: all four orders are counted in the guest.
    {
        CHECK(vm.ngram_reset());
        const std::string bytes = "ababa";
        std::size_t processed = 0;
        CHECK(vm.ngram_train(bytes, processed));
        CHECK_EQ(processed, bytes.size());
        std::array<std::vector<std::uint32_t>, 4> keys, counts;
        CHECK(vm.ngram_topk(keys, counts));
        for (const auto& list : keys) CHECK_EQ(list.size(), 64u);
        std::uint32_t a_count = 0, b_count = 0;
        for (std::size_t i = 0; i < keys[0].size(); ++i) {
            if (keys[0][i] == 'a') a_count = counts[0][i];
            if (keys[0][i] == 'b') b_count = counts[0][i];
        }
        CHECK_EQ(a_count, 3u);
        CHECK_EQ(b_count, 2u);
        bool saw_bigram = false;
        for (std::size_t i = 0; i < keys[1].size(); ++i)
            saw_bigram = saw_bigram || (keys[1][i] == 0x6162u); // "ab"
        CHECK(saw_bigram);
    }

    // 256-dimensional geometry: hyperbolic radius, path, triangle, field.
    {
        std::vector<std::int32_t> v0(256, 0), v1(256, 0), v2(256, 0);
        for (std::size_t i = 0; i < 256; ++i) {
            v0[i] = static_cast<std::int32_t>(i + 1);
            v1[i] = static_cast<std::int32_t>(2 * (i + 1));
            v2[i] = static_cast<std::int32_t>(3 * (i + 1));
        }
        std::int32_t mean = 0, radial = 0;
        CHECK(vm.hyperbolic_measure(v0, 256, mean, radial));
        CHECK(mean > 0);
        CHECK(radial >= 0);
        std::vector<std::int32_t> bank;
        bank.insert(bank.end(), v0.begin(), v0.end());
        bank.insert(bank.end(), v1.begin(), v1.end());
        bank.insert(bank.end(), v2.begin(), v2.end());
        std::int32_t length = 0, closure = 0, turn = 0, curvature = 0;
        CHECK(vm.path_geometry(bank, 3, 256, length, closure, turn,
                               curvature));
        CHECK(length > 0);
        CHECK(closure > 0);
        std::array<std::int32_t, 3> sides{};
        std::int32_t area = 0, tight = 0, orient = 0;
        CHECK(vm.triangle_geometry(bank, 256, sides, area, tight, orient));
        CHECK(sides[0] > 0 && sides[1] > 0 && sides[2] > 0);
        std::vector<std::int32_t> gcredits, gvotes;
        std::int32_t field = 0;
        CHECK(vm.field_perturb(v0, 256, gcredits, gvotes, field));
        CHECK_EQ(gcredits.size(), 255u);
        CHECK_EQ(gvotes.size(), 85u);
    }

    // C(256,2) vector-code observer: raw pair indexing and accumulation.
    CHECK(vm.vector_matrix_reset());
    std::uint32_t matrix_index = 999;
    std::int32_t matrix_value = 0;
    CHECK(vm.vector_matrix_accumulate(0, 1, 65536, matrix_index, matrix_value));
    CHECK_EQ(matrix_index, 0u);
    CHECK_EQ(matrix_value, 65536);
    CHECK(vm.vector_matrix_accumulate(1, 0, 65536, matrix_index, matrix_value));
    CHECK_EQ(matrix_index, 0u);
    CHECK_EQ(matrix_value, 131072);
    CHECK(vm.vector_matrix_accumulate(4, 4, 65536, matrix_index, matrix_value));
    CHECK_EQ(matrix_index, 32640u);
    CHECK_EQ(matrix_value, 0);
    CHECK(vm.vector_matrix_accumulate(254, 255, 32768, matrix_index,
                                      matrix_value));
    CHECK_EQ(matrix_index, 32639u);
    CHECK_EQ(matrix_value, 32768);
    std::int32_t probe_head = -1, probe_score = -1;
    CHECK(vm.vector_matrix_probe(0, 1, probe_head, probe_score));
    CHECK_EQ(probe_head, 1);
    CHECK_EQ(probe_score, 131072);
    std::vector<std::int32_t> matrix_cells;
    CHECK(vm.read_vector_matrix(matrix_cells));
    CHECK_EQ(matrix_cells.size(), 32640u);
    CHECK_EQ(matrix_cells[0], 131072);
    CHECK_EQ(matrix_cells[32639], 32768);
    std::vector<std::int32_t> matrix_credits;
    CHECK(vm.vector_matrix_credits(matrix_credits));
    CHECK_EQ(matrix_credits.size(), 255u);
    CHECK(matrix_credits[0] >= 131072);
    CHECK(matrix_credits[1] >= 131072);
    CHECK_EQ(matrix_credits[4], 0);
    std::array<std::int32_t, kTriadMemberCount> hot_credits{};
    std::copy(matrix_credits.begin(), matrix_credits.end(),
              hot_credits.begin());
    HotTriheadResult matrix_hot;
    CHECK(vm.hot_triheads(hot_credits, 0, matrix_hot));
    CHECK_EQ(matrix_hot.hot_heads, 3u);
    CHECK_EQ(matrix_hot.hot_triads, 1u);
    CHECK(!matrix_hot.field_hot);
    // Triangle-shape model is independent of the matrix/field state.
    {
        std::array<std::int32_t, 3> tsides = {100, 110, 105};
        CHECK(vm.triangle_model_reset());
        std::int32_t tcount = 0;
        CHECK(vm.triangle_model_observe(tsides, 105, 50000, 1, tcount));
        CHECK_EQ(tcount, 1);
        std::int32_t tscore = 0;
        CHECK(vm.triangle_model_score(tsides, 105, 50000, tscore));
        CHECK(tscore > 0);
        std::array<std::int32_t, 3> tstats{};
        std::array<std::int32_t, 2> torient{};
        CHECK(vm.read_triangle_model(tstats, torient));
        CHECK_EQ(tstats[2], 1);

        // The negative bank is a separate distribution.  A positive-like
        // shape must score above a negative-like shape, and the negative
        // bank must remain independently inspectable.
        std::array<std::int32_t, 3> nsides = {300, 310, 305};
        std::int32_t ncount = 0;
        CHECK(vm.triangle_model_observe_negative(nsides, 305, 20000, -1,
                                                 ncount));
        CHECK_EQ(ncount, 1);
        std::int32_t contrast_pos = 0, contrast_neg = 0;
        CHECK(vm.triangle_model_score_contrastive(tsides, 105, 50000,
                                                  contrast_pos));
        CHECK(vm.triangle_model_score_contrastive(nsides, 305, 20000,
                                                  contrast_neg));
        CHECK(contrast_pos > 60000);
        CHECK(contrast_neg < 5000);
        std::array<std::int32_t, 3> nstats{};
        std::array<std::int32_t, 2> norient{};
        CHECK(vm.read_triangle_model_negative(nstats, norient));
        CHECK_EQ(nstats[2], 1);

        // With no negative examples yet, contrastive scoring falls back to
        // the positive-only shape score rather than returning a fake zero.
        CHECK(vm.triangle_model_reset());
        CHECK(vm.triangle_model_observe(tsides, 105, 50000, 1, tcount));
        std::int32_t fallback = 0;
        CHECK(vm.triangle_model_score_contrastive(tsides, 105, 50000,
                                                  fallback));
        CHECK(fallback > 60000);

        // A negative-only bank cannot produce a positive contrastive score.
        CHECK(vm.triangle_model_reset());
        CHECK(vm.triangle_model_observe_negative(nsides, 305, 20000, -1,
                                                 ncount));
        std::int32_t no_positive = -1;
        CHECK(vm.triangle_model_score_contrastive(tsides, 105, 50000,
                                                  no_positive));
        CHECK_EQ(no_positive, 0);
    }

    return test_done("raw NaN16 field VM bridge");
}
