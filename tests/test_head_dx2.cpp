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
void identity_bf16_scaled(std::uint8_t* page, std::size_t base,
                          std::size_t rows, std::size_t cols, float scale) {
    for (std::size_t r = 0; r < rows && r < cols; ++r)
        put_bf16(page, base + (r * cols + r) * 2u, scale);
}
// Every layer is an identity block, so all three reverse stages contribute.
// The optional per-layer scale keeps the layer weights distinct, which catches
// a reverse that accidentally reuses one layer's page weights for another.
void make_identity_page(std::uint8_t* page,
                        const std::array<float, 3>& layer_scale) {
    for (std::size_t i = 0; i < HeadPageArena::kPageBytes; ++i) page[i] = 0;
    for (std::size_t layer = 0; layer < 3; ++layer) {
        const std::size_t base = layer * 0x50000u;
        const float scale = layer_scale[layer];
        identity_bf16_scaled(page, base + 0x00000u, 128, 128, scale);
        identity_bf16_scaled(page, base + 0x08000u, 128, 128, scale);
        identity_bf16_scaled(page, base + 0x10000u, 128, 128, scale);
        identity_bf16_scaled(page, base + 0x18000u, 128, 128, scale);
        identity_bf16_scaled(page, base + 0x20000u, 384, 128, scale);
        identity_bf16_scaled(page, base + 0x38000u, 128, 384, scale);
    }
    const std::uint32_t magic = 0x48315233u;
    for (unsigned i = 0; i < 4; ++i)
        page[0xFCC00 + i] = static_cast<std::uint8_t>(magic >> (8 * i));
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
// Central difference of the guest forward on sampled context coordinates.
// The same relative-error scale as the opcode137 test is used.
double max_rel_error(RawFieldVM& vm,
                     const std::array<float, 6 * 128>& context,
                     unsigned tokens, unsigned slot,
                     const std::array<float, 128>& target,
                     const std::array<float, 6 * 128>& dx0,
                     const std::vector<unsigned>& indices, double eps) {
    double max_rel = 0.0;
    for (unsigned index : indices) {
        const unsigned token = index / 128u;
        const unsigned d = index % 128u;
        auto plus = context, minus = context;
        plus[token * 128u + d] += static_cast<float>(eps);
        minus[token * 128u + d] -= static_cast<float>(eps);
        std::array<float, 6 * 128> out_plus{}, out_minus{};
        std::uint8_t r1 = 0, r2 = 0;
        CHECK(vm.native_head_block6(plus, static_cast<std::uint8_t>(tokens),
                                    static_cast<std::uint8_t>(slot),
                                    out_plus, r1));
        CHECK(vm.native_head_block6(minus, static_cast<std::uint8_t>(tokens),
                                    static_cast<std::uint8_t>(slot),
                                    out_minus, r2));
        CHECK(r1 == 0u && r2 == 0u);
        const double fd = (loss_last(out_plus, target, tokens) -
                           loss_last(out_minus, target, tokens)) /
                          (2.0 * eps);
        const double scale =
            std::max(1.0, static_cast<double>(std::fabs(dx0[index])));
        max_rel = std::max(max_rel, std::fabs(fd - dx0[index]) / scale);
    }
    return max_rel;
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

    // Opcode138: full dX0 reverse. The primary check uses an all-identity
    // page for every layer (not passthrough layers 0/1), so the reverse must
    // traverse all three layers. A second page scales each layer differently,
    // which fails if a reverse stage reuses another layer's weights.
    make_identity_page(arena.page(1), {1.0f, 1.0f, 1.0f});
    make_identity_page(arena.page(2), {0.5f, 0.75f, 1.0f});
    const std::size_t slot_identity = loader.load(1);
    const std::size_t slot_scaled = loader.load(2);
    CHECK_EQ(slot_identity, 1u);
    CHECK_EQ(slot_scaled, 2u);
    const auto before_identity = loader.export_page(slot_identity);
    const auto before_scaled = loader.export_page(slot_scaled);

    // Unit-scale inputs keep the all-identity stack well conditioned without
    // reducing the forward step, so the check measures the reverse, not
    // LayerNorm amplification of a tiny residual stream.
    std::array<float, 6 * 128> gctx1{}, gctx2{};
    std::array<float, 128> gtarget{};
    for (unsigned d = 0; d < 128u; ++d) {
        const float centered = static_cast<float>(static_cast<int>(d) - 64) / 64.0f;
        gctx1[d] = std::sin(0.11f * static_cast<float>(d)) + 0.20f * centered;
        gctx2[d] = std::cos(0.07f * static_cast<float>(d)) + 0.15f * centered;
        gctx2[128u + d] =
            std::sin(0.29f * static_cast<float>(d)) - 0.10f * centered;
        gtarget[d] = 0.40f * std::cos(0.17f * static_cast<float>(d)) -
                     0.15f * centered;
    }
    const std::vector<unsigned> samples1{0u, 1u, 7u, 17u, 33u, 64u, 95u, 127u};
    const std::vector<unsigned> samples2{0u,  1u,   7u,   17u,  33u,  64u,
                                         95u, 127u, 128u, 129u, 135u, 145u,
                                         161u, 192u, 223u, 255u};

    std::array<float, 6 * 128> gdx1{}, gdx2{};
    float gnorm1 = 0.0f, gnorm2 = 0.0f;
    CHECK(vm.native_head_page_train_dx0(gctx1, 1,
                                        static_cast<std::uint8_t>(slot_identity),
                                        gtarget, gdx1, gnorm1, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(gnorm1));
    CHECK(gnorm1 > 0.0f);
    CHECK(loader.export_page(slot_identity) == before_identity);
    const double dx0_id_t1 =
        max_rel_error(vm, gctx1, 1, static_cast<unsigned>(slot_identity),
                      gtarget, gdx1, samples1, eps);
    CHECK(dx0_id_t1 < 5e-2);

    CHECK(vm.native_head_page_train_dx0(gctx2, 2,
                                        static_cast<std::uint8_t>(slot_identity),
                                        gtarget, gdx2, gnorm2, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(gnorm2));
    CHECK(gnorm2 > 0.0f);
    CHECK(loader.export_page(slot_identity) == before_identity);
    const double dx0_id_t2 =
        max_rel_error(vm, gctx2, 2, static_cast<unsigned>(slot_identity),
                      gtarget, gdx2, samples2, eps);
    CHECK(dx0_id_t2 < 5e-2);

    std::array<float, 6 * 128> gdx1s{}, gdx2s{};
    CHECK(vm.native_head_page_train_dx0(gctx1, 1,
                                        static_cast<std::uint8_t>(slot_scaled),
                                        gtarget, gdx1s, gnorm1, reason));
    CHECK_EQ(reason, 0u);
    CHECK(loader.export_page(slot_scaled) == before_scaled);
    const double dx0_scaled_t1 =
        max_rel_error(vm, gctx1, 1, static_cast<unsigned>(slot_scaled),
                      gtarget, gdx1s, samples1, eps);
    CHECK(dx0_scaled_t1 < 5e-2);

    CHECK(vm.native_head_page_train_dx0(gctx2, 2,
                                        static_cast<std::uint8_t>(slot_scaled),
                                        gtarget, gdx2s, gnorm2, reason));
    CHECK_EQ(reason, 0u);
    CHECK(loader.export_page(slot_scaled) == before_scaled);
    const double dx0_scaled_t2 =
        max_rel_error(vm, gctx2, 2, static_cast<unsigned>(slot_scaled),
                      gtarget, gdx2s, samples2, eps);
    CHECK(dx0_scaled_t2 < 5e-2);

    // With layers 0/1 left at zero weights, both are forward identities and
    // their reverse is also an identity, so dX0 must equal opcode137's dX2.
    std::array<float, 6 * 128> dx0_passthrough{};
    float norm_passthrough = 0.0f;
    CHECK(vm.native_head_page_train_dx0(context2, 2, 0, target2,
                                        dx0_passthrough, norm_passthrough,
                                        reason));
    CHECK_EQ(reason, 0u);
    CHECK(loader.export_page(0) == before);
    double max_passthrough_diff = 0.0;
    for (unsigned i = 0; i < 2u * 128u; ++i)
        max_passthrough_diff =
            std::max(max_passthrough_diff,
                     std::fabs(static_cast<double>(dx0_passthrough[i]) -
                               static_cast<double>(dx2_2[i])));
    CHECK(max_passthrough_diff < 1e-4);

    // Opcode138 has the same input limits as opcode137.
    CHECK(vm.native_head_page_train_dx0(context2, 3, 0, target2,
                                        gdx2, gnorm2, reason));
    CHECK_EQ(reason, 1u);
    CHECK(vm.native_head_page_train_dx0(context2, 2, 16, target2,
                                        gdx2, gnorm2, reason));
    CHECK_EQ(reason, 1u);

    std::cout << "max relative gradient error: dX2 T=1 " << max_rel_t1
              << ", dX2 T=2 " << max_rel_t2 << "\n"
              << "max relative gradient error: dX0 identity T=1 " << dx0_id_t1
              << ", T=2 " << dx0_id_t2 << "\n"
              << "max relative gradient error: dX0 scaled T=1 "
              << dx0_scaled_t1 << ", T=2 " << dx0_scaled_t2 << "\n"
              << "max |dX0-dX2| on passthrough page: "
              << max_passthrough_diff << "\n";
    return test_done("native layer-2 dX2 and full dX0 reverse");
}
