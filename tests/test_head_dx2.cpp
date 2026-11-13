#include "nanlm/head_page_loader.hpp"
#include "test_util.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <vector>

using namespace nanlm;

namespace {
void put_bf16(std::uint8_t* page, std::size_t offset, float value) {
    std::uint32_t bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));
    const std::uint16_t bf = static_cast<std::uint16_t>(bits >> 16);
    page[offset + 0] = static_cast<std::uint8_t>(bf & 0xFFu);
    page[offset + 1] = static_cast<std::uint8_t>(bf >> 8);
}
void identity_bf16(std::uint8_t* page, std::size_t base,
                   std::size_t rows, std::size_t cols) {
    for (std::size_t r = 0; r < rows && r < cols; ++r)
        put_bf16(page, base + (r * cols + r) * 2u, 1.0f);
}
void make_page(std::uint8_t* page) {
    for (std::size_t i = 0; i < HeadPageArena::kPageBytes; ++i) page[i] = 0;
    // Layers 0/1 are passthrough: all-zero weights leave the residual stream
    // unchanged, so the test can finite-difference the layer-2 input directly.
    const std::size_t base = 2u * 0x50000u;
    identity_bf16(page, base + 0x00000u, 128, 128);
    identity_bf16(page, base + 0x08000u, 128, 128);
    identity_bf16(page, base + 0x10000u, 128, 128);
    identity_bf16(page, base + 0x18000u, 128, 128);
    identity_bf16(page, base + 0x20000u, 384, 128);
    identity_bf16(page, base + 0x38000u, 128, 384);
    const std::uint32_t magic = 0x48315233u;
    for (unsigned i = 0; i < 4; ++i)
        page[0xFCC00 + i] = static_cast<std::uint8_t>(magic >> (8 * i));
}
double loss(const std::array<float, 6 * 128>& output,
            const std::array<float, 128>& target) {
    double l = 0.0;
    for (unsigned d = 0; d < 128u; ++d) {
        const double e = static_cast<double>(output[d]) - target[d];
        l += 0.5 * e * e;
    }
    return l;
}
} // namespace

int main() {
    RawFieldVM vm("build/head_worker.nan");
    CHECK(vm.ready());
    HeadPageArena arena;
    HeadPageLoader loader(vm, arena);
    make_page(arena.page(0));
    CHECK_EQ(loader.load(0), 0u);
    const auto before = loader.export_page(0);

    std::array<float, 6 * 128> context{};
    for (unsigned d = 0; d < 128u; ++d)
        context[d] = 0.01f * static_cast<float>(static_cast<int>(d) - 64);
    std::array<float, 128> target{};
    std::array<float, 128> output{}, dx2{};
    float norm = 0.0f;
    std::uint8_t reason = 0;
    CHECK(vm.native_head_page_train_dx2(context, 1, 0, target,
                                        output, dx2, norm, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(norm));
    CHECK(norm > 0.0f);
    CHECK(loader.export_page(0) == before);

    const double eps = 1e-2;
    double max_rel = 0.0;
    for (unsigned d : {0u, 1u, 17u, 64u, 127u}) {
        auto plus = context, minus = context;
        plus[d] += static_cast<float>(eps);
        minus[d] -= static_cast<float>(eps);
        std::array<float, 6 * 128> out_plus{}, out_minus{};
        std::uint8_t r1 = 0, r2 = 0;
        CHECK(vm.native_head_block6(plus, 1, 0, out_plus, r1));
        CHECK(vm.native_head_block6(minus, 1, 0, out_minus, r2));
        CHECK(r1 == 0u && r2 == 0u);
        const double fd = (loss(out_plus, target) - loss(out_minus, target)) /
                          (2.0 * eps);
        const double scale = std::max(1.0, static_cast<double>(std::fabs(dx2[d])));
        const double rel = std::fabs(fd - dx2[d]) / scale;
        max_rel = std::max(max_rel, rel);
    }
    CHECK(max_rel < 5e-2);

    std::array<float, 128> bad_out{}, bad_dx{};
    CHECK(vm.native_head_page_train_dx2(context, 2, 0, target,
                                        bad_out, bad_dx, norm, reason));
    CHECK_EQ(reason, 1u);
    CHECK(vm.native_head_page_train_dx2(context, 1, 16, target,
                                        bad_out, bad_dx, norm, reason));
    CHECK_EQ(reason, 1u);

    return test_done("native layer-2 dX2 reverse");
}
