// 64-token local-window recurrent long-context scheduler.
//
// A 64-slot native block consumes [persistent memory, up to 63 new tokens].
// The last-token output becomes the next memory. This raises the local window
// from 5 to 63 tokens while keeping an unbounded stream and paged head pages.
#pragma once
#include "nanlm/head_page_loader.hpp"
#include "nanlm/summary_retriever.hpp"
#include "nanlm/long_context_scheduler.hpp"
#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <numeric>
#include <stdexcept>
#include <vector>

namespace nanlm {

class LongContext64Scheduler {
public:
    static constexpr std::size_t kMaxChunkTokens = 63;

    explicit LongContext64Scheduler(RawFieldVM& vm, HeadPageArena& arena,
                                    std::size_t chunk_tokens = kMaxChunkTokens,
                                    bool last_token_only = true)
        : vm_(vm), loader_(vm, arena), chunk_tokens_(chunk_tokens),
          last_token_only_(last_token_only) {
        if (chunk_tokens_ == 0u || chunk_tokens_ > kMaxChunkTokens)
            throw std::invalid_argument("long context64 chunk size");
        memory_.fill(std::array<float, 128>{});
    }

    LongContextResult run(const std::array<float, 255>& credits,
                          const std::vector<std::array<float, 128>>& token_vectors,
                          std::size_t top_k = HeadWorkerScheduler::kMaxHeads) {
        LongContextResult result{};
        if (token_vectors.empty() || top_k == 0u ||
            top_k > HeadWorkerScheduler::kMaxHeads) {
            result.reason = 1u;
            return result;
        }
        for (float credit : credits)
            if (!std::isfinite(credit)) {
                result.reason = 1u;
                return result;
            }
        std::array<unsigned, 255> order{};
        std::iota(order.begin(), order.end(), 0u);
        std::stable_sort(order.begin(), order.end(), [&](unsigned a, unsigned b) {
            if (credits[a] != credits[b]) return credits[a] > credits[b];
            return a < b;
        });
        result.heads.assign(order.begin(), order.begin() + top_k);
        result.final_states.resize(top_k);

        std::size_t pos = 0;
        while (pos < token_vectors.size()) {
            const std::size_t n = std::min(chunk_tokens_,
                                           token_vectors.size() - pos);
            ++result.chunks;
            for (std::size_t hi = 0; hi < result.heads.size(); ++hi) {
                const unsigned head = result.heads[hi];
                std::array<float, 64 * 128> context{};
                for (unsigned d = 0; d < 128u; ++d)
                    context[d] = memory_[head][d];
                for (std::size_t i = 0; i < n; ++i)
                    for (unsigned d = 0; d < 128u; ++d)
                        context[(i + 1u) * 128u + d] =
                            token_vectors[pos + i][d];
                std::size_t slot = 0;
                try {
                    slot = loader_.load(head);
                } catch (const std::exception&) {
                    result.reason = 3u;
                    return result;
                }
                std::array<float, 64 * 128> output{};
                std::uint8_t reason = 0;
                if (!vm_.native_head_block64(
                        context, static_cast<std::uint8_t>(n + 1u),
                        static_cast<std::uint8_t>(slot), output, reason,
                        last_token_only_)) {
                    result.reason = 2u;
                    return result;
                }
                if (reason != 0u) {
                    result.reason = reason;
                    return result;
                }
                const std::size_t base =
                    static_cast<std::size_t>(n + 1u) * 128u - 128u;
                for (unsigned d = 0; d < 128u; ++d) {
                    memory_[head][d] = output[base + d];
                    result.final_states[hi][d] = memory_[head][d];
                }
            }
            pos += n;
        }
        result.accepted = true;
        return result;
    }

