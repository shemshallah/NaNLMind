#include "nanlm/summary_retriever.hpp"
#include "test_util.hpp"

#include <array>
#include <cmath>
#include <cstdint>

using namespace nanlm;

namespace {
ChunkSummary summary(std::uint64_t id, float value) {
    ChunkSummary s{};
    s.chunk_id = id;
    s.token_count = 256;
    s.heads = {0u};
    std::array<float, 128> state{};
    state[0] = value;
    s.states = {state};
    return s;
}
std::size_t coverage(const SummaryBank& bank) {
    std::size_t total = 0;
    for (const auto& record : bank.records()) total += record.token_count;
    return total;
}
} // namespace

int main() {
    RawFieldVM vm("build/head_worker.nan");
    CHECK(vm.ready());

    // 512 summaries x 256 tokens = the full 131072-token tier.
    SummaryBank bank(512);
    for (std::uint64_t i = 0; i < 512u; ++i)
        bank.append(summary(i, static_cast<float>(i) / 512.0f));
    CHECK_EQ(bank.size(), 512u);
    CHECK_EQ(bank.capacity(), 512u);
    CHECK_EQ(coverage(bank), 131072u);

    SummaryRetriever retriever(vm);
    std::array<float, 128> query{};
    query[0] = 1.0f;
    const auto hits = retriever.query(bank, 0, query, 8);
    CHECK_EQ(hits.size(), 8u);
    CHECK_EQ(hits[0].chunk_id, 511u);
    CHECK_EQ(hits[1].chunk_id, 510u);
    CHECK(hits[0].score > hits[1].score);

    // The next 256-token chunk evicts the oldest record, not the tier shape.
    bank.append(summary(512u, 1.5f));
    CHECK_EQ(bank.size(), 512u);
    CHECK_EQ(coverage(bank), 131072u);
    CHECK_EQ(bank.at(0).chunk_id, 1u);
    CHECK_EQ(bank.at(511).chunk_id, 512u);

    const auto after = retriever.query(bank, 0, query, 1);
    CHECK_EQ(after.size(), 1u);
    CHECK_EQ(after[0].chunk_id, 512u);

    return test_done("512-slot / 131072-token summary-bank tier");
}
