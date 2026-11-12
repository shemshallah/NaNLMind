#include "nanlm/long_context_scheduler.hpp"
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
    HeadPageArena pages;
    make_page(pages.page(1));
    make_page(pages.page(3));
    HeadWorkerScheduler scheduler(vm, pages);
    LongContextScheduler long_context(scheduler);

    std::array<float, 255> credits{};
    credits[1] = 5.0f;
    credits[3] = 9.0f;
    std::vector<std::array<float, 128>> tokens(12);
    for (std::size_t t = 0; t < tokens.size(); ++t)
        for (unsigned d = 0; d < 128u; ++d)
            tokens[t][d] = 0.001f * static_cast<float>(
                static_cast<int>(d) - 64 + static_cast<int>(t));

    const auto result = long_context.run(credits, tokens, 2);
    CHECK(result.accepted);
    CHECK_EQ(result.chunks, 3u);
    CHECK_EQ(result.heads.size(), 2u);
    CHECK_EQ(result.final_states.size(), 2u);
    CHECK_EQ(result.heads[0], 3u);
    CHECK_EQ(result.heads[1], 1u);
    bool finite = true;
    for (const auto& state : result.final_states)
        for (float value : state) finite = finite && std::isfinite(value);
    CHECK(finite);

    bool memory_changed = false;
    for (unsigned d = 0; d < 128u; ++d)
        if (long_context.memory(3)[d] != 0.0f) memory_changed = true;
    CHECK(memory_changed);

    // Reset and replay: deterministic final memory.
    long_context.reset_memory();
    const auto replay = long_context.run(credits, tokens, 2);
    CHECK(replay.accepted);
    CHECK(replay.final_states == result.final_states);

    const std::vector<std::array<float, 128>> empty;
    const auto rejected = long_context.run(credits, empty, 2);
    CHECK(!rejected.accepted);
    CHECK_EQ(rejected.reason, 1u);

    return test_done("recurrent long-context scheduler");
}
