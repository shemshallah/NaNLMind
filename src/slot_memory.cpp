#include "nanlm/slot_memory.hpp"

#include <cmath>

namespace nanlm {

void SlotMemory::train(const std::vector<std::uint8_t>& data) {
    counts_.clear();
    bigram_ = {};
    unigram_ = {};
    if (data.size() < 2) return;
    for (std::size_t i = 0; i < data.size(); ++i) ++unigram_[data[i]];
    for (std::size_t i = 1; i < data.size(); ++i) ++bigram_[data[i - 1]][data[i]];
    for (std::size_t i = 1; i < data.size(); ++i) {
        std::uint32_t ctx = 0;
        for (int k = order_; k >= 1; --k) {
            const std::size_t pos = i >= static_cast<std::size_t>(k)
                                        ? i - static_cast<std::size_t>(k)
                                        : 0;
            ctx = (ctx << 8) | data[pos];
        }
        ++counts_[ctx][data[i]];
    }
}

std::uint8_t SlotMemory::predict(std::uint32_t context) const {
    auto it = counts_.find(context);
    if (it == counts_.end()) return 0;
    std::uint32_t best = 0;
    std::uint8_t best_b = 0;
    for (std::uint32_t b = 0; b < 256; ++b) {
        if (it->second[b] > best) {
            best = it->second[b];
            best_b = static_cast<std::uint8_t>(b);
        }
    }
    return best_b;
}

SlotEval SlotMemory::evaluate(const std::vector<std::uint8_t>& data, std::size_t start,
                              std::size_t end) const {
    SlotEval r;
    if (start < 1) start = 1;
    if (end > data.size()) end = data.size();
    double bits = 0.0;
    for (std::size_t i = start; i < end; ++i) {
        std::uint32_t ctx = 0;
        for (int k = order_; k >= 1; --k) {
            const std::size_t pos = i >= static_cast<std::size_t>(k)
                                        ? i - static_cast<std::size_t>(k)
                                        : 0;
            ctx = (ctx << 8) | data[pos];
        }
        ++r.bytes;
        if (predict(ctx) == data[i]) ++r.correct;
        auto it = counts_.find(ctx);
        std::uint32_t total = 0;
        std::uint32_t c = 0;
        if (it != counts_.end()) {
            for (std::uint32_t x : it->second) total += x;
            c = it->second[data[i]];
        }
        const double p2 = (static_cast<double>(c) + 1.0) /
                          (static_cast<double>(total) + 256.0);
        const std::uint8_t a = i >= 1 ? data[i - 1] : 0;
        std::uint32_t total_b = 0;
        for (std::uint32_t x : bigram_[a]) total_b += x;
        const double p1 = (static_cast<double>(bigram_[a][data[i]]) + 1.0) /
                          (static_cast<double>(total_b) + 256.0);
        const double lambda = static_cast<double>(total) / (static_cast<double>(total) + 50.0);
        const double p = lambda * p2 + (1.0 - lambda) * p1;
        bits += -std::log2(p);
    }
    if (r.bytes) {
        r.accuracy = static_cast<double>(r.correct) / static_cast<double>(r.bytes);
        r.bits_per_byte = bits / static_cast<double>(r.bytes);
    }
    return r;
}

} // namespace nanlm
