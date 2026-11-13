// Top-k paged head scheduler for the dedicated six-token head worker.
//
// The host selects up to 20 active heads from external credits, asks the LRU
// page loader for a resident 1 MiB page, and invokes the single native
// opcode122 worker for each head.  No head arithmetic is performed here.
#pragma once
#include "nanlm/dual_tensor_arena.hpp"
#include "nanlm/head_page_loader.hpp"
#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <limits>
#include <string>
#include <utility>
#include <numeric>
#include <stdexcept>
#include <vector>

namespace nanlm {

struct HeadWorkerState {
    std::uint8_t head = 0;
    std::uint8_t slot = 0;
    std::uint8_t token_count = 0;
    std::array<float, 6 * 128> output{};
};

struct HeadWorkerBatch {
    bool accepted = false;
    std::uint8_t reason = 0;
    std::uint64_t generation = 0;
    std::vector<HeadWorkerState> heads;
};

class HeadWorkerScheduler {
public:
    static constexpr std::size_t kMaxHeads = 20;
    static constexpr std::size_t kStateWords = 6 * 128;

    HeadWorkerScheduler(RawFieldVM& vm, HeadPageArena& arena)
        : vm_(vm), loader_(vm, arena) {}

    HeadWorkerBatch run(const std::array<float, 255>& credits,
                        const std::array<float, kStateWords>& context,
                        std::uint8_t token_count,
                        std::size_t top_k = kMaxHeads) {
        HeadWorkerBatch batch{};
        if (token_count == 0u || token_count > 6u || top_k > kMaxHeads) {
            batch.reason = 1u;
            return batch;
        }
        for (float credit : credits)
            if (!std::isfinite(credit)) {
                batch.reason = 1u;
                return batch;
            }
        if (top_k == 0u) {
            batch.accepted = true;
            return batch;
        }
        std::array<unsigned, 255> order{};
        std::iota(order.begin(), order.end(), 0u);
        std::stable_sort(order.begin(), order.end(), [&](unsigned a, unsigned b) {
            if (credits[a] != credits[b]) return credits[a] > credits[b];
            return a < b;
        });
        std::vector<HeadWorkerState> states;
        states.reserve(top_k);
        for (std::size_t i = 0; i < top_k; ++i) {
            const unsigned head = order[i];
            std::size_t slot = 0;
            try {
                slot = loader_.load(head);
            } catch (const std::exception&) {
                batch.reason = 3u;
                return batch;
            }
            HeadWorkerState state{};
            state.head = static_cast<std::uint8_t>(head);
            state.slot = static_cast<std::uint8_t>(slot);
            state.token_count = token_count;
            std::uint8_t reason = 0;
            if (!vm_.native_head_block6(context, token_count, state.slot,
                                        state.output, reason)) {
                batch.reason = 2u;
                return batch;
            }
            if (reason != 0u) {
                batch.reason = reason;
                return batch;
            }
            states.push_back(state);
        }
        for (const auto& state : states) {
            const std::size_t base =
                (static_cast<std::size_t>(state.token_count) - 1u) * 128u;
            for (unsigned d = 0; d < 128u; ++d)
                last_state_[state.head][d] = state.output[base + d];
        }
        batch.heads = std::move(states);
        batch.accepted = true;
        return batch;
    }

