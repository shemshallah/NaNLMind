// Native top-k retrieval over a chunk-summary bank.
//
// Summary vectors are scored by the guest head-state readout (opcode123); the
// host only groups bank entries by head, batches <=64 candidates, and sorts the
// returned guest scores. No host dot product or retrieval arithmetic is used.
#pragma once
#include "nanlm/chunk_summary.hpp"
#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace nanlm {

struct SummaryHit {
    std::size_t bank_index = 0;
    std::uint64_t chunk_id = 0;
    float score = 0.0f;
};

class SummaryRetriever {
public:
    explicit SummaryRetriever(RawFieldVM& vm) : vm_(vm) {}

    std::vector<SummaryHit> query(
        const SummaryBank& bank, unsigned head,
        const std::array<float, 128>& query_state,
        std::size_t top_k = 8) const {
        if (head >= 255u) throw std::out_of_range("summary head");
        if (top_k == 0u || top_k > 64u)
            throw std::invalid_argument("summary top-k must be 1..64");
        std::vector<std::size_t> bank_indices;
        std::vector<std::array<float, 128>> candidates;
        for (std::size_t i = 0; i < bank.size(); ++i) {
            const auto& record = bank.at(i);
            for (std::size_t hi = 0; hi < record.heads.size(); ++hi) {
                if (record.heads[hi] != head) continue;
                bank_indices.push_back(i);
                candidates.push_back(record.states[hi]);
                break;
            }
        }
        std::vector<SummaryHit> hits;
        if (candidates.empty()) return hits;
        std::vector<float> scores;
        scores.reserve(candidates.size());
        for (std::size_t base = 0; base < candidates.size(); base += 64u) {
            const std::size_t n = std::min<std::size_t>(64u,
                                                        candidates.size() - base);
            std::vector<std::array<float, 128>> batch(
                candidates.begin() + static_cast<std::ptrdiff_t>(base),
                candidates.begin() + static_cast<std::ptrdiff_t>(base + n));
            std::vector<float> part;
            std::uint8_t reason = 0;
            if (!vm_.native_head_state_readout(query_state, batch, part, reason))
                throw std::runtime_error("summary retrieval guest failure: " +
                                         vm_.error());
            if (reason != 0u)
                throw std::runtime_error("summary retrieval rejected reason=" +
                                         std::to_string(reason));
            scores.insert(scores.end(), part.begin(), part.end());
        }
        for (std::size_t i = 0; i < scores.size(); ++i)
            hits.push_back(SummaryHit{bank_indices[i],
                                      bank.at(bank_indices[i]).chunk_id,
                                      scores[i]});
        std::stable_sort(hits.begin(), hits.end(),
                         [](const SummaryHit& a, const SummaryHit& b) {
            if (a.score != b.score) return a.score > b.score;
            return a.bank_index < b.bank_index;
        });
        if (hits.size() > top_k) hits.resize(top_k);
        return hits;
    }

private:
    RawFieldVM& vm_;
};

} // namespace nanlm
