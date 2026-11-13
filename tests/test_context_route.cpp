#include "nanlm/raw_field.hpp"
#include "test_util.hpp"

#include <cmath>

using namespace nanlm;

int main() {
    RawFieldVM vm("build/field_driver.nan");
    CHECK(vm.ready());
    if (!vm.ready()) return test_done("raw NaN16 joint context readout");

    constexpr std::size_t kBuckets = 64;
    constexpr std::size_t kBucket = 5;
    CHECK(vm.reset_context_readout(kBuckets));

    // High posterior: wrong group 0 = 0.55, true group 1 = 0.45.
    // Low group 0 is diffuse (wrong low 1 = 0.30); low group 1 is peaked
    // (true low 0 = 0.90).  Greedy high->low picks (0, 1); joint routing
    // picks (1, 0) because 0.45*0.90 > 0.55*0.30.
    const float high0 = std::log(0.55f);
    const float high1 = std::log(0.45f);
    const float low0_wrong = std::log(0.30f);
    const float low0_other = std::log(0.70f / 15.0f);
    const float low1_true = std::log(0.90f);
    const float low1_other = std::log(0.10f / 15.0f);
    for (std::size_t h = 0; h < 16; ++h) {
        const float value = h == 0 ? high0 : (h == 1 ? high1 : -20.0f);
        CHECK(vm.set_context_high(kBucket, h, value, kBuckets));
    }
    for (std::size_t l = 0; l < 16; ++l) {
        CHECK(vm.set_context_low(kBucket, 0, l,
                                 l == 1 ? low0_wrong : low0_other, kBuckets));
        CHECK(vm.set_context_low(kBucket, 1, l,
                                 l == 0 ? low1_true : low1_other, kBuckets));
    }

    const std::uint8_t target = 0x10;  // high 1, low 0
    bool correct = false;
    float loss = 0.0f;
    std::uint8_t predicted_high = 0, predicted_low = 0;

    CHECK(vm.readout_context(target, 0.0f, kBucket, kBuckets, correct, loss,
                             predicted_high, predicted_low));
    CHECK(!correct);
    CHECK_EQ(predicted_high, 0u);
    CHECK_EQ(predicted_low, 1u);
    CHECK(std::isfinite(loss));

    correct = false;
    predicted_high = predicted_low = 0;
    CHECK(vm.readout_context_joint(target, 0.0f, kBucket, kBuckets, correct,
                                   loss, predicted_high, predicted_low));
    CHECK(correct);
    CHECK_EQ(predicted_high, 1u);
    CHECK_EQ(predicted_low, 0u);
    CHECK(std::isfinite(loss));
    CHECK(loss > 0.0f);

    // The guest backoff route resolves the compact bucket, then the joint
    // readout runs on that same bucket.  Greedy backoff still picks high 0,
    // while the joint head pair selects high 1 / low 0.
    CHECK(vm.reset_context_readout(kBuckets));
    CHECK(vm.reset_context_backoff());
    constexpr std::uint32_t kKey = 0x41424344u;
    bool inserted = false;
    for (int step = 0; step < 3; ++step) {
        CHECK(vm.context_backoff_build(kKey, &inserted));
        if (step == 0) CHECK(inserted);
    }
    ContextBackoffSelection selection;
    CHECK(vm.context_backoff_select(kBuckets, 1, selection));
    CHECK_EQ(selection.exact_count, 1u);
    std::vector<std::uint32_t> selected_keys;
    CHECK(vm.context_backoff_exact_keys(selection.exact_count, selected_keys));
    CHECK_EQ(selected_keys.size(), 1u);
    CHECK_EQ(selected_keys[0], kKey);

    ContextBackoffStep routed;
    CHECK(vm.readout_context_backoff(target, 0.0f, kKey, kBuckets, routed));
    CHECK(routed.exact);
    const std::uint32_t routed_bucket = routed.bucket;
    CHECK(routed_bucket < kBuckets);
    for (std::size_t h = 0; h < 16; ++h) {
        const float value = h == 0 ? high0 : (h == 1 ? high1 : -20.0f);
        CHECK(vm.set_context_high(routed_bucket, h, value, kBuckets));
    }
    for (std::size_t l = 0; l < 16; ++l) {
        CHECK(vm.set_context_low(routed_bucket, 0, l,
                                 l == 1 ? low0_wrong : low0_other, kBuckets));
        CHECK(vm.set_context_low(routed_bucket, 1, l,
                                 l == 0 ? low1_true : low1_other, kBuckets));
    }
    CHECK(vm.readout_context_backoff(target, 0.0f, kKey, kBuckets, routed));
    CHECK(!routed.correct);
    CHECK_EQ(routed.predicted_high, 0u);
    CHECK_EQ(routed.predicted_low, 1u);
    CHECK(std::isfinite(routed.loss));

    bool joint_correct = false;
    float joint_loss = 0.0f;
    std::uint8_t joint_high = 0, joint_low = 0;
    CHECK(vm.readout_context_joint(target, 0.0f, routed_bucket, kBuckets,
                                   joint_correct, joint_loss, joint_high,
                                   joint_low));
    CHECK(joint_correct);
    CHECK_EQ(joint_high, 1u);
    CHECK_EQ(joint_low, 0u);
    CHECK(std::isfinite(joint_loss));
    CHECK(joint_loss > 0.0f);

    // The same guest-selected exact key feeds the copy/induction route.
    CHECK(vm.reset_context_readout(kBuckets));
    CHECK(vm.reset_context_copy(selected_keys, kBuckets, 4));
    bool copy_correct = false;
    float copy_loss = 0.0f;
    std::uint8_t copy_predicted = 0;
    for (int step = 0; step < 8; ++step) {
        CHECK(vm.readout_context_copy(
            target, 0.5f, kKey, kBuckets, selected_keys.size(), 4, 0.15f,
            copy_correct, copy_loss, copy_predicted));
        CHECK(copy_correct);
        CHECK_EQ(copy_predicted, target);
    }
    CHECK(vm.readout_context_copy(
        target, 0.0f, kKey, kBuckets, selected_keys.size(), 4, 0.15f,
        copy_correct, copy_loss, copy_predicted));
    CHECK(copy_correct);
    CHECK_EQ(copy_predicted, target);
    CHECK(std::isfinite(copy_loss));

    // An out-of-range bucket is rejected consistently in both modes.
    CHECK(!vm.readout_context(target, 0.0f, kBuckets, kBuckets, correct, loss,
                              predicted_high, predicted_low));
    CHECK(!vm.readout_context_joint(target, 0.0f, kBuckets, kBuckets, correct,
                                    loss, predicted_high, predicted_low));

    return test_done("raw NaN16 joint context readout");
}
