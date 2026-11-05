#include "nanlm/context2.hpp"

#include <cmath>

namespace nanlm {

Context2Model::Context2Model() = default;

void Context2Model::observe(std::uint8_t a, std::uint8_t b, std::uint8_t c,
                            std::uint32_t n) {
    if (!slabs_[a]) slabs_[a] = std::make_unique<Slab>();
    Slab& s = *slabs_[a];
    const std::uint32_t old = s.counts[b][c];
    const std::uint32_t next = (old > 0xFFFFFFFFu - n) ? 0xFFFFFFFFu : old + n;
    s.counts[b][c] = next;
    s.row_total[b] += n;
    s.total += n;
    ++bigram_[b][c];
    ++unigram_[c];
}

void Context2Model::train(const std::vector<std::uint8_t>& data) {
    slabs_ = {};
    bigram_ = {};
    unigram_ = {};
    for (std::size_t i = 2; i < data.size(); ++i) {
        observe(data[i - 2], data[i - 1], data[i]);
    }
}

std::uint32_t Context2Model::count(std::uint8_t a, std::uint8_t b, std::uint8_t c) const {
    if (!slabs_[a]) return 0;
    return slabs_[a]->counts[b][c];
}

std::uint8_t Context2Model::predict(std::uint8_t a, std::uint8_t b) const {
    if (slabs_[a]) {
        const Slab& s = *slabs_[a];
        std::uint32_t best = 0;
        std::uint8_t best_c = 0;
        for (std::uint32_t c = 0; c < 256; ++c) {
            if (s.counts[b][c] > best) {
                best = s.counts[b][c];
                best_c = static_cast<std::uint8_t>(c);
            }
        }
        if (best > 0) return best_c;
    }
    // Bigram fallback.
    std::uint32_t best = 0;
    std::uint8_t best_c = 0;
    for (std::uint32_t c = 0; c < 256; ++c) {
        if (bigram_[b][c] > best) {
            best = bigram_[b][c];
            best_c = static_cast<std::uint8_t>(c);
        }
    }
    return best_c;
}

Context2Eval Context2Model::evaluate(const std::vector<std::uint8_t>& data,
                                     std::size_t start, std::size_t end) const {
    Context2Eval r;
    if (start < 2) start = 2;
    if (end > data.size()) end = data.size();
    double bits = 0.0;
    for (std::size_t i = start; i < end; ++i) {
        const std::uint8_t a = data[i - 2];
        const std::uint8_t b = data[i - 1];
        const std::uint8_t c = data[i];
        ++r.bytes;
        if (predict(a, b) == c) ++r.correct;

        std::uint32_t row_total = 0;
        std::uint32_t c2 = 0;
        if (slabs_[a]) {
            row_total = slabs_[a]->row_total[b];
            c2 = slabs_[a]->counts[b][c];
        }
        const double p2 = (static_cast<double>(c2) + 1.0) /
                          (static_cast<double>(row_total) + 256.0);
        std::uint32_t bigram_total = 0;
        for (std::uint32_t x : bigram_[b]) bigram_total += x;
        const double p1 = (static_cast<double>(bigram_[b][c]) + 1.0) /
                          (static_cast<double>(bigram_total) + 256.0);
        const double lambda = static_cast<double>(row_total) /
                              (static_cast<double>(row_total) + 50.0);
        bits += -std::log2(lambda * p2 + (1.0 - lambda) * p1);
    }
    if (r.bytes) {
        r.accuracy = static_cast<double>(r.correct) / static_cast<double>(r.bytes);
        r.bits_per_byte = bits / static_cast<double>(r.bytes);
    }
    return r;
}

std::size_t Context2Model::slabs() const {
    std::size_t n = 0;
    for (const auto& s : slabs_) if (s) ++n;
    return n;
}

} // namespace nanlm
