// Scheduler that turns a token chunk into final per-head memory summaries.
#pragma once
#include "nanlm/chunk_summary.hpp"
#include "nanlm/long_context64_scheduler.hpp"

namespace nanlm {

class ChunkSummaryScheduler {
public:
    explicit ChunkSummaryScheduler(LongContext64Scheduler& context)
        : context_(context) {}

    ChunkSummary summarize(
        std::uint64_t chunk_id,
        const std::array<float, 255>& credits,
        const std::vector<std::array<float, 128>>& token_vectors,
        std::size_t top_k = HeadWorkerScheduler::kMaxHeads) {
        if (token_vectors.empty())
            throw std::invalid_argument("chunk summary requires tokens");
        context_.reset_memory();
        const auto result = context_.run(credits, token_vectors, top_k);
        if (!result.accepted)
            throw std::runtime_error("chunk summary context rejection");
        ChunkSummary summary{};
        summary.chunk_id = chunk_id;
        summary.token_count = token_vectors.size();
        summary.heads = result.heads;
        summary.states = result.final_states;
        return summary;
    }

private:
    LongContext64Scheduler& context_;
};

} // namespace nanlm
