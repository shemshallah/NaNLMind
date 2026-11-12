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

    std::array<float, 64 * 128> input{};
    for (unsigned t = 0; t < 64; ++t)
        for (unsigned d = 0; d < 128; ++d)
            input[t * 128 + d] = 0.001f * static_cast<float>(
                static_cast<int>(d) - 64 + static_cast<int>(t % 7));
    std::array<float, 64 * 128> output{};
    std::uint8_t reason = 0;
    CHECK(vm.native_head_block64(input, 64, 0, output, reason));
    CHECK_EQ(reason, 0u);
    bool finite = true;
    float energy = 0.0f;
    for (float value : output) {
        finite = finite && std::isfinite(value);
        energy += value * value;
    }
    CHECK(finite);
    CHECK(energy > 1e-6f);

    std::array<float, 64 * 128> rejected{};
    CHECK(vm.native_head_block64(input, 65, 0, rejected, reason));
    CHECK_EQ(reason, 1u);
    CHECK(vm.native_head_block64(input, 64, 16, rejected, reason));
    CHECK_EQ(reason, 1u);

    return test_done("native 64-token head block");
}
