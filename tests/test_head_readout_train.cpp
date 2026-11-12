#include "nanlm/raw_field.hpp"
#include "test_util.hpp"

#include <array>
#include <cmath>
#include <limits>
#include <vector>

using namespace nanlm;

int main() {
    RawFieldVM vm("build/head_worker.nan");
    CHECK(vm.ready());

    std::array<float, 128> state{};
    state[0] = 1.0f;
    std::vector<std::array<float, 128>> candidates(2);
    candidates[0][0] = 1.0f;
    candidates[1][0] = -1.0f;

    std::vector<float> probabilities;
    std::vector<std::array<float, 128>> updated;
    float loss = 0.0f;
    std::uint8_t predicted = 0;
    std::uint8_t reason = 0;
    CHECK(vm.native_head_state_train(state, candidates, 0, 0.1f,
                                     probabilities, updated, loss,
                                     predicted, reason));
    CHECK_EQ(reason, 0u);
    CHECK_EQ(predicted, 0u);
    CHECK(std::isfinite(loss));
    CHECK(loss >= 0.0f);
    CHECK_EQ(probabilities.size(), 2u);
    CHECK(probabilities[0] > probabilities[1]);
    CHECK(updated[0][0] > candidates[0][0]);
    CHECK(updated[1][0] < candidates[1][0]);
    bool finite = true;
    for (const auto& row : updated)
        for (float value : row) finite = finite && std::isfinite(value);
    CHECK(finite);

    std::vector<float> rejected_probs;
    std::vector<std::array<float, 128>> rejected_updated;
    CHECK(vm.native_head_state_train(state, candidates, 2, 0.1f,
                                     rejected_probs, rejected_updated,
                                     loss, predicted, reason));
    CHECK_EQ(reason, 1u);
    CHECK(rejected_probs.empty());
    CHECK(rejected_updated.empty());

    CHECK(vm.native_head_state_train(state, candidates, 0,
                                     std::numeric_limits<float>::quiet_NaN(),
                                     rejected_probs, rejected_updated,
                                     loss, predicted, reason));
    CHECK_EQ(reason, 1u);

    return test_done("native head-state readout training step");
}
