// Mapped hypermatrix and triadic head-field voting for NaNLMind v2.
//
// The 256x256 pair fabric is already the address-derived register. This module
// adds the third-order extension inside the same 8 MiB chart:
//
//   H[pair(a,b)] = 256 candidate bits
//
// A hyperedge (a,b,c) projects to three bits:
//   c in H[pair(a,b)], a in H[pair(b,c)], b in H[pair(c,a)].
//
// The projected bits live in Universe::hypermatrix_ and serialize/digest with
// the chart. There is no host-side model or second memory object. Exact
// hyperedge support is combined with a dense two-of-three pair contraction so
// the readout is not limited to memorized held-out triples.
//
// Heads 0..254 form 85 independent triads. Each triad records a 3-bit vote in
// its leader's head scratchpad. A patch is applied to the field only after at
// least two of the three heads vote for it. Head 255 aggregates triad votes
// into the field decision. This is integer/native state, not a NaNLM v1
// dependency or a floating-point backpropagation graph.
#pragma once

#include "nanlm/head.hpp"
#include "nanlm/hypergraph.hpp"
#include "nanlm/universe.hpp"

#include <array>
#include <cstdint>
#include <vector>

namespace nanlm {

class Hypermatrix {
public:
    static constexpr std::size_t kHeads = kHeadCount;
    static constexpr std::size_t kBitsPerRow = 256;
    static constexpr std::size_t kRowBytes = kHypermatrixRowBytes;

    explicit Hypermatrix(Universe& universe) : universe_(&universe) {}

    static std::uint32_t row_address(std::uint8_t a, std::uint8_t b) {
        return static_cast<std::uint32_t>(pair_index(a, b));
    }
    static void set_bit(Universe& universe, std::uint8_t a, std::uint8_t b,
                        std::uint8_t candidate);
    static void clear_bit(Universe& universe, std::uint8_t a, std::uint8_t b,
                          std::uint8_t candidate);
    static bool bit(const Universe& universe, std::uint8_t a, std::uint8_t b,
                    std::uint8_t candidate);

    void set(std::uint8_t a, std::uint8_t b, std::uint8_t c);
    void clear(std::uint8_t a, std::uint8_t b, std::uint8_t c);
    bool has(std::uint8_t a, std::uint8_t b, std::uint8_t c) const;

    // Number of the three projected membership bits that are set (0..3).
    std::uint32_t exact_support(std::uint8_t a, std::uint8_t b,
                                std::uint8_t c) const;
    // Two-of-three pair activity over the same register (0..3).
    std::uint32_t dense_support(std::uint8_t a, std::uint8_t b,
                                std::uint8_t c) const;
    // exact * 4 + dense; zero when no hyperedge or pair evidence is present.
    std::uint32_t score(std::uint8_t a, std::uint8_t b, std::uint8_t c) const;
    // Integer CP-rank proxy from the three palindromic head registers.
    std::uint32_t head_coupling(std::uint8_t a, std::uint8_t b,
                                std::uint8_t c) const;

    // Project a first-class Hypergraph edge into the mapped hypermatrix.
    // Only root-chart head-bit members are used; arcs/pages remain in the
    // Hypergraph itself.
    bool project(const Hyperedge& edge);
    static bool project(Universe& universe, const Hyperedge& edge);

    std::size_t nonzero() const { return universe_->hypermatrix_nonzero(); }

private:
    Universe* universe_;
    static bool pair_active(const Universe& universe, std::uint8_t a,
                            std::uint8_t b);
};

struct BooleanProbe {
    std::uint32_t a = 0;
    std::uint32_t b = 0;
    bool target = false;
};

struct HeadProposalResult {
    bool triad_accepted = false;
    bool applied = false;
    std::uint8_t triad = 0;
    std::uint8_t votes = 0;
    std::int16_t head_credit = 0;
    std::int16_t triad_credit = 0;
};

class TriadField {
public:
    static constexpr std::uint16_t kHeadCount = 256;
    static constexpr std::uint8_t kCognitiveHeads = 255;
    static constexpr std::uint8_t kTriadSize = 3;
    static constexpr std::uint8_t kTriadCount = 85;
    static constexpr std::uint8_t kFieldHead = 255;
    // Vote bytes live in each leader's 1 KiB head scratchpad.
    static constexpr std::size_t kVoteOffset = 8;   // uint32 mask
    static constexpr std::size_t kFieldOffset = 12; // uint16 accepted triads
    static constexpr std::size_t kLocalGainOffset = 16; // int32 Q16.16
    static constexpr std::size_t kGroupGainOffset = 20; // int32 Q16.16

