// Chunk summaries over the 64-token recurrent context worker.
//
// A chunk is summarized by resetting the persistent context memory, running
// the entire chunk through the 64-slot worker in 63-token windows, and taking
// the final per-head memory as the chunk summary.  The bank stores summaries
// only; native scoring/retrieval is a separate layer.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <stdexcept>
#include <utility>
#include <vector>

namespace nanlm {

struct ChunkSummary {
    std::uint64_t chunk_id = 0;
    std::size_t token_count = 0;
    std::vector<unsigned> heads;
    std::vector<std::array<float, 128>> states;
};

class SummaryBank {
public:
    explicit SummaryBank(std::size_t capacity = 512)
        : capacity_(capacity) {
        if (capacity_ == 0) throw std::invalid_argument("summary bank capacity");
    }

    void append(ChunkSummary summary) {
        if (summary.heads.size() != summary.states.size())
            throw std::invalid_argument("summary heads/states mismatch");
        if (records_.size() >= capacity_) records_.pop_front();
        records_.push_back(std::move(summary));
    }
    std::size_t size() const noexcept { return records_.size(); }
    std::size_t capacity() const noexcept { return capacity_; }
    const ChunkSummary& at(std::size_t i) const { return records_.at(i); }
    const std::deque<ChunkSummary>& records() const noexcept { return records_; }
    void clear() { records_.clear(); }

private:
    std::size_t capacity_;
    std::deque<ChunkSummary> records_;
};

} // namespace nanlm
