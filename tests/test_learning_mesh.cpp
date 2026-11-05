#include "nanlm/learning_mesh.hpp"
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
    cfg.top_k = 1;
    cfg.max_strength = 32;
    BootstrapMesh mesh(cfg, 1);
    for (std::uint8_t t = 0; t < 8; ++t) mesh.bootstrap().set_head(t, code(t));

    const std::array<std::uint8_t, 8> seq{0, 1, 2, 3, 4, 5, 6, 7};
    for (int epoch = 0; epoch < 10; ++epoch) {
        for (std::size_t i = 0; i < seq.size(); ++i) {
            CHECK(mesh.step(code(seq[i]), seq[(i + 1) % seq.size()]));
        }
    }

    std::size_t correct = 0;
    for (std::size_t i = 0; i < seq.size(); ++i) {
        const auto pred = mesh.bootstrap().predict(code(seq[i]));
        if (!pred.abstain && pred.token == seq[(i + 1) % seq.size()]) ++correct;
    }
    CHECK_EQ(correct, seq.size());
    CHECK_EQ(mesh.mind().traces(), 80u);
    CHECK(mesh.mind().evidence(0) != 0);
    CHECK(mesh.bootstrap().head_bias(0) != 0);

    // Meta-feedback is bounded and does not replace bootstrap's local keys.
    const auto fb = mesh.mind().feedback();
    for (auto b : fb) CHECK(b >= -8 && b <= 8);
    CHECK(mesh.mind().digest() == mesh.mind().digest());

    return test_done("two-rate bootstrap/overbootstrap learning mesh");
}
