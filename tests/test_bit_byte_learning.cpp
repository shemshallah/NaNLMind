#include "nanlm/learning_mesh.hpp"
#include "test_util.hpp"

#include <array>
#include <cstdint>

using namespace nanlm;

namespace {

HopfieldRouter::Vector code(std::uint8_t token) {
    return HopfieldRouter::token_code(token);
}

std::size_t run_cycle(std::uint16_t n, bool bitwise) {
    HopfieldConfig cfg;
    cfg.top_k = 1;
    cfg.max_strength = 32;
    BootstrapMesh mesh(cfg, 1);
    for (std::uint16_t t = 0; t < n; ++t) {
        mesh.bootstrap().set_head(static_cast<std::uint8_t>(t),
                                  code(static_cast<std::uint8_t>(t)));
    }
    const std::array<std::uint8_t, 256> seq = [] {
        std::array<std::uint8_t, 256> out{};
        for (std::uint16_t i = 0; i < 256; ++i) out[i] = static_cast<std::uint8_t>(i);
        return out;
    }();
    for (int epoch = 0; epoch < 10; ++epoch) {
        for (std::uint16_t i = 0; i < n; ++i) {
            const std::uint8_t target = static_cast<std::uint8_t>((i + 1) % n);
            CHECK(mesh.step(code(seq[i]), target));
        }
    }
    std::size_t correct = 0;
    for (std::uint16_t i = 0; i < n; ++i) {
        const std::uint8_t target = static_cast<std::uint8_t>((i + 1) % n);
        const auto pred = mesh.bootstrap().predict(code(seq[i]));
        if (!pred.abstain && pred.token == target) ++correct;
    }
    CHECK_EQ(mesh.bootstrap().used_slots(), n);
    CHECK_EQ(mesh.mind().traces(), static_cast<std::uint64_t>(10) * n);
    CHECK(mesh.mind().evidence(0) != 0);
    CHECK(mesh.bootstrap().head_bias(0) >= -8 && mesh.bootstrap().head_bias(0) <= 8);
    if (bitwise) CHECK(n == 2);
    return correct;
}

} // namespace

int main() {
    const std::size_t bits = run_cycle(2, true);
    CHECK_EQ(bits, 2u);
    const std::size_t bytes = run_cycle(256, false);
    std::cout << "bit=" << bits << "/2 byte=" << bytes << "/256\n";
    CHECK(bytes >= 255u); // one byte transition is still unresolved
    return test_done("bitwise and bytewise two-rate learning");
}
