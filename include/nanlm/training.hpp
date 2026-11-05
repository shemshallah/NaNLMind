#pragma once
// Single-universe training harness.
//
// Scope: one 8 MiB chart, 256 heads, CPU-only, integer learning. No global
// cluster training here; that is design-only until the root universe passes
// its gates.
#include "nanlm/head.hpp"
#include "nanlm/temporal.hpp"

#include <cstdint>
#include <vector>

namespace nanlm {

struct BooleanSample {
    std::uint32_t a = 0;
    std::uint32_t b = 0;
    bool target = false;
};

struct AccuracyReport {
    std::size_t total = 0;
    std::size_t correct = 0;
    double accuracy = 0.0;
};

class UniverseTrainer {
public:
    explicit UniverseTrainer(HeadArray& heads) : heads_(&heads) {}

    // Train one head on a Boolean task for N epochs.
    void train_boolean(std::uint8_t head, const std::vector<BooleanSample>& samples,
                       int epochs = 1);
    AccuracyReport evaluate_boolean(std::uint8_t head,
                                    const std::vector<BooleanSample>& samples) const;

    // Store a cyclic/linear sequence in the temporal links.
    void train_sequence(const std::vector<std::uint8_t>& sequence, std::uint64_t epoch = 0);
    std::vector<std::uint8_t> recall_forward(std::uint8_t start, int steps) const;
    std::vector<std::uint8_t> recall_reverse(std::uint8_t start, int steps) const;

    const BidirectionalMemory& temporal() const { return temporal_; }

private:
    HeadArray* heads_;
    BidirectionalMemory temporal_;
};

} // namespace nanlm
