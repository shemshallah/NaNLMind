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

    // An out-of-range bucket is rejected consistently in both modes.
    CHECK(!vm.readout_context(target, 0.0f, kBuckets, kBuckets, correct, loss,
                              predicted_high, predicted_low));
    CHECK(!vm.readout_context_joint(target, 0.0f, kBuckets, kBuckets, correct,
                                    loss, predicted_high, predicted_low));

    return test_done("raw NaN16 joint context readout");
}