    static std::uint8_t leader(std::uint8_t head);
    static std::uint8_t triad_index(const Universe& universe, std::uint8_t head);
    // Default fixed triads, retained for callers that have no Universe.
    static std::array<std::uint8_t, kTriadSize> members(std::uint8_t head);
    // Adaptive triad membership stored in the chart.
    static std::array<std::uint8_t, kTriadSize> members(const Universe& universe,
                                                        std::uint8_t head);
    static std::uint32_t votes(const Universe& universe, std::uint8_t head);
    static bool vote(Universe& universe, std::uint8_t head, bool approve);
    static void clear(Universe& universe, std::uint8_t head);
    static bool accepted(const Universe& universe, std::uint8_t head);

    // Recompute the field vote from the 85 triad masks and the native Q16.16
    // phase coherence of each triad. Returns the accepted-triad count.
    static std::uint16_t update_field(Universe& universe);
    static bool field_accepted(const Universe& universe);
    static std::uint16_t field_count(const Universe& universe);
    static std::int32_t field_coherence(Universe& universe);
    static std::int32_t field_support_q16(const Universe& universe);

    // Q16.16 hierarchical hypermatrix gains. Local gains live in each head,
    // group gains in the triad's third head, and the field gain in head 255.
    static std::int32_t local_gain(const Universe& universe, std::uint8_t head);
    static std::int32_t group_gain(const Universe& universe, std::uint8_t head);
    static std::int32_t field_gain(const Universe& universe);
    static void set_local_gain(Universe& universe, std::uint8_t head,
                               std::int32_t q16);
    static void set_group_gain(Universe& universe, std::uint8_t head,
                               std::int32_t q16);
    static void set_field_gain(Universe& universe, std::int32_t q16);

    // Broadcast patch: all three members receive the same patch after a 2/3
    // vote. Retained as the baseline cluster operation.
    static bool apply_patch(Universe& universe, HeadArray& heads,
                            std::uint8_t proposer, std::uint16_t patch,
                            std::uint32_t a, std::uint32_t b, bool target);

    // Per-head independent self-modification. Only the proposer's mask is
    // patched. Its triad members vote from their own Boolean predictions; the
    // proposal applies when at least two members predict the target and the
    // candidate rule is correct. Accepted/rejected proposals update bounded
    // integer credit fields (not floating-point gradients).
    static HeadProposalResult propose_head_patch(
        Universe& universe, HeadArray& heads, std::uint8_t proposer,
        std::uint16_t patch, std::uint32_t a, std::uint32_t b, bool target);

    // Score a triad on a small Boolean probe set. This is the local objective
    // used by temporary membership remaps.
    static std::int32_t triad_score(const Universe& universe, HeadArray& heads,
                                    std::uint8_t triad,
                                    const BooleanProbe* probes, std::size_t count);

    // Swap one member between triads when the combined local score improves.
    // The mapping is reversible and serialized; a failed trial rolls back.
    static bool remap_member(Universe& universe, HeadArray& heads,
                             std::uint8_t triad, std::uint8_t slot,
                             std::uint8_t replacement,
                             const BooleanProbe* probes, std::size_t count);

    static std::int16_t head_credit(const Universe& universe, std::uint8_t head);
    static std::int16_t triad_credit(const Universe& universe, std::uint8_t head);
};

} // namespace nanlm
