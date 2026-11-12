#include "nanlm/head_page_loader.hpp"
#include "test_util.hpp"

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
    for (std::size_t layer = 0; layer < 3; ++layer) {
        const std::size_t base = layer * 0x50000u;
        identity_bf16(page, base + 0x00000u, 128, 128);
        identity_bf16(page, base + 0x08000u, 128, 128);
        identity_bf16(page, base + 0x10000u, 128, 128);
        identity_bf16(page, base + 0x18000u, 128, 128);
        identity_bf16(page, base + 0x20000u, 384, 128);
        identity_bf16(page, base + 0x38000u, 128, 384);
    }
    const std::uint32_t magic = 0x48315233u;
    for (unsigned i = 0; i < 4; ++i)
        page[0xFCC00 + i] = static_cast<std::uint8_t>(magic >> (8 * i));
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
    CHECK_EQ(before.size(), HeadPageArena::kPageBytes);

    std::array<float, 6 * 128> context{};
    context[0] = 1.0f;
    std::array<float, 128> target{};
    std::array<float, 6 * 128> output{};
    float error_norm = 0.0f;
    std::uint8_t reason = 0;
    CHECK(vm.native_head_page_train(context, 1, 0, target, 0.1f,
                                    output, error_norm, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(error_norm));
    CHECK(error_norm > 0.0f);
    bool finite = true;
    for (float value : output) finite = finite && std::isfinite(value);
    CHECK(finite);

    const auto after = loader.export_page(0);
    CHECK_EQ(after.size(), HeadPageArena::kPageBytes);
    CHECK(after[0xFCC00] == before[0xFCC00]);
    CHECK(after[0xFCC01] == before[0xFCC01]);
    bool w2_changed = false;
    for (std::size_t i = 0xD8000u; i < 0xE0000u; ++i)
        if (after[i] != before[i]) w2_changed = true;
    CHECK(w2_changed);

    // Fresh page: update the final attention output projection Wo instead.
    make_page(arena.page(0));
    loader.clear();
    CHECK_EQ(loader.load(0), 0u);
    const auto before_wo = loader.export_page(0);
    CHECK(vm.native_head_page_train(context, 1, 0, target, 0.1f,
                                    output, error_norm, reason, true));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(error_norm));
    CHECK(error_norm > 0.0f);
    const auto after_wo = loader.export_page(0);
    CHECK(after_wo[0xFCC00] == before_wo[0xFCC00]);
    bool wo_changed = false;
    for (std::size_t i = 0xB8000u; i < 0xC0000u; ++i)
        if (after_wo[i] != before_wo[i]) wo_changed = true;
    CHECK(wo_changed);

    // Fresh page: update W1 through the final W2 gradient.
    make_page(arena.page(0));
    loader.clear();
    CHECK_EQ(loader.load(0), 0u);
    const auto before_w1 = loader.export_page(0);
    CHECK(vm.native_head_page_train_w1(context, 1, 0, target, 0.1f,
                                       output, error_norm, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(error_norm));
    CHECK(error_norm > 0.0f);
    const auto after_w1 = loader.export_page(0);
    CHECK(after_w1[0xFCC00] == before_w1[0xFCC00]);
    bool w1_changed = false;
    for (std::size_t i = 0xC0000u; i < 0xD8000u; ++i)
        if (after_w1[i] != before_w1[i]) w1_changed = true;
    CHECK(w1_changed);

    // Fresh page: update the final value projection Wv.
    make_page(arena.page(0));
    loader.clear();
    CHECK_EQ(loader.load(0), 0u);
    const auto before_wv = loader.export_page(0);
    CHECK(vm.native_head_page_train_wv(context, 1, 0, target, 0.1f,
                                       output, error_norm, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(error_norm));
    CHECK(error_norm > 0.0f);
    const auto after_wv = loader.export_page(0);
    CHECK(after_wv[0xFCC00] == before_wv[0xFCC00]);
    bool wv_changed = false;
    for (std::size_t i = 0xB0000u; i < 0xB8000u; ++i)
        if (after_wv[i] != before_wv[i]) wv_changed = true;
    CHECK(wv_changed);

    // Fresh page: update final Wq/Wk through the softmax score path.
    make_page(arena.page(0));
    loader.clear();
    CHECK_EQ(loader.load(0), 0u);
    const auto before_qk = loader.export_page(0);
    auto context_multi = context;
    context_multi[128] = 0.5f;
    CHECK(vm.native_head_page_train_qk(context_multi, 2, 0, target, 0.1f,
                                       output, error_norm, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(error_norm));
    CHECK(error_norm > 0.0f);
    const auto after_qk = loader.export_page(0);
    CHECK(after_qk[0xFCC00] == before_qk[0xFCC00]);
    bool wq_changed = false, wk_changed = false;
    for (std::size_t i = 0xA0000u; i < 0xA8000u; ++i)
        if (after_qk[i] != before_qk[i]) wq_changed = true;
    for (std::size_t i = 0xA8000u; i < 0xB0000u; ++i)
        if (after_qk[i] != before_qk[i]) wk_changed = true;
    CHECK(wq_changed);
    CHECK(wk_changed);

    // Fresh page: local layer-1 W2 update from the final output error.
    make_page(arena.page(0));
    loader.clear();
    CHECK_EQ(loader.load(0), 0u);
    const auto before_l1 = loader.export_page(0);
    CHECK(vm.native_head_page_train_l1w2(context, 1, 0, target, 0.1f,
                                         output, error_norm, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(error_norm));
    CHECK(error_norm > 0.0f);
    const auto after_l1 = loader.export_page(0);
    CHECK(after_l1[0xFCC00] == before_l1[0xFCC00]);
    bool l1w2_changed = false;
    for (std::size_t i = 0x88000u; i < 0xA0000u; ++i)
        if (after_l1[i] != before_l1[i]) l1w2_changed = true;
    CHECK(l1w2_changed);

    // Fresh page: local layer-1 W1 update.
    make_page(arena.page(0));
    loader.clear();
    CHECK_EQ(loader.load(0), 0u);
    const auto before_l1w1 = loader.export_page(0);
    CHECK(vm.native_head_page_train_l1w1(context, 1, 0, target, 0.1f,
                                         output, error_norm, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(error_norm));
    CHECK(error_norm > 0.0f);
    const auto after_l1w1 = loader.export_page(0);
    CHECK(after_l1w1[0xFCC00] == before_l1w1[0xFCC00]);
    bool l1w1_changed = false;
    for (std::size_t i = 0x70000u; i < 0x88000u; ++i)
        if (after_l1w1[i] != before_l1w1[i]) l1w1_changed = true;
    CHECK(l1w1_changed);

    // Fresh page: local layer-1 Wo update.
    make_page(arena.page(0));
    loader.clear();
    CHECK_EQ(loader.load(0), 0u);
    const auto before_l1wo = loader.export_page(0);
    CHECK(vm.native_head_page_train_l1wo(context, 1, 0, target, 0.1f,
                                         output, error_norm, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(error_norm));
    CHECK(error_norm > 0.0f);
    const auto after_l1wo = loader.export_page(0);
    CHECK(after_l1wo[0xFCC00] == before_l1wo[0xFCC00]);
    bool l1wo_changed = false;
    for (std::size_t i = 0x68000u; i < 0x70000u; ++i)
        if (after_l1wo[i] != before_l1wo[i]) l1wo_changed = true;
    CHECK(l1wo_changed);

    // Fresh page: local layer-1 Wv update.
    make_page(arena.page(0));
    loader.clear();
    CHECK_EQ(loader.load(0), 0u);
    const auto before_l1wv = loader.export_page(0);
    CHECK(vm.native_head_page_train_l1wv(context, 1, 0, target, 0.1f,
                                         output, error_norm, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(error_norm));
    CHECK(error_norm > 0.0f);
    const auto after_l1wv = loader.export_page(0);
    CHECK(after_l1wv[0xFCC00] == before_l1wv[0xFCC00]);
    bool l1wv_changed = false;
    for (std::size_t i = 0x60000u; i < 0x68000u; ++i)
        if (after_l1wv[i] != before_l1wv[i]) l1wv_changed = true;
    CHECK(l1wv_changed);

    // Fresh page: local layer-1 Q/K update with two tokens.
    make_page(arena.page(0));
    loader.clear();
    CHECK_EQ(loader.load(0), 0u);
    const auto before_l1qk = loader.export_page(0);
    CHECK(vm.native_head_page_train_l1qk(context_multi, 2, 0, target, 0.1f,
                                         output, error_norm, reason));
    CHECK_EQ(reason, 0u);
    CHECK(std::isfinite(error_norm));
    CHECK(error_norm > 0.0f);
    const auto after_l1qk = loader.export_page(0);
    CHECK(after_l1qk[0xFCC00] == before_l1qk[0xFCC00]);
    bool l1wq_changed = false, l1wk_changed = false;
    for (std::size_t i = 0x50000u; i < 0x58000u; ++i)
        if (after_l1qk[i] != before_l1qk[i]) l1wq_changed = true;
    for (std::size_t i = 0x58000u; i < 0x60000u; ++i)
        if (after_l1qk[i] != before_l1qk[i]) l1wk_changed = true;
    CHECK(l1wq_changed);
    CHECK(l1wk_changed);

    CHECK(vm.native_head_page_train(context, 1, 16, target, 0.1f,
                                    output, error_norm, reason));
    CHECK_EQ(reason, 1u);
    CHECK(vm.native_head_page_train(context, 7, 0, target, 0.1f,
                                    output, error_norm, reason));
    CHECK_EQ(reason, 1u);

    return test_done("native final + layer1 W2/W1/Wo/Wv/QK page training step");
}
