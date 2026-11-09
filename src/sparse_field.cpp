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

std::int32_t SparseField::dot(const std::int16_t* weights,
                              const std::array<std::int32_t, kMaxDim>& x,
                              std::size_t dim, int shift) {
    std::int64_t sum = 0;
    for (std::size_t d = 0; d < dim; ++d) {
        sum += static_cast<std::int64_t>(weights[d]) * x[d];
    }
    return clamp32(sum >> shift);
}

bool SparseField::configure(std::uint16_t dim_value, std::uint8_t rank_value,
                            std::uint8_t active_value) {
    if (dim_value == 0 || dim_value > kMaxDim || rank_value == 0 ||
        rank_value > kMaxRank || active_value == 0 || active_value > kActive) {
        return false;
    }
    auto& s = state();
    s = {};
    s.dim = dim_value;
    s.rank = rank_value;
    s.active = active_value;
    s.flags = 0;
    s.generation = 1;
    return true;
}

void SparseField::reset() {
    state() = {};
}

void SparseField::seed(std::uint64_t seed_value) {
    auto& s = state();
    const std::size_t d = s.dim;
    const std::size_t r = s.rank;
    if (d == 0 || d > kMaxDim || r == 0 || r > kMaxRank) {
        configure(kSparseDefaultDim, kSparseDefaultRank, kSparseActive);
        return seed(seed_value);
    }
    std::fill(std::begin(s.hotspot), std::end(s.hotspot), 0);
    std::fill(std::begin(s.usage), std::end(s.usage), 0);
    std::fill(std::begin(s.hot_head), std::end(s.hot_head), 0);
    std::fill(std::begin(s.hot_triad), std::end(s.hot_triad), 0);
    std::fill(std::begin(s.triad_score), std::end(s.triad_score), 0);
    s.hot_triad_count = 0;
    s.field_hot = 0;
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
        for (std::size_t j = 0; j < d; ++j) {
            for (std::size_t k = 0; k < r; ++k) {
                s.down[h][j][k] = static_cast<std::int16_t>(
                    static_cast<std::int32_t>(next() % 129) - 64);
                s.up[h][k][j] = static_cast<std::int16_t>(
                    static_cast<std::int32_t>(next() % 129) - 64);
            }
            s.router[h][j] = static_cast<std::int16_t>(
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
    std::int64_t value = dot(s.router[head], x, s.dim);
    // Hotspot is Q8.8; lift it to Q16.16 before adding.
    value += static_cast<std::int64_t>(s.hotspot[head]) << 8;
    return clamp32(value);
}

bool SparseField::forward(const Feature& x, Result& out) {
    ensure_seeded();
    auto& s = state();
    const std::size_t d = s.dim;
    const std::size_t r = s.rank;
    const std::size_t k = std::min<std::size_t>(s.active, kActive);
    out = {};

    std::array<std::int32_t, kHeads> scores{};
    std::array<bool, kHeads> used{};
    for (std::size_t h = 0; h < kHeads; ++h) {
        scores[h] = score(static_cast<std::uint8_t>(h), x);
    }

    for (std::size_t slot = 0; slot < k; ++slot) {
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
    std::int64_t delta[kMaxDim]{};
    for (std::size_t slot = 0; slot < out.count; ++slot) {
        const std::size_t h = out.heads[slot];
        std::array<std::int32_t, kMaxRank> z{};
        for (std::size_t j = 0; j < r; ++j) {
            std::int64_t sum = 0;
            for (std::size_t i = 0; i < d; ++i) {
                sum += static_cast<std::int64_t>(s.down[h][i][j]) * x[i];
            }
            z[j] = clamp32(sum >> 15);
        }
        for (std::size_t i = 0; i < d; ++i) {
            std::int64_t y = 0;
            for (std::size_t j = 0; j < r; ++j) {
                y += static_cast<std::int64_t>(s.up[h][j][i]) * z[j];
            }
            y >>= 15;
            delta[i] += (static_cast<std::int64_t>(out.weights[slot]) * y) >> 16;
        }
        ++s.usage[h];
    }
    for (std::size_t i = 0; i < d; ++i) {
        out.output[i] = clamp32(static_cast<std::int64_t>(x[i]) + delta[i]);
    }
    return true;
}

bool SparseField::update(std::uint8_t head, const Feature& x,
                         std::int16_t credit) {
    ensure_seeded();
    if (head >= kHeads) return false;
    auto& s = state();
    const std::size_t d = s.dim;
    const std::size_t r = s.rank;
    for (std::size_t i = 0; i < d; ++i) {
        const std::int64_t step =
            (static_cast<std::int64_t>(x[i]) * credit) >> 20;
        s.router[head][i] = clamp16(
            static_cast<std::int64_t>(s.router[head][i]) + step);
        for (std::size_t j = 0; j < r; ++j) {
            const std::int64_t adapter_step =
                (static_cast<std::int64_t>(x[i]) * credit) >> 21;
            s.down[head][i][j] = clamp16(
                static_cast<std::int64_t>(s.down[head][i][j]) + adapter_step);
            s.up[head][j][i] = clamp16(
                static_cast<std::int64_t>(s.up[head][j][i]) + adapter_step);
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

SparseField::Hotspots SparseField::update_hotspots(
    const std::array<std::int16_t, kHeads>& credits,
    std::int16_t head_threshold, std::int16_t triad_threshold) {
    ensure_seeded();
    auto& s = state();
    Hotspots out;

    for (std::size_t h = 0; h < kHeads; ++h) {
        s.hotspot[h] = clamp16((static_cast<std::int64_t>(s.hotspot[h]) * 7) / 8);
        s.hot_head[h] = 0;
    }
    std::fill(std::begin(s.hot_triad), std::end(s.hot_triad), 0);
    std::fill(std::begin(s.triad_score), std::end(s.triad_score), 0);
    s.hot_triad_count = 0;
    s.field_hot = 0;

    // Direct hot heads are found across all 255 interfaces.
    for (std::size_t h = 0; h < kHeads; ++h) {
        if (credits[h] > head_threshold) {
            s.hot_head[h] = 1;
            ++out.hot_heads;
        }
    }

    // Scan every triad using the adaptive mapping, not a fixed h/3 grouping.
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        const std::size_t a = universe_->triad_members()[t * kTriadSize + 0];
        const std::size_t b = universe_->triad_members()[t * kTriadSize + 1];
        const std::size_t c = universe_->triad_members()[t * kTriadSize + 2];
        const std::int64_t sum = static_cast<std::int64_t>(credits[a]) +
                                 credits[b] + credits[c];
        const std::int64_t mean = sum / 3;
        const int member_hot = (credits[a] > head_threshold ? 1 : 0) +
                               (credits[b] > head_threshold ? 1 : 0) +
                               (credits[c] > head_threshold ? 1 : 0);
        s.triad_score[t] = clamp32(mean);
        if (member_hot >= 2 || mean > triad_threshold) {
            s.hot_triad[t] = 1;
            ++s.hot_triad_count;
            // A hot triangle promotes all three members, even if only two
            // were individually above the head threshold.
            for (std::size_t slot = 0; slot < kTriadSize; ++slot) {
                const std::size_t h =
                    universe_->triad_members()[t * kTriadSize + slot];
                if (!s.hot_head[h]) {
                    s.hot_head[h] = 1;
                    ++out.hot_heads;
                }
            }
        }
    }

    // Hot heads keep a decaying routing bias; hot triangles add their mean.
    for (std::size_t t = 0; t < kTriadCount; ++t) {
        if (!s.hot_triad[t]) continue;
        for (std::size_t slot = 0; slot < kTriadSize; ++slot) {
            const std::size_t h =
                universe_->triad_members()[t * kTriadSize + slot];
            s.hotspot[h] = clamp16(
                static_cast<std::int64_t>(s.hotspot[h]) + s.triad_score[t]);
        }
    }
    for (std::size_t h = 0; h < kHeads; ++h) {
        if (s.hot_head[h] && !s.hot_triad[universe_->triad_of()[h]]) {
            s.hotspot[h] = clamp16(
                static_cast<std::int64_t>(s.hotspot[h]) + credits[h]);
        }
    }

    s.field_hot = s.hot_triad_count >= 43 ? 1 : 0;
    out.hot_triads = s.hot_triad_count;
    out.field_hot = s.field_hot != 0;
    std::copy(std::begin(s.hot_head), std::end(s.hot_head),
              out.heads.begin());
    std::copy(std::begin(s.hot_triad), std::end(s.hot_triad),
              out.triads.begin());
    ++s.generation;
    return out;
}

SparseField::Hotspots SparseField::update_hotspots(
    const std::array<std::int16_t, kHeads>& credits,
    std::int16_t threshold) {
    return update_hotspots(credits, threshold, threshold);
}

} // namespace nanlm
