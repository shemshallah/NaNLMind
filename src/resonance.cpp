#include "nanlm/resonance.hpp"

#include <algorithm>
#include <cstdlib>

namespace nanlm {
namespace {

// Coupling by 8-bit Hamming distance, Q16.16.
constexpr std::int32_t kHammingCoupling[9] = {
    0,      // 0: self, handled separately
    26214,  // 1: 0.40
    19661,  // 2: 0.30
    13107,  // 3: 0.20
    9175,   // 4: 0.14
    6554,   // 5: 0.10
    4588,   // 6: 0.07
    3277,   // 7: 0.05
    1966,   // 8: 0.03
};

std::int32_t clamp_energy(std::int64_t v) {
    if (v < 0) return 0;
    if (v > (1 << 20)) return 1 << 20;
    return static_cast<std::int32_t>(v);
}

} // namespace

ResonanceLattice::ResonanceLattice() { reset(0); }

void ResonanceLattice::reset(std::uint64_t seed) {
    for (int i = 0; i < 256; ++i) {
        const std::uint32_t h = mix32(static_cast<std::uint32_t>(seed) ^
                                      (static_cast<std::uint32_t>(i) * 0x9E3779B9u));
        nodes_[i].amp = 0;
        nodes_[i].energy = 0;
        nodes_[i].phase = static_cast<std::int32_t>(h & 0xFFFFu);
    }
}

std::int32_t ResonanceLattice::coupling(int i, int j) const {
    if (i == j) return 0;
    const int row_i = (i >> 4) & 15;
    const int col_i = i & 15;
    const int row_j = (j >> 4) & 15;
    const int col_j = j & 15;
    const int manhattan = std::abs(row_i - row_j) + std::abs(col_i - col_j);

    std::int32_t local = 0;
    switch (manhattan) {
        case 1: local = 52429; break; // 0.80
        case 2: local = 32768; break; // 0.50
        case 3: local = 16384; break; // 0.25
        case 4: local = 8192; break;  // 0.125
        default: local = 0; break;
    }

    const auto distance = static_cast<std::uint8_t>(hamming8(static_cast<std::uint8_t>(i),
                                                             static_cast<std::uint8_t>(j)));
    const std::int32_t remote = kHammingCoupling[std::min<unsigned>(distance, 8)];
    return std::max(local, remote);
}

void ResonanceLattice::ping(int head, std::int32_t energy, std::int32_t phase) {
    ResonanceNode& n = node(head);
    n.energy = clamp_energy(static_cast<std::int64_t>(n.energy) + energy);
    n.amp = std::max<std::int32_t>(n.amp, energy);
    n.phase = (phase == 0) ? n.phase : (phase & 0xFFFF);
}

void ResonanceLattice::step() {
    std::array<std::int32_t, 256> next{};
    for (int i = 0; i < 256; ++i) {
        std::int64_t sum_e = 0;
        std::int64_t sum_c = 0;
        for (int j = 0; j < 256; ++j) {
            if (i == j) continue;
            const std::int32_t c = coupling(i, j);
            sum_c += c;
            sum_e += (static_cast<std::int64_t>(c) * nodes_[j].energy) >> 16;
        }
        // Discrete heat diffusion: energy + alpha * (weighted neighbor mean -
        // energy). This conserves energy and propagates a wave without the
        // runaway amplification of a naive additive update.
        const std::int64_t degree_energy = (sum_c * nodes_[i].energy) >> 16;
        const std::int64_t diffusion = (sum_e - degree_energy) / 8;
        std::int64_t blended = static_cast<std::int64_t>(nodes_[i].energy) + diffusion;
        blended = (blended * 1023) / 1024; // tiny leak
        next[i] = clamp_energy(blended);
    }
    for (int i = 0; i < 256; ++i) {
        nodes_[i].energy = next[i];
        nodes_[i].amp = std::min(next[i], 1 << 20);
        // Phase advances slowly with local energy. Integer-only.
        nodes_[i].phase = (nodes_[i].phase + (next[i] >> 12)) & 0xFFFF;
    }
}

int ResonanceLattice::propagate(int from, int to, std::int32_t threshold, int max_steps) {
    reset(0);
    ping(from, 65536);
    if (from == to) return 0;
    for (int s = 1; s <= max_steps; ++s) {
        step();
        if (nodes_[to].energy >= threshold) return s;
    }
    return -1;
}

std::int32_t ResonanceLattice::coherence(int top_k) const {
    std::array<int, 256> order{};
    for (int i = 0; i < 256; ++i) order[i] = i;
    std::sort(order.begin(), order.end(), [&](int a, int b) {
        return nodes_[a].energy > nodes_[b].energy;
    });
    const int n = std::min(std::max(top_k, 2), 256);
    std::int64_t sum = 0;
    std::int64_t pairs = 0;
    for (int a = 0; a < n; ++a) {
        for (int b = a + 1; b < n; ++b) {
            int d = std::abs(nodes_[order[a]].phase - nodes_[order[b]].phase);
            d = std::min(d, 65536 - d);
            sum += (65536 - d);
            ++pairs;
        }
    }
    if (pairs == 0) return 0;
    return static_cast<std::int32_t>(sum / pairs);
}

Hash256 ResonanceLattice::digest() const {
    Sha256 h;
    h.update(nodes_.data(), nodes_.size() * sizeof(ResonanceNode));
    return h.final();
}

} // namespace nanlm
