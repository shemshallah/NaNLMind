#include "nanlm/head_worker_scheduler.hpp"
#include "test_util.hpp"

#include <array>
#include <cmath>
#include <cstring>
#include <limits>

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
    HeadWorkerBatch saved{};
    {
        RawFieldVM vm("build/head_worker.nan");
        CHECK(vm.ready());
        HeadPageArena pages;
        for (unsigned h = 0; h < 4; ++h) make_page(pages.page(h));
        HeadWorkerScheduler scheduler(vm, pages);

        std::array<float, 255> credits{};
        credits[0] = 1.0f;
        credits[1] = 5.0f;
        credits[2] = 7.0f;
        credits[3] = 9.0f;
        std::array<float, 6 * 128> context{};
        for (unsigned t = 0; t < 2; ++t)
            for (unsigned d = 0; d < 128; ++d)
                context[t * 128 + d] = 0.01f * static_cast<float>(
                    static_cast<int>(d) - 64 + static_cast<int>(t) * 2);

        saved = scheduler.run(credits, context, 2, 3);
        CHECK(saved.accepted);
        CHECK_EQ(saved.heads.size(), 3u);
        CHECK_EQ(saved.heads[0].head, 3u);
        CHECK_EQ(saved.heads[1].head, 2u);
        CHECK_EQ(saved.heads[2].head, 1u);
        CHECK_EQ(scheduler.resident_count(), 3u);
        for (const auto& state : saved.heads) {
            CHECK(state.token_count == 2u);
            CHECK(scheduler.slot_of(state.head) >= 0);
            bool finite = true;
            for (float value : state.output) finite = finite && std::isfinite(value);
            CHECK(finite);
            for (unsigned d = 0; d < 128; ++d)
                CHECK_EQ(scheduler.last_state(state.head)[d],
                         state.output[128 + d]);
        }

        const auto empty = scheduler.run(credits, context, 2, 0);
        CHECK(empty.accepted);
        CHECK(empty.heads.empty());
        const auto too_many = scheduler.run(credits, context, 2, 17);
        CHECK(!too_many.accepted);
        CHECK_EQ(too_many.reason, 1u);
        auto bad_credits = credits;
        bad_credits[0] = std::numeric_limits<float>::quiet_NaN();
        const auto bad_credit_run = scheduler.run(bad_credits, context, 2, 1);
        CHECK(!bad_credit_run.accepted);
        CHECK_EQ(bad_credit_run.reason, 1u);
    }

    // Feed the already-measured guest states into the canonical candidate
    // tensor only after the worker VM has been released.
    DualTensor256Arena arena(std::string(64, 'a'), std::string(64, 'b'));
    arena.set_all_candidate_writer_permissions(true);
    arena.begin_candidate();
    const std::string source(64, 'd');
    saved.generation = arena.generation();
    const auto staged = stage_head_worker_batch(
        arena, saved, arena.generation(), 1000u, source);
    CHECK_EQ(staged.heads, 3u);
    CHECK_EQ(staged.fresh_leaves, 3u);
    CHECK_EQ(staged.scalar_writes, 3u);
    const auto& leaves = arena.candidate_leaves(3, 3, 3);
    CHECK_EQ(leaves.size(), 1u);
    CHECK(leaves[0].kind == TensorLeafKind::HeadVector128);
    CHECK_EQ(leaves[0].payload.size(), 128u * sizeof(float));
    CHECK(arena.active_leaves(3, 3, 3).empty());
    CHECK(arena.active(3, 3, 3) == 0.0f);
    arena.abort_candidate();

    return test_done("top-k paged head worker scheduler and tensor transport");
}
