#include "nanlm/byte_model.hpp"

#include <algorithm>
#include <cmath>

namespace nanlm {

void ByteModel::clear() {
    for (std::uint32_t a = 0; a < 256; ++a) {
        for (std::uint32_t b = 0; b < 256; ++b) {
            auto& c = universe_->pair_cell(static_cast<std::uint8_t>(a),
                                           static_cast<std::uint8_t>(b));
            c.s_plus() = NanWord::make(NanType::QuietPositive, NanType::QuietPositive, 0);
            c.s_minus() = NanWord::make(NanType::QuietNegative, NanType::QuietNegative, 0);
        }
    }
    universe_->refresh_checksums();
}

void ByteModel::observe(std::uint8_t a, std::uint8_t b, std::uint32_t n) {
    auto& c = universe_->pair_cell(a, b);
    auto* rail = (a < b) ? &c.s_plus() : (a > b ? &c.s_minus() : &c.s_plus());
    const std::uint32_t old = rail->payload();
    const std::uint32_t next = (old > 0xFFFFFFFFu - n) ? 0xFFFFFFFFu : old + n;
    const NanType t = (a > b) ? NanType::QuietNegative : NanType::QuietPositive;
    *rail = NanWord::make(t, t, next);
    c.generation = static_cast<std::uint16_t>(c.generation + 1u);
}

std::uint32_t ByteModel::count(std::uint8_t a, std::uint8_t b) const {
    const auto& c = const_cast<Universe*>(universe_)->pair_cell(a, b);
    if (a < b) return c.s_plus().payload();
    if (a > b) return c.s_minus().payload();
    return c.s_plus().payload();
}

std::uint32_t ByteModel::total(std::uint8_t a) const {
    std::uint64_t sum = 0;
    for (std::uint32_t b = 0; b < 256; ++b) sum += count(a, static_cast<std::uint8_t>(b));
    return sum > 0xFFFFFFFFull ? 0xFFFFFFFFu : static_cast<std::uint32_t>(sum);
}

std::uint8_t ByteModel::predict(std::uint8_t a) const {
    std::uint32_t best_b = 0;
    std::uint32_t best = 0;
    for (std::uint32_t b = 0; b < 256; ++b) {
        const std::uint32_t c = count(a, static_cast<std::uint8_t>(b));
        if (c > best) {
            best = c;
            best_b = b;
        }
    }
    return static_cast<std::uint8_t>(best_b);
}

void ByteModel::train(const std::vector<std::uint8_t>& data) {
    clear();
    for (std::size_t i = 1; i < data.size(); ++i) observe(data[i - 1], data[i]);
    universe_->refresh_checksums();
}

ByteEval ByteModel::evaluate(const std::vector<std::uint8_t>& data, std::size_t start,
                             std::size_t end) const {
    ByteEval r;
    if (start < 1) start = 1;
    if (end > data.size()) end = data.size();
    double bits = 0.0;
    for (std::size_t i = start; i < end; ++i) {
        const std::uint8_t a = data[i - 1];
        const std::uint8_t b = data[i];
        ++r.bytes;
        if (predict(a) == b) ++r.correct;
        const std::uint32_t total_count = total(a);
        const double p = (static_cast<double>(count(a, b)) + 1.0) /
                         (static_cast<double>(total_count) + 256.0);
        bits += -std::log2(p);
    }
    if (r.bytes) {
        r.accuracy = static_cast<double>(r.correct) / static_cast<double>(r.bytes);
        r.bits_per_byte = bits / static_cast<double>(r.bytes);
    }
    return r;
}

ByteEval ByteModel::reference(const std::vector<std::uint8_t>& train,
                              const std::vector<std::uint8_t>& test) {
    std::vector<std::uint32_t> counts(256 * 256, 0);
    for (std::size_t i = 1; i < train.size(); ++i) {
        ++counts[static_cast<std::size_t>(train[i - 1]) * 256 + train[i]];
    }
    ByteEval r;
    double bits = 0.0;
    for (std::size_t i = 1; i < test.size(); ++i) {
        const std::uint8_t a = test[i - 1];
        const std::uint8_t b = test[i];
        std::uint32_t total = 0;
        std::uint32_t best = 0;
        std::uint8_t best_b = 0;
        for (std::uint32_t x = 0; x < 256; ++x) {
            const std::uint32_t c = counts[static_cast<std::size_t>(a) * 256 + x];
            total += c;
            if (c > best) {
                best = c;
                best_b = static_cast<std::uint8_t>(x);
            }
        }
        ++r.bytes;
        if (best_b == b) ++r.correct;
        const double p = (static_cast<double>(counts[static_cast<std::size_t>(a) * 256 + b]) +
                          1.0) / (static_cast<double>(total) + 256.0);
        bits += -std::log2(p);
    }
    if (r.bytes) {
        r.accuracy = static_cast<double>(r.correct) / static_cast<double>(r.bytes);
        r.bits_per_byte = bits / static_cast<double>(r.bytes);
    }
    return r;
}

ByteEval ByteModel::order0_reference(const std::vector<std::uint8_t>& train,
                                     const std::vector<std::uint8_t>& test) {
    std::vector<std::uint32_t> counts(256, 0);
    for (std::uint8_t b : train) ++counts[b];
    std::uint32_t best = 0;
    std::uint8_t best_b = 0;
    for (std::uint32_t b = 0; b < 256; ++b) {
        if (counts[b] > best) {
            best = counts[b];
            best_b = static_cast<std::uint8_t>(b);
        }
    }
    ByteEval r;
    double bits = 0.0;
    for (std::uint8_t b : test) {
        ++r.bytes;
        if (b == best_b) ++r.correct;
        const double p = (static_cast<double>(counts[b]) + 1.0) /
                         (static_cast<double>(train.size()) + 256.0);
        bits += -std::log2(p);
    }
    if (r.bytes) {
        r.accuracy = static_cast<double>(r.correct) / static_cast<double>(r.bytes);
        r.bits_per_byte = bits / static_cast<double>(r.bytes);
    }
    return r;
}

} // namespace nanlm
