// Deterministic integer resonance lattice over the 256 palindromic heads.
//
// The 256 fixed points form a 16x16 lattice via the eight free bits of the
// palindromic address. Every head is used; none is reserved. Local edges are
// strong, long-range Hamming coupling is weak. All arithmetic is integer
// Q16.16 so replay is bit-identical across compilers.
#pragma once

#include "nanlm/nan16.hpp"
#include "nanlm/sha256.hpp"

#include <array>
#include <cstdint>

namespace nanlm {

struct ResonanceNode {
    std::int32_t amp = 0;    // Q16.16 signed amplitude
    std::int32_t phase = 0;  // 0..65535
    std::int32_t energy = 0; // Q16.16 non-negative
};

class ResonanceLattice {
public:
    ResonanceLattice();

    void reset(std::uint64_t seed = 0);
    void ping(int head, std::int32_t energy, std::int32_t phase = 0);
    void step();
    int propagate(int from, int to, std::int32_t threshold = 19661, int max_steps = 500);
    std::int32_t coherence(int top_k = 16) const;

    std::int32_t coupling(int i, int j) const;
    const ResonanceNode& node(int i) const { return nodes_[static_cast<std::size_t>(i & 255)]; }
    ResonanceNode& node(int i) { return nodes_[static_cast<std::size_t>(i & 255)]; }
    std::int32_t energy(int i) const { return node(i).energy; }

    Hash256 digest() const;

private:
    std::array<ResonanceNode, 256> nodes_{};
};

} // namespace nanlm
