#include "nanlm/sparse_field.hpp"

#include <algorithm>
#include <limits>

namespace nanlm {

std::int32_t SparseField::clamp32(std::int64_t value) {
    if (value > std::numeric_limits<std::int32_t>::max()) {
        return std::numeric_limits<std::int32_t>::max();
    }
    if (value < std::numeric_limits<std::int32_t>::min()) {
        return std::numeric_limits<std::int32_t>::min();
    }
    return static_cast<std::int32_t>(value);
}

std::int16_t SparseField::clamp16(std::int64_t value) {
    if (value > 32767) return 32767;
    if (value < -32768) return -32768;
    return static_cast<std::int16_t>(value);
}

std::int32_t SparseField::dot(const std::int16_t* weights, const Feature& x,
                              int shift) {
    std::int64_t sum = 0;
    for (std::size_t d = 0; d < kDim; ++d) {
        sum += static_cast<std::int64_t>(weights[d]) * x[d];
    }
    return clamp32(sum >> shift);
}

void SparseField::reset() {
    state() = {};
}

void SparseField::seed(std::uint64_t seed_value) {
    auto& s = state();
    s = {};
    std::uint64_t x = seed_value ? seed_value : 0x9E3779B97F4A7C15ull;
    auto next = [&]() {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        return x;
    };
    // Small Q1.15 weights: the trunk learns the large representation; these
    // adapters start near identity so the shared trunk is not disrupted.
    for (std::size_t h = 0; h < kHeads; ++h) {
        for (std::size_t d = 0; d < kDim; ++d) {
            for (std::size_t r = 0; r < kRank; ++r) {
                s.down[h][d][r] = static_cast<std::int16_t>(
                    static_cast<std::int32_t>(next() % 129) - 64);
                s.up[h][r][d] = static_cast<std::int16_t>(
                    static_cast<std::int32_t>(next() % 129) - 64);
            }
            s.router[h][d] = static_cast<std::int16_t>(
                static_cast<std::int32_t>(next() % 513) - 256);
        }
    }
    s.flags = 1;
    s.generation = 1;
}

void SparseField::ensure_seeded() {
    if (!seeded()) seed(universe_->genome() ^ 0x5350415253454649ull);
}

std::int32_t SparseField::score(std::uint8_t head, const Feature& x) const {
    if (head >= kHeads) return std::numeric_limits<std::int32_t>::min();
    const auto& s = state();
    std::int64_t value = dot(s.router[head], x);
    // Hotspot is Q8.8; lift it to Q16.16 before adding.
    value += static_cast<std::int64_t>(s.hotspot[head]) << 8;
    return clamp32(value);
}

bool SparseField::forward(const Feature& x, Result& out) {
    ensure_seeded();
    auto& s = state();
    out = {};

    std::array<std::int32_t, kHeads> scores{};
    std::array<bool, kHeads> used{};
    for (std::size_t h = 0; h < kHeads; ++h) {
        scores[h] = score(static_cast<std::uint8_t>(h), x);
    }

    std::size_t count = std::min(kActive, kHeads);
    for (std::size_t slot = 0; slot < count; ++slot) {
        std::int32_t best_score = std::numeric_limits<std::int32_t>::min();
        std::size_t best = kHeads;
        for (std::size_t h = 0; h < kHeads; ++h) {
            if (!used[h] && scores[h] > best_score) {
                best_score = scores[h];
                best = h;
            }
        }
        if (best == kHeads) break;
        used[best] = true;
        out.heads[slot] = static_cast<std::uint8_t>(best);
        out.weights[slot] = scores[best];
        out.mask[best / 64] |= (std::uint64_t{1} << (best % 64));
        ++out.count;
    }
    if (out.count == 0) return false;

    // Integer softmax substitute: non-negative top-k scores, normalized Q16.
    std::int32_t min_score = std::numeric_limits<std::int32_t>::max();
    for (std::size_t slot = 0; slot < out.count; ++slot) {
        min_score = std::min(min_score, out.weights[slot]);
    }
    std::int64_t total = 0;
    std::array<std::int64_t, kActive> raw{};
    for (std::size_t slot = 0; slot < out.count; ++slot) {
        raw[slot] = static_cast<std::int64_t>(out.weights[slot]) -
                    min_score + 1;
        total += raw[slot];
    }
    for (std::size_t slot = 0; slot < out.count; ++slot) {
        out.weights[slot] = static_cast<std::int32_t>(
            (raw[slot] << 16) / total);
    }

    out.output = x;
    std::int64_t delta[kDim]{};
    for (std::size_t slot = 0; slot < out.count; ++slot) {
        const std::size_t h = out.heads[slot];
        std::array<std::int32_t, kRank> z{};
        for (std::size_t r = 0; r < kRank; ++r) {
            std::int64_t sum = 0;
            for (std::size_t d = 0; d < kDim; ++d) {
                sum += static_cast<std::int64_t>(s.down[h][d][r]) * x[d];
            }
            z[r] = clamp32(sum >> 15);
        }
        for (std::size_t d = 0; d < kDim; ++d) {
            std::int64_t y = 0;
            for (std::size_t r = 0; r < kRank; ++r) {
                y += static_cast<std::int64_t>(s.up[h][r][d]) * z[r];
            }
            y >>= 15;
            delta[d] += (static_cast<std::int64_t>(out.weights[slot]) * y) >> 16;
        }
        ++s.usage[h];
    }
    for (std::size_t d = 0; d < kDim; ++d) {
        out.output[d] = clamp32(static_cast<std::int64_t>(x[d]) + delta[d]);
    }
    return true;
}

bool SparseField::update(std::uint8_t head, const Feature& x,
                         std::int16_t credit) {
    ensure_seeded();
    if (head >= kHeads) return false;
    auto& s = state();
    for (std::size_t d = 0; d < kDim; ++d) {
        const std::int64_t step =
            (static_cast<std::int64_t>(x[d]) * credit) >> 20;
        s.router[head][d] = clamp16(
            static_cast<std::int64_t>(s.router[head][d]) + step);
        for (std::size_t r = 0; r < kRank; ++r) {
            const std::int64_t adapter_step =
                (static_cast<std::int64_t>(x[d]) * credit) >> 21;
            s.down[head][d][r] = clamp16(
                static_cast<std::int64_t>(s.down[head][d][r]) + adapter_step);
            s.up[head][r][d] = clamp16(
                static_cast<std::int64_t>(s.up[head][r][d]) + adapter_step);
        }
    }
    s.hotspot[head] = clamp16(static_cast<std::int64_t>(s.hotspot[head]) +
                              (credit >> 1));
    auto& credit_field = universe_->head_credit()[head];
    credit_field = clamp16(static_cast<std::int64_t>(credit_field) +
                           (credit >> 2));
    ++s.generation;
    return true;
}

void SparseField::update_hotspots(
    const std::array<std::int16_t, kHeads>& credits,
    std::int16_t threshold) {
    ensure_seeded();
    auto& s = state();
    for (std::size_t h = 0; h < kHeads; ++h) {
        s.hotspot[h] = clamp16((static_cast<std::int64_t>(s.hotspot[h]) * 7) / 8);
    }
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        const std::int64_t sum =
            static_cast<std::int64_t>(credits[t * 3]) + credits[t * 3 + 1] +
            credits[t * 3 + 2];
        const std::int64_t mean = sum / 3;
        if (mean <= threshold) continue;
        for (std::size_t slot = 0; slot < 3; ++slot) {
            const std::size_t h = t * 3 + slot;
            s.hotspot[h] = clamp16(
                static_cast<std::int64_t>(s.hotspot[h]) + mean);
        }
    }
    ++s.generation;
}

} // namespace nanlm
