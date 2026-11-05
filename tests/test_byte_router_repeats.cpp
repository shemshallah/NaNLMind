#include "nanlm/learning_mesh.hpp"
#include "test_util.hpp"

#include <fstream>
#include <iomanip>
#include <iterator>
#include <vector>

using namespace nanlm;

namespace {
double eval_hopfield(const BootstrapMesh& mesh, const std::vector<std::uint8_t>& data,
                     std::size_t begin, std::size_t end) {
    std::size_t correct = 0, n = 0;
    for (std::size_t i = begin + 1; i < end && i < data.size(); ++i) {
        const auto p = mesh.bootstrap().predict(
            HopfieldRouter::token_code(data[i - 1]));
        if (!p.abstain && p.token == data[i]) ++correct;
        ++n;
    }
    return n ? static_cast<double>(correct) / n : 0.0;
}
double eval_bigram(const ByteBigram& counts, const std::vector<std::uint8_t>& data,
                   std::size_t begin, std::size_t end) {
    std::size_t correct = 0, n = 0;
    for (std::size_t i = begin + 1; i < end && i < data.size(); ++i) {
        if (counts.predict(data[i - 1]) == data[i]) ++correct;
        ++n;
    }
    return n ? static_cast<double>(correct) / n : 0.0;
}
} // namespace

int main() {
    std::ifstream f("data/alice_excerpt.txt", std::ios::binary);
    CHECK(f.good());
    std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                   std::istreambuf_iterator<char>());
    if (data.size() < 1000) return test_done("byte router repeats (skipped)");
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
    ByteBigram counts;
    counts.train(data, 0, subtrain);
    ExpertRouter router;

    std::cout << std::fixed << std::setprecision(4);
    for (int pass = 1; pass <= 10; ++pass) {
        for (std::size_t i = 1; i < subtrain; ++i) {
            mesh.step(HopfieldRouter::token_code(data[i - 1]), data[i]);
        }
        const double hop = eval_hopfield(mesh, data, split, data.size());
        const double big = eval_bigram(counts, data, split, data.size());

        // Refresh validation evidence each pass.
        for (std::size_t i = subtrain + 1; i < split; ++i) {
            const auto hp = mesh.bootstrap().predict(
                HopfieldRouter::token_code(data[i - 1]));
            router.observe(0, !hp.abstain &&
                hp.token == data[i]);
            router.observe(1, counts.predict(data[i - 1]) == data[i]);
        }
        const std::uint8_t chosen = router.choose();
        const double routed = chosen == 0 ? hop : big;
        std::cout << "pass=" << pass << " hop=" << hop
                  << " bigram=" << big << " routed=" << routed
                  << " chosen=" << (chosen == 0 ? "hopfield" : "bigram")
                  << " traces=" << mesh.mind().traces() << "\n";
    }
    return test_done("10-pass byte router measurement");
}