    const std::array<float, 128>& last_state(std::uint8_t head) const {
        if (head >= 255u) throw std::out_of_range("head worker state");
        return last_state_[head];
    }
    std::size_t resident_count() const { return loader_.resident_count(); }
    int slot_of(std::uint8_t head) const { return loader_.slot_of(head); }
    void clear_pages() { loader_.clear(); }

private:
    RawFieldVM& vm_;
    HeadPageLoader loader_;
    std::array<std::array<float, 128>, 255> last_state_{};
};

struct HeadWorkerStageResult {
    std::size_t heads = 0;
    std::size_t fresh_leaves = 0;
    std::size_t scalar_writes = 0;
    std::uint64_t generation = 0;
};

struct HeadWorkerTokenStageResult {
    std::size_t heads = 0;
    std::size_t token_leaves = 0;
    std::size_t fresh_leaves = 0;
    std::size_t scalar_writes = 0;
    std::uint64_t generation = 0;
};

// Transport the worker's last-token 128D state into the candidate tensor as a
// typed HeadVector128 leaf, plus one guest lane as the candidate scalar.  The
// scalar is a transport of a guest output, not a host-computed score.
inline HeadWorkerStageResult stage_head_worker_batch(
    DualTensor256Arena& arena, const HeadWorkerBatch& batch,
    std::uint64_t expected_generation, std::uint64_t logical_base,
    const std::string& source_sha256) {
    if (!batch.accepted)
        throw std::invalid_argument("head worker batch was not accepted");
    if (!arena.candidate_open() || arena.generation() != expected_generation)
        throw std::logic_error("head worker batch generation/lease mismatch");
    if (!valid_tensor_leaf_sha256(source_sha256))
        throw std::invalid_argument("head worker source digest invalid");
    if (batch.heads.size() > HeadWorkerScheduler::kMaxHeads)
        throw std::invalid_argument("head worker batch exceeds resident limit");
    if (logical_base > std::numeric_limits<std::uint64_t>::max() - 254u)
        throw std::invalid_argument("head worker logical id overflow");

    HeadWorkerStageResult result{};
    result.generation = arena.generation();
    try {
        for (const auto& state : batch.heads) {
            if (state.head >= 255u || state.token_count == 0u ||
                state.token_count > 6u)
                throw std::invalid_argument("head worker state invalid");
            if (!arena.candidate_writer_allowed(state.head))
                throw std::logic_error("head worker writer not authorized");
            TensorDataLeaf leaf{};
            leaf.kind = TensorLeafKind::HeadVector128;
            leaf.logical_leaf_id = logical_base + state.head;
            leaf.source_generation = arena.generation();
            leaf.source_sha256 = source_sha256;
            leaf.payload.resize(128u * sizeof(float));
            const std::size_t base =
                (static_cast<std::size_t>(state.token_count) - 1u) * 128u;
            std::memcpy(leaf.payload.data(), state.output.data() + base,
                        leaf.payload.size());
            const bool fresh = arena.attach_candidate_leaf(
                state.head, state.head, state.head, state.head, leaf);
            const float scalar = state.output[base];
            if (!std::isfinite(scalar))
                throw std::invalid_argument("head worker scalar not finite");
            arena.stage_native_value(state.head, state.head, state.head,
                                     state.head, scalar);
            ++result.heads;
            result.fresh_leaves += fresh ? 1u : 0u;
            ++result.scalar_writes;
        }
    } catch (...) {
        arena.abort_candidate();
        throw;
    }
    return result;
}


// Per-token candidate transport: one HeadVector128 leaf per worker token at
// T[h,h,h], plus one guest last-token scalar per head.  This is the
// per-token write path; it never writes the ACTIVE bank.
inline HeadWorkerTokenStageResult stage_head_worker_tokens(
    DualTensor256Arena& arena, const HeadWorkerBatch& batch,
    std::uint64_t expected_generation, std::uint64_t logical_base,
    const std::string& source_sha256) {
    if (!batch.accepted)
        throw std::invalid_argument("head worker batch was not accepted");
    if (!arena.candidate_open() || arena.generation() != expected_generation)
        throw std::logic_error("head worker token generation/lease mismatch");
    if (!valid_tensor_leaf_sha256(source_sha256))
        throw std::invalid_argument("head worker token source digest invalid");
    if (batch.heads.size() > HeadWorkerScheduler::kMaxHeads)
        throw std::invalid_argument("head worker token batch exceeds resident limit");
    if (logical_base > std::numeric_limits<std::uint64_t>::max() - 255u * 6u)
        throw std::invalid_argument("head worker token logical id overflow");
    HeadWorkerTokenStageResult result{};
    result.generation = arena.generation();
    try {
        for (const auto& state : batch.heads) {
            if (state.head >= 255u || state.token_count == 0u ||
                state.token_count > 6u)
                throw std::invalid_argument("head worker token state invalid");
            if (!arena.candidate_writer_allowed(state.head))
                throw std::logic_error("head worker token writer not authorized");
            for (unsigned t = 0; t < state.token_count; ++t) {
                TensorDataLeaf leaf{};
                leaf.kind = TensorLeafKind::HeadVector128;
                leaf.logical_leaf_id = logical_base +
                    static_cast<std::uint64_t>(state.head) * 6u + t;
                leaf.source_generation = arena.generation();
                leaf.source_sha256 = source_sha256;
                leaf.payload.resize(128u * sizeof(float));
                std::memcpy(leaf.payload.data(),
                            state.output.data() + t * 128u,
                            leaf.payload.size());
                const bool fresh = arena.attach_candidate_leaf(
                    state.head, state.head, state.head, state.head, leaf);
                ++result.token_leaves;
                if (fresh) ++result.fresh_leaves;
            }
            const std::size_t last =
                (static_cast<std::size_t>(state.token_count) - 1u) * 128u;
            const float scalar = state.output[last];
            if (!std::isfinite(scalar))
                throw std::invalid_argument("head worker token scalar not finite");
            arena.stage_native_value(state.head, state.head, state.head,
                                     state.head, scalar);
            ++result.heads;
            ++result.scalar_writes;
        }
    } catch (...) {
        arena.abort_candidate();
        throw;
    }
    return result;
}

} // namespace nanlm
