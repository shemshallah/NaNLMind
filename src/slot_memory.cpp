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


namespace nanlm {

std::uint32_t KneserNey::context_key(const std::vector<std::uint8_t>& data,
                                     std::size_t i, int level) const {
    std::uint32_t ctx = 0;
    for (int k = level; k >= 1; --k) {
        const std::size_t pos = i >= static_cast<std::size_t>(k) ? i - k : 0;
        ctx = (ctx << 8) | data[pos];
    }
    return ctx;
}

std::uint32_t KneserNey::lower_context(std::uint32_t ctx, int level) const {
    if (level <= 0) return 0;
    const std::uint32_t mask = (level >= 4) ? 0xFFFFFFFFu : ((1u << (8 * level)) - 1u);
    return ctx & mask;
}

void KneserNey::train(const std::vector<std::uint8_t>& data) {
    for (auto& c : counts_) c.clear();
    for (auto& t : totals_) t.clear();
    for (auto& t : types_) t.clear();
    for (auto& c : continuation_) c.fill(0);
    continuation_total_ = 0;
    continuation_types_ = 0;

    for (std::size_t i = 0; i < data.size(); ++i) {
        for (int level = 1; level <= order_; ++level) {
            if (i < static_cast<std::size_t>(level)) continue;
            const std::uint32_t ctx = context_key(data, i, level);
            ++counts_[level][ctx][data[i]];
        }
    }
    for (int level = 1; level <= order_; ++level) {
        for (auto& kv : counts_[level]) {
            std::uint64_t total = 0;
            std::uint16_t types = 0;
            for (std::uint32_t b = 0; b < 256; ++b) {
                const std::uint32_t c = kv.second[b];
                if (c) {
                    total += c;
                    ++types;
                    ++continuation_[level - 1][b];
                }
            }
            totals_[level][kv.first] = total;
            types_[level][kv.first] = types;
        }
    }
    for (std::uint32_t b = 0; b < 256; ++b) {
        continuation_total_ += continuation_[0][b];
        if (continuation_[0][b]) ++continuation_types_;
    }
}

double KneserNey::p_kn(int level, std::uint32_t ctx, std::uint8_t b) const {
    if (level <= 0) {
        if (continuation_total_ == 0) return 1.0 / 256.0;
        const double c = static_cast<double>(continuation_[0][b]);
        const double total = static_cast<double>(continuation_total_);
        const double lambda = discount_ * static_cast<double>(continuation_types_) / total;
        return std::max(c - discount_, 0.0) / total + lambda * (1.0 / 256.0);
    }
    auto tit = totals_[level].find(ctx);
    if (tit == totals_[level].end() || tit->second == 0) {
        return p_kn(level - 1, lower_context(ctx, level - 1), b);
    }
    const double total = static_cast<double>(tit->second);
    auto cit = counts_[level].find(ctx);
    const double c = cit == counts_[level].end() ? 0.0 : static_cast<double>(cit->second[b]);
    const double types = static_cast<double>(types_[level].at(ctx));
    const double lambda = discount_ * types / total;
    const double lower = p_kn(level - 1, lower_context(ctx, level - 1), b);
    return std::max(c - discount_, 0.0) / total + lambda * lower;
}

double KneserNey::probability(std::uint32_t context, std::uint8_t b) const {
    return p_kn(order_, context, b);
}

std::uint8_t KneserNey::predict(std::uint32_t context) const {
    std::uint8_t best_b = 0;
    double best = -1.0;
    for (std::uint32_t b = 0; b < 256; ++b) {
        const double p = probability(context, static_cast<std::uint8_t>(b));
        if (p > best) {
            best = p;
            best_b = static_cast<std::uint8_t>(b);
        }
    }
    return best_b;
}

SlotEval KneserNey::evaluate(const std::vector<std::uint8_t>& data, std::size_t start,
                             std::size_t end) const {
    SlotEval r;
    if (start < static_cast<std::size_t>(order_)) start = order_;
    if (end > data.size()) end = data.size();
    double bits = 0.0;
    for (std::size_t i = start; i < end; ++i) {
        const std::uint32_t ctx = context_key(data, i, order_);
        const std::uint8_t b = data[i];
        ++r.bytes;
        if (predict(ctx) == b) ++r.correct;
        const double p = std::max(probability(ctx, b), 1e-12);
        bits += -std::log2(p);
    }
    if (r.bytes) {
        r.accuracy = static_cast<double>(r.correct) / static_cast<double>(r.bytes);
        r.bits_per_byte = bits / static_cast<double>(r.bytes);
    }
    return r;
}

} // namespace nanlm
