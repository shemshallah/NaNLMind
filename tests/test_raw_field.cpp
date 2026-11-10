#include "nanlm/raw_field.hpp"
#include "nanlm/sparse_field.hpp"
#include "test_util.hpp"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>

#include <array>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <vector>

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

    // Context 16x16 class table -> canonical 255-head/85-triad/43 field
    // link. The committed guest fixture is
    // mth/tests/mth_context_class_test.nas; this drives the same command 30
    // through the C++ bridge.
    constexpr std::size_t context_buckets = 4;
    constexpr std::uint32_t context_bucket = 1;
    {
        const auto path = std::filesystem::temp_directory_path() /
                          "nanlm_context_class_scores.bin";
        std::ofstream scores(path, std::ios::binary);
        CHECK(static_cast<bool>(scores));
        std::vector<std::uint32_t> words(272 * context_buckets, 0);
        auto put_score = [&](std::size_t index, float value) {
            std::uint32_t bits = 0;
            std::memcpy(&bits, &value, sizeof(bits));
            words[index] = bits;
        };
        const std::size_t low_base = 16 * context_buckets;
        put_score(8 * context_buckets + context_bucket, 1.0f);
        put_score(low_base + 8 * 16 * context_buckets +
                  5 * context_buckets + context_bucket, 1.0f);
        for (const std::uint32_t word : words) {
            const std::array<char, 4> raw = {
                static_cast<char>(word & 0xFFu),
                static_cast<char>((word >> 8) & 0xFFu),
                static_cast<char>((word >> 16) & 0xFFu),
                static_cast<char>((word >> 24) & 0xFFu)};
            scores.write(raw.data(), raw.size());
        }
        scores.close();
        CHECK(vm.load_context_readout(path.string(), context_buckets));
        std::error_code ignored;
        std::filesystem::remove(path, ignored);
    }

    std::array<std::int32_t, kTriadMemberCount> class_credits{};
    for (std::size_t i = 0; i < 126; ++i) class_credits[i] = 0x2000;
    class_credits[132] = 0x2000;
    ContextClassInput class_input;
    class_input.buckets = context_buckets;
    class_input.bucket = context_bucket;
    class_input.head_threshold = 0x1000;

    ContextClassResult class_result;
    CHECK(vm.context_class_map(class_input, class_credits, class_result));
    CHECK_EQ(class_result.high, 8u);
    CHECK_EQ(class_result.low, 5u);
    CHECK_EQ(class_result.head, 133u);
    CHECK_EQ(class_result.triad, 44u);
    CHECK_EQ(class_result.member, 1u);
    CHECK(!class_result.field_head);
    CHECK_EQ(class_result.accepted_triads, 42u);
    CHECK(!class_result.field_accepted);
    CHECK(!class_result.triad_accepted);
    CHECK_EQ(class_result.votes[0], 1u);
    CHECK_EQ(class_result.votes[44], 0u);

    // Native CFT credit crosses the head threshold and makes triad 44 the
    // 43rd accepted triad; 42/85 stays rejected above.
    ContextCreditInput class_credit;
    class_credit.kind = ContextCreditKind::Cft;
    class_credit.cft = {0, 0, 0, 0x10000, 0x6000};
    ContextClassResult credited;
    CHECK(vm.context_class_credit(class_input, class_credit, class_credits,
                                  credited));
    CHECK_EQ(credited.credit_delta, 0x2000);
    CHECK_EQ(credited.head_credit_before, 0);
    CHECK_EQ(credited.head_credit_after, 0x2000);
    CHECK(credited.credit_applied);
    CHECK_EQ(credited.accepted_triads, 43u);
    CHECK(credited.field_accepted);
    CHECK(credited.triad_accepted);
    CHECK_EQ(credited.votes[44], 1u);

    // The TRAIL branch uses the same native kernel ABI. This is the fixed
    // vector from mth/tests/mth_credit_pipeline_test.nas: credit = -0x6DC.
    ContextCreditInput trail_credit;
    trail_credit.kind = ContextCreditKind::Trail;
    trail_credit.trail = {0x8000, 0x6666, 0x4CCC, 0x3333, 0x1999,
                          0x1999, 0x3333, 0x0CCC, 0x051E, 0xE666, 0xCCCC};
    ContextClassResult trailed;
    CHECK(vm.context_class_credit(class_input, trail_credit, class_credits,
                                  trailed));
    CHECK_EQ(trailed.credit_delta, -0x6DC);
    CHECK_EQ(trailed.head_credit_before, 0);
    CHECK_EQ(trailed.head_credit_after, -0x6DC);
    CHECK(trailed.credit_applied);
    CHECK_EQ(trailed.accepted_triads, 42u);
    CHECK(!trailed.field_accepted);

    // Chart bridge copies the guest votes, field count and selected head
    // credit into the canonical chart.
    Universe class_universe;
    for (std::size_t i = 0; i < 126; ++i) {
        class_universe.head_credit()[i] = 0x2000;
    }
    class_universe.head_credit()[132] = 0x2000;
    ContextClassResult applied;
    CHECK(vm.context_class_apply(class_universe, class_input, class_credit,
                                 applied));
    CHECK_EQ(class_universe.head_credit()[133], 0x2000);
    CHECK_EQ(class_universe.triad_field_count(), 43u);
    CHECK_EQ(class_universe.triad_votes()[0], 1u);
    CHECK_EQ(class_universe.triad_votes()[44], 1u);

    // Direct-prediction mode uses the same guest mapping law, including the
    // reserved field head 255.
    ContextClassInput direct_input;
    direct_input.direct = true;
    direct_input.direct_high = 15;
    direct_input.direct_low = 14;
    direct_input.head_threshold = 0x1000;
    ContextClassResult direct_result;
    CHECK(vm.context_class_map(direct_input, class_credits, direct_result));
    CHECK_EQ(direct_result.head, 254u);
    CHECK_EQ(direct_result.triad, 84u);
    CHECK_EQ(direct_result.member, 2u);
    CHECK(!direct_result.field_head);
    direct_input.direct_low = 15;
    CHECK(vm.context_class_map(direct_input, class_credits, direct_result));
    CHECK_EQ(direct_result.head, 255u);
    CHECK_EQ(direct_result.triad, 0xFFFFu);
    CHECK_EQ(direct_result.member, 0xFFFFu);
    CHECK(direct_result.field_head);

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

    // Batched context readout: 1,500 samples must produce the same guest
    // state, correct count and float32 loss sum as 1,500 per-sample commands.
    // The batching only removes host round trips; the guest still calls the
    // mth_context_hier kernel once per sample.
    constexpr std::size_t batch_buckets = 512;
    constexpr std::size_t batch_samples = 1500;
    RawFieldVM batch_vm("build/field_driver.nan");
    RawFieldVM ref_vm("build/field_driver.nan");
    CHECK(batch_vm.ready());
    CHECK(ref_vm.ready());
    CHECK(batch_vm.reset_context_readout(batch_buckets));
    CHECK(ref_vm.reset_context_readout(batch_buckets));
    std::vector<std::uint8_t> batch_targets(batch_samples);
    std::vector<std::uint32_t> batch_contexts(batch_samples);
    std::vector<float> batch_lrs(batch_samples);
    std::uint32_t lcg = 0x9E3779B9u;
    for (std::size_t i = 0; i < batch_samples; ++i) {
        lcg = lcg * 1664525u + 1013904223u;
        batch_targets[i] =
            static_cast<std::uint8_t>((lcg >> 24) % 255u);
        batch_contexts[i] =
            static_cast<std::uint32_t>((lcg >> 8) % batch_buckets);
        batch_lrs[i] = (i % 17 == 0) ? 0.0f
                                     : 0.05f + 0.001f * static_cast<float>(i % 23);
    }
    std::size_t ref_correct = 0;
    float ref_loss = 0.0f;
    for (std::size_t i = 0; i < batch_samples; ++i) {
        bool sample_correct = false;
        float sample_loss = 0.0f;
        std::uint8_t predicted_high = 0, predicted_low = 0;
        CHECK(ref_vm.readout_context(
            batch_targets[i], batch_lrs[i], batch_contexts[i], batch_buckets,
            sample_correct, sample_loss, predicted_high, predicted_low));
        ref_correct += sample_correct ? 1u : 0u;
        ref_loss += sample_loss;
    }
    std::size_t batch_correct = 0, batch_processed = 0;
    float batch_loss = 0.0f;
    CHECK(batch_vm.readout_context_batch(
        batch_targets.data(), batch_contexts.data(), batch_lrs.data(),
        batch_samples, batch_buckets, batch_correct, batch_loss,
        batch_processed));
    CHECK_EQ(batch_processed, batch_samples);
    CHECK_EQ(batch_correct, ref_correct);
    std::uint32_t batch_loss_bits = 0, ref_loss_bits = 0;
    std::memcpy(&batch_loss_bits, &batch_loss, sizeof(batch_loss_bits));
    std::memcpy(&ref_loss_bits, &ref_loss, sizeof(ref_loss_bits));
    CHECK_EQ(batch_loss_bits, ref_loss_bits);

    const char* batch_path = "build/context_batch_parity.nmc";
    const char* ref_path = "build/context_ref_parity.nmc";
    CHECK(batch_vm.save_context_readout(batch_path, batch_buckets));
    CHECK(ref_vm.save_context_readout(ref_path, batch_buckets));
    std::ifstream batch_file(batch_path, std::ios::binary);
    std::ifstream ref_file(ref_path, std::ios::binary);
    const std::string batch_bytes((std::istreambuf_iterator<char>(batch_file)),
                                  std::istreambuf_iterator<char>());
    const std::string ref_bytes((std::istreambuf_iterator<char>(ref_file)),
                                std::istreambuf_iterator<char>());
    CHECK(!batch_bytes.empty());
    CHECK(batch_bytes == ref_bytes);
    std::remove(batch_path);
    std::remove(ref_path);

    return test_done("raw NaN16 field VM bridge");
}
