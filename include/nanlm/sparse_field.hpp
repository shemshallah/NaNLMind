// Native sparse head/field bank for the shared-trunk architecture.
//
// The shared trunk supplies one Q16.16 feature vector per token.  This bank
// owns the 255 low-rank head adapters, router scores, hotspot bias and usage
// counters.  Only the selected top-k adapters are evaluated; the rest remain
// cheap wave/interface state.  The state lives in Universe::sparse_field(),
// so it serializes and digests with the chart and can later be paged as one
// sparse field.
#pragma once

#include "nanlm/universe.hpp"

#include <array>
#include <cstddef>
#include <cstdint>

namespace nanlm {

class SparseField {
public:
    static constexpr std::size_t kDim = kSparseDim;
    static constexpr std::size_t kHeads = kSparseHeads;
    static constexpr std::size_t kActive = kSparseActive;
    static constexpr std::size_t kRank = kSparseRank;

    using Feature = std::array<std::int32_t, kDim>;
    using Mask = std::array<std::uint64_t, (kHeads + 63) / 64>;

    struct Result {
        std::array<std::uint8_t, kActive> heads{};
        std::array<std::int32_t, kActive> weights{};
        Feature output{};
        Mask mask{};
        std::size_t count = 0;
    };

    explicit SparseField(Universe& universe) : universe_(&universe) {}

    SparseFieldState& state() { return universe_->sparse_field(); }
    const SparseFieldState& state() const { return universe_->sparse_field(); }

    void reset();
    // Deterministic small initialization from the chart genome/seed.
    void seed(std::uint64_t seed);
    bool seeded() const { return (state().flags & 1u) != 0; }

    std::int32_t score(std::uint8_t head, const Feature& x) const;
    // Evaluate only the top-k adapters.  Updates usage counters and returns
    // the selected mask; inactive adapters are never indexed.
    bool forward(const Feature& x, Result& out);
    // Local, non-BPTT credit update for one active adapter.  This is the
    // native update boundary; accepted proposals still go through the triad
    // (2/3) and field (43/85) votes.
    bool update(std::uint8_t head, const Feature& x, std::int16_t credit);
    // Decay and promote triad hotspots from per-head local credits.
    void update_hotspots(const std::array<std::int16_t, kHeads>& credits,
                         std::int16_t threshold);

private:
    static std::int32_t clamp32(std::int64_t value);
    static std::int16_t clamp16(std::int64_t value);
    static std::int32_t dot(const std::int16_t* weights, const Feature& x,
                            int shift = 15);
    void ensure_seeded();

    Universe* universe_;
};

} // namespace nanlm
