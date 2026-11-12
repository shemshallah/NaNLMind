// Recurrent long-context chunk scheduler over the six-token head worker.
//
// A six-slot worker consumes [persistent memory, up to five new token vectors].
// The last-token output becomes the next persistent memory.  This gives an
// unbounded token stream without allocating a per-token tensor bank, while
// keeping all attention in the guest.  It is a recurrent memory path, not a
// full-context transformer; hierarchical summary banks are a later layer.
#pragma once
#include "nanlm/head_worker_scheduler.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <numeric>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace nanlm {

struct LongContextResult {
    bool accepted = false;
    std::uint8_t reason = 0;
    std::size_t chunks = 0;
    std::vector<unsigned> heads;
    std::vector<std::array<float, 128>> final_states;
};

class LongContextScheduler {
public:
    static constexpr std::size_t kTokensPerChunk = 5; // six slots minus memory

    explicit LongContextScheduler(HeadWorkerScheduler& scheduler)
        : scheduler_(scheduler) {
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
            const std::size_t n = std::min(kTokensPerChunk,
                                           token_vectors.size() - pos);
            ++result.chunks;
            for (std::size_t hi = 0; hi < result.heads.size(); ++hi) {
                const unsigned head = result.heads[hi];
                std::array<float, 6 * 128> context{};
                for (unsigned d = 0; d < 128u; ++d)
                    context[d] = memory_[head][d];
                for (std::size_t i = 0; i < n; ++i)
                    for (unsigned d = 0; d < 128u; ++d)
                        context[(i + 1u) * 128u + d] =
                            token_vectors[pos + i][d];
                std::array<float, 255> one{};
                one[head] = 1.0f;
                const auto batch = scheduler_.run(
                    one, context, static_cast<std::uint8_t>(n + 1u), 1u);
                if (!batch.accepted || batch.heads.size() != 1u) {
                    result.reason = batch.reason ? batch.reason : 2u;
                    return result;
                }
                const auto& state = batch.heads[0];
                const std::size_t base =
                    (static_cast<std::size_t>(state.token_count) - 1u) * 128u;
                for (unsigned d = 0; d < 128u; ++d) {
                    memory_[head][d] = state.output[base + d];
                    result.final_states[hi][d] = memory_[head][d];
                }
            }
            pos += n;
        }
        result.accepted = true;
        return result;
    }

    const std::array<float, 128>& memory(std::uint8_t head) const {
        if (head >= 255u) throw std::out_of_range("long context head");
        return memory_[head];
    }
    void reset_memory() { memory_.fill(std::array<float, 128>{}); }

private:
    HeadWorkerScheduler& scheduler_;
    std::array<std::array<float, 128>, 255> memory_{};
};

} // namespace nanlm
