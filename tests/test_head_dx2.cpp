#include "nanlm/head_page_loader.hpp"
#include "test_util.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <iostream>
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
double loss_last(const std::array<float, 6 * 128>& output,
                 const std::array<float, 128>& target,
                 unsigned tokens) {
    double l = 0.0;
    const unsigned base = (tokens - 1u) * 128u;
    for (unsigned d = 0; d < 128u; ++d) {
        const double e = static_cast<double>(output[base + d]) - target[d];
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
    const double eps = 1e-2;

    // T=2 first: this also checks that the new path derives the page base on
    // its own instead of relying on an earlier T=1 call. The second token is
    // nonzero. mth_head_block6 uses an unmasked two-key softmax, so both key
    // columns participate in dK/dV.
    std::array<float, 6 * 128> context2{};
    for (unsigned d = 0; d < 128u; ++d) {
        context2[d] = 0.01f * static_cast<float>(static_cast<int>(d) - 64);
        context2[128u + d] = 0.013f * std::sin(0.37f * static_cast<float>(d)) +
                             0.002f * static_cast<float>(d);
    }
    std::array<float, 128> target2{};
    for (unsigned d = 0; d < 128u; ++d)
        target2[d] = 0.011f * std::cos(0.23f * static_cast<float>(d)) -
                     0.004f * static_cast<float>(d);
    std::array<float, 6 * 128> output2{}, dx2_2{};
    float norm2 = 0.0f;
    std::uint8_t reason = 0;
    CHECK(vm.native_head_page_train_dx2(context2, 2, 0, target2,
                                        output2, dx2_2, norm2, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(norm2));
    CHECK(norm2 > 0.0f);
    CHECK(loader.export_page(0) == before);

    std::array<float, 6 * 128> reference2{};
    std::uint8_t ref_reason = 0;
    CHECK(vm.native_head_block6(context2, 2, 0, reference2, ref_reason));
    CHECK_EQ(ref_reason, 0u);
    for (unsigned i = 0; i < 2u * 128u; ++i)
        CHECK(reference2[i] == output2[i]);

    double max_rel_t2 = 0.0;
    for (unsigned index : {0u, 1u, 3u, 17u, 42u, 64u, 100u, 127u,
                           128u, 129u, 131u, 145u, 170u, 192u, 228u, 255u}) {
        const unsigned token = index / 128u;
        const unsigned d = index % 128u;
        auto plus = context2, minus = context2;
        plus[token * 128u + d] += static_cast<float>(eps);
        minus[token * 128u + d] -= static_cast<float>(eps);
        std::array<float, 6 * 128> out_plus{}, out_minus{};
        std::uint8_t r1 = 0, r2 = 0;
        CHECK(vm.native_head_block6(plus, 2, 0, out_plus, r1));
        CHECK(vm.native_head_block6(minus, 2, 0, out_minus, r2));
        CHECK(r1 == 0u && r2 == 0u);
        const double fd = (loss_last(out_plus, target2, 2) -
                           loss_last(out_minus, target2, 2)) /
                          (2.0 * eps);
        const double scale =
            std::max(1.0, static_cast<double>(std::fabs(dx2_2[index])));
        const double rel = std::fabs(fd - dx2_2[index]) / scale;
        max_rel_t2 = std::max(max_rel_t2, rel);
    }
    CHECK(max_rel_t2 < 5e-2);

    // T=1 compatibility overload: exact layer-2 dX2 against central
    // differences of the guest forward.
    std::array<float, 6 * 128> context{};
    for (unsigned d = 0; d < 128u; ++d)
        context[d] = 0.01f * static_cast<float>(static_cast<int>(d) - 64);
    std::array<float, 128> target{};
    std::array<float, 128> output{}, dx2{};
    float norm = 0.0f;
    CHECK(vm.native_head_page_train_dx2(context, 1, 0, target,
                                        output, dx2, norm, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(norm));
    CHECK(norm > 0.0f);
    CHECK(loader.export_page(0) == before);

    double max_rel_t1 = 0.0;
    for (unsigned d : {0u, 1u, 17u, 64u, 127u}) {
        auto plus = context, minus = context;
        plus[d] += static_cast<float>(eps);
        minus[d] -= static_cast<float>(eps);
        std::array<float, 6 * 128> out_plus{}, out_minus{};
        std::uint8_t r1 = 0, r2 = 0;
        CHECK(vm.native_head_block6(plus, 1, 0, out_plus, r1));
        CHECK(vm.native_head_block6(minus, 1, 0, out_minus, r2));
        CHECK(r1 == 0u && r2 == 0u);
        const double fd = (loss_last(out_plus, target, 1) -
                           loss_last(out_minus, target, 1)) /
                          (2.0 * eps);
        const double scale = std::max(1.0, static_cast<double>(std::fabs(dx2[d])));
        const double rel = std::fabs(fd - dx2[d]) / scale;
        max_rel_t1 = std::max(max_rel_t1, rel);
    }
    CHECK(max_rel_t1 < 5e-2);

    // The new T=1 path must reproduce the compatibility overload exactly.
    std::array<float, 6 * 128> out_t1{}, dx_t1{};
    float norm_t1 = 0.0f;
    CHECK(vm.native_head_page_train_dx2(context, 1, 0, target,
                                        out_t1, dx_t1, norm_t1, reason));
    CHECK_EQ(reason, 0u);
    for (unsigned d = 0; d < 128u; ++d) {
        CHECK(out_t1[d] == output[d]);
        CHECK(dx_t1[d] == dx2[d]);
    }

    // T>2 stays rejected, as does an out-of-range slot. The compatibility
    // overload remains T=1-only.
    std::array<float, 6 * 128> bad_out{}, bad_dx{};
    CHECK(vm.native_head_page_train_dx2(context2, 3, 0, target2,
                                        bad_out, bad_dx, norm2, reason));
    CHECK_EQ(reason, 1u);
    CHECK(vm.native_head_page_train_dx2(context2, 2, 16, target2,
                                        bad_out, bad_dx, norm2, reason));
    CHECK_EQ(reason, 1u);
    std::array<float, 128> old_out{}, old_dx{};
    CHECK(vm.native_head_page_train_dx2(context2, 2, 0, target2,
                                        old_out, old_dx, norm2, reason));
    CHECK_EQ(reason, 1u);

    std::cout << "max relative gradient error: T=1 " << max_rel_t1
              << ", T=2 " << max_rel_t2 << "\n";
    return test_done("native layer-2 dX2 reverse");
}
