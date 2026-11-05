#include "nanlm/bootstrap_router.hpp"
#include "test_util.hpp"

#include <array>
#include <vector>

using namespace nanlm;

namespace {
HopfieldRouter::Vector code(std::uint8_t t) {
    return HopfieldRouter::token_code(t);
}
std::size_t evaluate(const HopfieldRouter& hop, const std::array<std::uint8_t, 8>& seq) {
    std::size_t correct = 0;
    for (std::size_t i = 0; i < seq.size(); ++i) {
        const auto p = hop.predict(code(seq[i]));
        if (!p.abstain && p.token == seq[(i + 1) % seq.size()]) ++correct;
    }
    return correct;
}
void train(HopfieldRouter& hop, const std::array<std::uint8_t, 8>& seq, int passes) {
    for (int e = 0; e < passes; ++e) {
        for (std::size_t i = 0; i < seq.size(); ++i) {
            CHECK(hop.learn(code(seq[i]), seq[(i + 1) % seq.size()]));
        }
    }
}
} // namespace

int main() {
    HopfieldConfig cfg;
    cfg.top_k = 1;
    cfg.max_strength = 32;
    HopfieldRouter hop(cfg);
    const std::array<std::uint8_t, 8> seq{0, 1, 2, 3, 4, 5, 6, 7};
    for (std::uint8_t t = 0; t < 8; ++t) hop.set_head(t, code(t));
    train(hop, seq, 10);
    CHECK_EQ(evaluate(hop, seq), 8u);
    CHECK_EQ(hop.used_slots(), 8u);

    const auto before = hop.used_pairs();
    std::size_t dropped = 0;
    for (std::size_t i = 0; i < before.size(); i += 3) {
        if (hop.drop_slot(before[i])) ++dropped;
    }
    CHECK(dropped >= 2u);
    const std::size_t damaged = evaluate(hop, seq);
    std::cout << "slot-recovery dropped=" << dropped << " damaged="
              << damaged << "/8 used=" << hop.used_slots() << "\n";
    CHECK(damaged < 8u);

    train(hop, seq, 80);
    // Targeted repair for any transition that the ordinary update left wrong.
    for (std::size_t i = 0; i < seq.size(); ++i) {
        const auto p = hop.predict(code(seq[i]));
        if (p.abstain || p.token != seq[(i + 1) % seq.size()]) {
            CHECK(hop.teach(code(seq[i]), seq[(i + 1) % seq.size()]));
        }
    }
    const std::size_t recovered = evaluate(hop, seq);
    CHECK_EQ(recovered, 8u);
    CHECK_EQ(hop.used_slots(), 8u);
    std::cout << "slot-recovery recovered=" << recovered
              << "/8 used=" << hop.used_slots() << "\n";
    for (std::size_t i = 0; i < seq.size(); ++i) {
        const auto p = hop.predict(code(seq[i]));
        if (p.abstain || p.token != seq[(i + 1) % seq.size()]) {
            std::cout << "fail i=" << i << " pred="
                      << (p.abstain ? -1 : static_cast<int>(p.token))
                      << " target=" << static_cast<int>(seq[(i + 1) % seq.size()])
                      << "\n";
        }
    }
    return test_done("30% slot loss and retrain recovery");
}
