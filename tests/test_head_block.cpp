#include "nanlm/head_page_loader.hpp"
#include "test_util.hpp"

#include <array>
#include <cmath>
#include <cstring>

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
        identity_bf16(page, base + 0x00000u, 128, 128); // Wq
        identity_bf16(page, base + 0x08000u, 128, 128); // Wk
        identity_bf16(page, base + 0x10000u, 128, 128); // Wv
        identity_bf16(page, base + 0x18000u, 128, 128); // Wo
        identity_bf16(page, base + 0x20000u, 384, 128); // W1
        identity_bf16(page, base + 0x38000u, 128, 384); // W2
    }
    const std::uint32_t magic = 0x48315233u;
    page[0xFCC00] = static_cast<std::uint8_t>(magic & 0xFFu);
    page[0xFCC01] = static_cast<std::uint8_t>((magic >> 8) & 0xFFu);
    page[0xFCC02] = static_cast<std::uint8_t>((magic >> 16) & 0xFFu);
    page[0xFCC03] = static_cast<std::uint8_t>((magic >> 24) & 0xFFu);
}
} // namespace

int main() {
    RawFieldVM vm("build/field_driver.nan");
    CHECK(vm.ready());
    HeadPageArena arena;
    HeadPageLoader loader(vm, arena);

    make_page(arena.page(0));
    CHECK_EQ(loader.load(0), 0u);

    std::array<float, 128> input{};
    for (std::size_t i = 0; i < input.size(); ++i)
        input[i] = 0.01f * static_cast<float>(static_cast<int>(i) - 64);
    std::array<float, 128> output{};
    std::uint8_t reason = 0;
    CHECK(vm.native_head_block(input, 0, output, reason));
    CHECK_EQ(reason, 0u);
    float energy = 0.0f;
    bool finite = true;
    for (float v : output) {
        finite = finite && std::isfinite(v);
        energy += v * v;
    }
    CHECK(finite);
    CHECK(energy > 1e-6f);

    std::array<float, 128> again{};
    CHECK(vm.native_head_block(input, 0, again, reason));
    CHECK_EQ(reason, 0u);
    CHECK(output == again);

    std::uint8_t bad_reason = 0;
    std::array<float, 128> rejected{};
    CHECK(vm.native_head_block(input, 16, rejected, bad_reason));
    CHECK_EQ(bad_reason, 1u);

    arena.clear_page(1); // no page header, so the guest must reject it
    CHECK_EQ(loader.load(1), 1u);
    CHECK(vm.native_head_block(input, 1, rejected, bad_reason));
    CHECK_EQ(bad_reason, 2u);

    return test_done("native bf16 head block");
}
