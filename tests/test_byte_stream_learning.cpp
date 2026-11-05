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
    if (data.size() < 1000) return test_done("byte-stream learning gate (skipped)");
    const std::size_t split = (data.size() * 4) / 5;

    HopfieldConfig cfg;
    cfg.top_k = 8;
    cfg.max_strength = 16;
    BootstrapMesh mesh(cfg, 8);
    for (std::uint16_t b = 0; b < 256; ++b) {
        mesh.bootstrap().set_head(static_cast<std::uint8_t>(b),
                                  HopfieldRouter::token_code(static_cast<std::uint8_t>(b)));
    }

    // Train on the first 80% as consecutive byte transitions.
    std::size_t train_steps = 0;
    for (int epoch = 0; epoch < 2; ++epoch) {
        for (std::size_t i = 1; i < split; ++i) {
            CHECK(mesh.step(HopfieldRouter::token_code(data[i - 1]), data[i]));
            ++train_steps;
        }
    }

    std::array<std::size_t, 256> freq{};
    for (std::size_t i = 0; i < split; ++i) ++freq[data[i]];
    const std::uint8_t fallback = static_cast<std::uint8_t>(
        std::max_element(freq.begin(), freq.end()) - freq.begin());

    std::size_t correct = 0;
    std::size_t hybrid_correct = 0;
    std::size_t evaluated = 0;
    for (std::size_t i = split + 1; i < data.size(); ++i) {
        const auto pred = mesh.bootstrap().predict(
            HopfieldRouter::token_code(data[i - 1]));
        if (!pred.abstain && pred.token == data[i]) ++correct;
        const std::uint8_t chosen = pred.abstain ? fallback
                                                : static_cast<std::uint8_t>(pred.token);
        if (chosen == data[i]) ++hybrid_correct;
        ++evaluated;
    }
    const double acc = evaluated ? static_cast<double>(correct) / evaluated : 0.0;
    const double hybrid = evaluated ? static_cast<double>(hybrid_correct) / evaluated : 0.0;
    std::cout << "alice excerpt bytes=" << data.size()
              << " train_steps=" << train_steps
              << " test=" << evaluated
              << " top1=" << acc
              << " hybrid_top1=" << hybrid
              << " fallback=" << static_cast<unsigned>(fallback)
              << " slots=" << mesh.bootstrap().used_slots()
              << " traces=" << mesh.mind().traces() << "\n";

    CHECK(evaluated > 0);
    CHECK(mesh.mind().traces() == train_steps);
    CHECK(mesh.bootstrap().used_slots() > 0);
    // Order-0 top-1 on this corpus is about 16.18%; require a clear margin.
    CHECK(acc >= 0.18 || hybrid >= 0.18);

    return test_done("byte-stream two-rate learning");
}
