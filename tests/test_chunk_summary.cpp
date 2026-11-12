#include "nanlm/chunk_summary.hpp"
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
    LongContext64Scheduler context(vm, pages, 16);
    ChunkSummaryScheduler summarizer(context);

    std::array<float, 255> credits{};
    credits[1] = 5.0f;
    credits[3] = 9.0f;
    std::vector<std::array<float, 128>> tokens(17);
    for (std::size_t t = 0; t < tokens.size(); ++t)
        for (unsigned d = 0; d < 128u; ++d)
            tokens[t][d] = 0.001f * static_cast<float>(
                static_cast<int>(d) - 64 + static_cast<int>(t));

    const auto first = summarizer.summarize(7, credits, tokens, 2);
    CHECK(first.chunk_id == 7u);
    CHECK_EQ(first.token_count, tokens.size());
    CHECK_EQ(first.heads.size(), 2u);
    CHECK_EQ(first.states.size(), 2u);
    CHECK_EQ(first.heads[0], 3u);
    bool finite = true;
    for (const auto& state : first.states)
        for (float value : state) finite = finite && std::isfinite(value);
    CHECK(finite);

    SummaryBank bank(2);
    bank.append(first);
    bank.append(summarizer.summarize(8, credits, tokens, 2));
    CHECK_EQ(bank.size(), 2u);
    bank.append(summarizer.summarize(9, credits, tokens, 2));
    CHECK_EQ(bank.size(), 2u);
    CHECK(bank.at(0).chunk_id == 8u);
    CHECK(bank.at(1).chunk_id == 9u);
    bank.clear();
    CHECK_EQ(bank.size(), 0u);

    const std::vector<std::array<float, 128>> empty;
    bool rejected = false;
    try {
        (void)summarizer.summarize(10, credits, empty, 2);
    } catch (const std::invalid_argument&) {
        rejected = true;
    }
    CHECK(rejected);

    return test_done("chunk summary scheduler and paged bank");
}