    // Retrieve up to summary_k bank vectors per head and prepend them to the
    // local window: [memory | summaries | local tokens], T <= 64.
    LongContextResult run_hierarchical(
        const std::array<float, 255>& credits,
        const std::vector<std::array<float, 128>>& token_vectors,
        SummaryBank& bank, std::size_t top_k = HeadWorkerScheduler::kMaxHeads,
        std::size_t summary_k = 2, std::size_t local_limit = 0) {
        LongContextResult result{};
        if (token_vectors.empty() || top_k == 0u ||
            top_k > HeadWorkerScheduler::kMaxHeads || summary_k > 62u ||
            local_limit > kMaxChunkTokens - summary_k) {
            result.reason = 1u;
            return result;
        }
        for (float credit : credits)
            if (!std::isfinite(credit)) {
                result.reason = 1u;
                return result;
            }
        std::array<unsigned, 255> order{};
        std::iota(order.begin(), order.end(), 0u);
        std::stable_sort(order.begin(), order.end(), [&](unsigned a, unsigned b) {
            if (credits[a] != credits[b]) return credits[a] > credits[b];
            return a < b;
        });
        result.heads.assign(order.begin(), order.begin() + top_k);
        result.final_states.resize(top_k);
        SummaryRetriever retriever(vm_);
        const std::size_t local_per_chunk = local_limit == 0u
            ? kMaxChunkTokens - summary_k : local_limit;
        std::size_t pos = 0;
        while (pos < token_vectors.size()) {
            const std::size_t n = std::min(local_per_chunk,
                                           token_vectors.size() - pos);
            ++result.chunks;
            for (std::size_t hi = 0; hi < result.heads.size(); ++hi) {
                const unsigned head = result.heads[hi];
                const auto hits = retriever.query(bank, head, memory_[head],
                                                  summary_k);
                const std::size_t k = hits.size();
                const std::size_t token_count = 1u + k + n;
                if (token_count > 64u) {
                    result.reason = 1u;
                    return result;
                }
                std::array<float, 64 * 128> context{};
                for (unsigned d = 0; d < 128u; ++d)
                    context[d] = memory_[head][d];
                for (std::size_t i = 0; i < k; ++i)
                    for (unsigned d = 0; d < 128u; ++d)
                        context[(i + 1u) * 128u + d] =
                            bank.at(hits[i].bank_index).states[
                                hits[i].head_index][d];
                for (std::size_t i = 0; i < n; ++i)
                    for (unsigned d = 0; d < 128u; ++d)
                        context[(1u + k + i) * 128u + d] =
                            token_vectors[pos + i][d];
                std::size_t slot = 0;
                try {
                    slot = loader_.load(head);
                } catch (const std::exception&) {
                    result.reason = 3u;
                    return result;
                }
                std::array<float, 64 * 128> output{};
                std::uint8_t reason = 0;
                if (!vm_.native_head_block64(
                        context, static_cast<std::uint8_t>(token_count),
                        static_cast<std::uint8_t>(slot), output, reason,
                        last_token_only_)) {
                    result.reason = 2u;
                    return result;
                }
                if (reason != 0u) {
                    result.reason = reason;
                    return result;
                }
                const std::size_t base = (token_count - 1u) * 128u;
                for (unsigned d = 0; d < 128u; ++d) {
                    memory_[head][d] = output[base + d];
                    result.final_states[hi][d] = memory_[head][d];
                }
            }
            pos += n;
        }
        result.accepted = true;
        return result;
    }

    const std::array<float, 128>& memory(std::uint8_t head) const {
        if (head >= 255u) throw std::out_of_range("long context64 head");
        return memory_[head];
    }
    std::size_t chunk_tokens() const noexcept { return chunk_tokens_; }
    void reset_memory() { memory_.fill(std::array<float, 128>{}); }

private:
    RawFieldVM& vm_;
    HeadPageLoader loader_;
    std::size_t chunk_tokens_ = kMaxChunkTokens;
    bool last_token_only_ = true;
    std::array<std::array<float, 128>, 255> memory_{};
};

} // namespace nanlm
