#include "nanlm/learning_mesh.hpp"
#include "test_util.hpp"

#include <fstream>
#include <iterator>
#include <vector>

using namespace nanlm;

int main() {
    std::ifstream f("data/alice_excerpt.txt", std::ios::binary);
    CHECK(f.good());
    std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                   std::istreambuf_iterator<char>());
    if (data.size() < 1000) return test_done("byte expert router (skipped)");
    const std::size_t split = (data.size() * 4) / 5;
    const std::size_t subtrain = (split * 4) / 5;

    HopfieldConfig cfg;
    cfg.top_k = 8;
    cfg.max_strength = 16;
    BootstrapMesh mesh(cfg, 8);
    for (std::uint16_t b = 0; b < 256; ++b) {
        mesh.bootstrap().set_head(static_cast<std::uint8_t>(b),
                                  HopfieldRouter::token_code(static_cast<std::uint8_t>(b)));
    }
    for (int epoch = 0; epoch < 2; ++epoch) {
        for (std::size_t i = 1; i < subtrain; ++i) {
            mesh.step(HopfieldRouter::token_code(data[i - 1]), data[i]);
        }
    }

    ByteBigram counts;
    counts.train(data, 0, subtrain);

    // Validation chooses the expert; overbootstrap only sees correctness.
    ExpertRouter router;
    for (std::size_t i = subtrain + 1; i < split; ++i) {
        const auto hp = mesh.bootstrap().predict(
            HopfieldRouter::token_code(data[i - 1]));
        const std::uint8_t hpred = hp.abstain ? 0 : static_cast<std::uint8_t>(hp.token);
        router.observe(0, hpred == data[i]);
        router.observe(1, counts.predict(data[i - 1]) == data[i]);
    }
    const std::uint8_t chosen = router.choose();
    std::cout << "router chose " << (chosen == 0 ? "hopfield" : "bigram")
              << " validation totals " << router.total(0)
              << "/" << router.total(1) << "\n";

    std::size_t correct = 0;
    std::size_t evaluated = 0;
    for (std::size_t i = split + 1; i < data.size(); ++i) {
        std::uint8_t pred = counts.predict(data[i - 1]);
        if (chosen == 0) {
            const auto hp = mesh.bootstrap().predict(
                HopfieldRouter::token_code(data[i - 1]));
            pred = hp.abstain ? 0 : static_cast<std::uint8_t>(hp.token);
        }
        if (pred == data[i]) ++correct;
        ++evaluated;
    }
    const double acc = evaluated ? static_cast<double>(correct) / evaluated : 0.0;
    std::cout << "expert test top1=" << acc << " bytes=" << evaluated
              << " chosen=" << static_cast<unsigned>(chosen) << "\n";
    CHECK_EQ(router.total(0), router.total(1));
    CHECK(acc >= 0.18); // order-0 is 16.18% on this corpus
    return test_done("byte expert router");
}
