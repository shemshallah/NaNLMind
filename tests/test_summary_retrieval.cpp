#include "nanlm/summary_retriever.hpp"
#include "test_util.hpp"

#include <array>
#include <cmath>

using namespace nanlm;

namespace {
ChunkSummary summary(std::uint64_t id, unsigned head, float lane0) {
    ChunkSummary s{};
    s.chunk_id = id;
    s.token_count = 64;
    s.heads = {head};
    std::array<float, 128> state{};
    state[0] = lane0;
    s.states = {state};
    return s;
}
} // namespace

int main() {
    RawFieldVM vm("build/head_worker.nan");
    CHECK(vm.ready());
    SummaryBank bank(8);
    bank.append(summary(10, 3, 0.2f));
    bank.append(summary(11, 3, 0.8f));
    bank.append(summary(12, 3, -0.5f));
    bank.append(summary(20, 1, 9.0f));

    SummaryRetriever retriever(vm);
    std::array<float, 128> query{};
    query[0] = 1.0f;
    const auto hits = retriever.query(bank, 3, query, 2);
    CHECK_EQ(hits.size(), 2u);
    CHECK_EQ(hits[0].chunk_id, 11u);
    CHECK_EQ(hits[1].chunk_id, 10u);
    CHECK(hits[0].score > hits[1].score);
    CHECK(std::isfinite(hits[0].score));

    const auto none = retriever.query(bank, 2, query, 2);
    CHECK(none.empty());

    bool rejected = false;
    try {
        (void)retriever.query(bank, 3, query, 0);
    } catch (const std::invalid_argument&) {
        rejected = true;
    }
    CHECK(rejected);

    return test_done("native summary top-k retrieval");
}
