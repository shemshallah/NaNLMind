// Context-2 slot memory baseline.
//
// This is a host baseline, not the topology. It stores counts for the previous
// two bytes and predicts the next byte. It shows how much a longer context buys
// over the topology bigram, so the next substrate step has a target.
#pragma once

#include <array>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace nanlm {

struct SlotEval {
    std::size_t bytes = 0;
    std::size_t correct = 0;
    double accuracy = 0.0;
    double bits_per_byte = 0.0;
};

class SlotMemory {
public:
    explicit SlotMemory(int order = 2) : order_(order < 1 ? 1 : order) {}

    void train(const std::vector<std::uint8_t>& data);
    std::uint8_t predict(std::uint32_t context) const;
    SlotEval evaluate(const std::vector<std::uint8_t>& data, std::size_t start,
                      std::size_t end) const;

private:
    int order_ = 2;
    std::unordered_map<std::uint32_t, std::array<std::uint32_t, 256>> counts_;
    std::array<std::array<std::uint32_t, 256>, 256> bigram_{};
    std::array<std::uint32_t, 256> unigram_{};
};

// Interpolated Kneser-Ney byte model. order = context length in bytes:
//   1 = bigram KN, 2 = trigram KN, 3 = 4-gram KN.
class KneserNey {
public:
    explicit KneserNey(int order = 2, double discount = 0.75)
        : order_(order < 1 ? 1 : order), discount_(discount) {}

    void train(const std::vector<std::uint8_t>& data);
    double probability(std::uint32_t context, std::uint8_t b) const;
    std::uint8_t predict(std::uint32_t context) const;
    SlotEval evaluate(const std::vector<std::uint8_t>& data, std::size_t start,
                      std::size_t end) const;

private:
    std::uint32_t context_key(const std::vector<std::uint8_t>& data, std::size_t i,
                              int level) const;
    std::uint32_t lower_context(std::uint32_t ctx, int level) const;
    double p_kn(int level, std::uint32_t ctx, std::uint8_t b) const;

    int order_ = 2;
    double discount_ = 0.75;
    std::array<std::unordered_map<std::uint32_t, std::array<std::uint32_t, 256>>, 4> counts_;
    std::array<std::unordered_map<std::uint32_t, std::uint64_t>, 4> totals_;
    std::array<std::unordered_map<std::uint32_t, std::uint16_t>, 4> types_;
    std::array<std::array<std::uint64_t, 256>, 4> continuation_{};
    std::uint64_t continuation_total_ = 0;
    std::uint32_t continuation_types_ = 0;
};

} // namespace nanlm
