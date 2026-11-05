#include "nanlm/bootstrap_router.hpp"
#include "test_util.hpp"

#include <array>

using namespace nanlm;

namespace {

HopfieldRouter::Vector code(std::uint8_t token) {
    HopfieldRouter::Vector v{};
    v[token % HopfieldRouter::kDim] = 100;
    return v;
}

} // namespace

int main() {
    HopfieldConfig cfg;
    cfg.top_k = 1;       // one active head makes the pair choice deterministic
    cfg.max_strength = 32;
    HopfieldRouter hop(cfg);

    for (std::uint8_t t = 0; t < 8; ++t) {
        hop.set_head(t, code(t));
    }

    const std::array<std::uint8_t, 8> sequence{0, 1, 2, 3, 4, 5, 6, 7};
    constexpr int kEpochs = 10;
    for (int epoch = 0; epoch < kEpochs; ++epoch) {
        for (std::size_t i = 0; i < sequence.size(); ++i) {
            const std::uint8_t input = sequence[i];
            const std::uint8_t target = sequence[(i + 1) % sequence.size()];
            CHECK(hop.learn(code(input), target));
        }
    }

    std::size_t correct = 0;
    for (std::size_t i = 0; i < sequence.size(); ++i) {
        const std::uint8_t input = sequence[i];
        const std::uint8_t target = sequence[(i + 1) % sequence.size()];
        const auto pred = hop.predict(code(input));
        if (!pred.abstain && pred.token == target) ++correct;
    }
    CHECK_EQ(correct, sequence.size());
    CHECK_EQ(hop.used_slots(), 8u);

    // A held-out sequence over the same learned transition graph.
    const std::array<std::uint8_t, 16> replay{
        0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7};
    std::size_t replay_correct = 0;
    for (std::size_t i = 0; i + 1 < replay.size(); ++i) {
        const auto pred = hop.predict(code(replay[i]));
        if (!pred.abstain && pred.token == replay[i + 1]) ++replay_correct;
    }
    CHECK_EQ(replay_correct, replay.size() - 1);

    return test_done("Hopfield token-sequence learning");
}
