#include "nanlm/raw_field.hpp"
#include "test_util.hpp"

#include <array>
#include <cmath>
#include <vector>

using namespace nanlm;

int main() {
    RawFieldVM vm("build/head_worker.nan");
    CHECK(vm.ready());

    std::array<float, 128> state{};
    for (unsigned d = 0; d < 128; ++d)
        state[d] = 0.01f * static_cast<float>(static_cast<int>(d) - 64);

    std::vector<std::array<float, 128>> candidates(3);
    candidates[0][0] = 1.0f;
    candidates[1][1] = 1.0f;
    candidates[2][2] = 1.0f;
    std::vector<float> scores;
    std::uint8_t reason = 0;
    CHECK(vm.native_head_state_readout(state, candidates, scores, reason));
    CHECK_EQ(reason, 0u);
    CHECK_EQ(scores.size(), 3u);
    CHECK_EQ(scores[0], state[0]);
    CHECK_EQ(scores[1], state[1]);
    CHECK_EQ(scores[2], state[2]);

    std::vector<float> again;
    CHECK(vm.native_head_state_readout(state, candidates, again, reason));
    CHECK(again == scores);

    const std::vector<std::array<float, 128>> none;
    CHECK(vm.native_head_state_readout(state, none, again, reason));
    CHECK_EQ(reason, 1u);
    CHECK(again.empty());

    std::vector<std::array<float, 128>> too_many(65);
    CHECK(vm.native_head_state_readout(state, too_many, again, reason));
    CHECK_EQ(reason, 1u);

    return test_done("native head-state readout");
}
