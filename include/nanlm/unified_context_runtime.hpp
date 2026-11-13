// One facade for the unified long-context architecture.
//
// It owns the native 64-slot context stream, the chunk summarizer, and native
// summary retrieval over one shared VM/arena. No alternate model path is
// introduced; all components use the same worker and page layout.
#pragma once
#include "nanlm/chunk_summary_scheduler.hpp"
#include "nanlm/head_page_checkpoint.hpp"
#include "nanlm/long_context64_scheduler.hpp"
#include "nanlm/summary_retriever.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

namespace nanlm {

class UnifiedContextRuntime {
public:
    UnifiedContextRuntime(RawFieldVM& vm, HeadPageArena& arena,
                          std::size_t chunk_tokens = 63)
        : arena_(arena), context_(vm, arena, chunk_tokens, true),
          summarizer_context_(vm, arena, chunk_tokens, true),
          summarizer_(summarizer_context_), retriever_(vm) {}

    void load_checkpoint(const std::string& directory,
                         const std::vector<unsigned>& heads) {
        HeadPageCheckpoint store(directory);
        std::string error;
        if (!store.verify_all(&error))
            throw std::runtime_error("checkpoint invalid: " + error);
        context_.clear_pages();
        summarizer_context_.clear_pages();
        for (unsigned head : heads) {
            if (head >= 255u) throw std::out_of_range("head");
            if (!store.present(head) || !store.read_page(head, arena_))
                throw std::runtime_error("checkpoint missing head " +
                                         std::to_string(head));
        }
    }

    LongContextResult advance(
        const std::array<float, 255>& credits,
        const std::vector<std::array<float, 128>>& tokens,
        std::size_t top_k = 20u, SummaryBank* bank = nullptr,
        std::size_t summary_k = 0, std::size_t local_limit = 0) {
        if (bank && summary_k != 0u)
            return context_.run_hierarchical(credits, tokens, *bank, top_k,
                                             summary_k, local_limit);
        return context_.run(credits, tokens, top_k);
    }

    ChunkSummary summarize(std::uint64_t chunk_id,
                           const std::array<float, 255>& credits,
                           const std::vector<std::array<float, 128>>& tokens,
                           std::size_t top_k = 20u) {
        return summarizer_.summarize(chunk_id, credits, tokens, top_k);
    }

    std::vector<SummaryHit> retrieve(
        const SummaryBank& bank, unsigned head,
        const std::array<float, 128>& query, std::size_t top_k = 8u) const {
        return retriever_.query(bank, head, query, top_k);
    }

    const std::array<float, 128>& memory(unsigned head) const {
        return context_.memory(static_cast<std::uint8_t>(head));
    }
    std::size_t resident_pages() const { return context_.resident_count(); }

private:
    HeadPageArena& arena_;
    LongContext64Scheduler context_;
    LongContext64Scheduler summarizer_context_;
    ChunkSummaryScheduler summarizer_;
    SummaryRetriever retriever_;
};

} // namespace nanlm
