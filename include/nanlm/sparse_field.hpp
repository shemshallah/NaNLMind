// Native sparse head/field bank for the shared-trunk architecture.
//
// The shared trunk supplies one Q16.16 feature vector per token.  This bank
// owns the 255 low-rank head adapters, router scores, hotspot bias and usage
// counters.  Only the selected top-k adapters are evaluated; the rest remain
// cheap wave/interface state.  The state lives in Universe::sparse_field(),
// so it serializes and digests with the chart and can later be paged as one
// sparse field.
//
// Dimensions are runtime-configurable up to d=512 and rank 4.  The full
// d=512 layout is reserved in the chart extension; a smaller model never
// touches the unused tail.
#pragma once

#include "nanlm/universe.hpp"

#include <array>
#include <cstddef>
#include <cstdint>

namespace nanlm {

class SparseField {
public:
    static constexpr std::size_t kMaxDim = kSparseMaxDim;
    static constexpr std::size_t kMaxRank = kSparseMaxRank;
    static constexpr std::size_t kHeads = kSparseHeads;
    static constexpr std::size_t kActive = kSparseActive;

    using Feature = std::array<std::int32_t, kMaxDim>;
    using Mask = std::array<std::uint64_t, (kHeads + 63) / 64>;

    struct Result {
        std::array<std::uint8_t, kActive> heads{};
        std::array<std::int32_t, kActive> weights{};
        Feature output{};
        Mask mask{};
        std::size_t count = 0;
    };

    struct Hotspots {
        std::array<std::uint8_t, kHeads> heads{};
        std::array<std::uint8_t, kTriadCount> triads{};
        std::uint16_t hot_heads = 0;
        std::uint16_t hot_triads = 0;
        bool field_hot = false;
    };

    explicit SparseField(Universe& universe) : universe_(&universe) {}

    SparseFieldState& state() { return universe_->sparse_field(); }
    const SparseFieldState& state() const { return universe_->sparse_field(); }

    std::size_t dim() const { return state().dim; }
    std::size_t rank() const { return state().rank; }
    std::size_t active() const { return state().active; }

    // Set the active prefix.  dim <= 512, rank <= 4, active <= 8.  Returns
    // false without changing state when the request exceeds the reserved
    // layout or the field budget.
    bool configure(std::uint16_t dim, std::uint8_t rank,
                   std::uint8_t active = kSparseActive);

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

    // Scan the whole field for hot heads and hot triads.  A head is hot when
    // its local credit exceeds head_threshold.  A triad is hot when at least
    // two of its three members are hot or its mean credit exceeds
    // triad_threshold.  Hot triads promote all their members.  The field is
    // hot when at least 43 of 85 triads are hot (the 43/85 field threshold).
    // The triad members are read from the adaptive Universe mapping, not from
    // the fixed head/3 grouping.
    Hotspots update_hotspots(const std::array<std::int16_t, kHeads>& credits,
                             std::int16_t head_threshold,
                             std::int16_t triad_threshold);
    Hotspots update_hotspots(const std::array<std::int16_t, kHeads>& credits,
                             std::int16_t threshold);

    const std::array<std::uint8_t, kHeads>& hot_heads() const {
        return state().hot_head;
    }
    const std::array<std::uint8_t, kTriadCount>& hot_triads() const {
        return state().hot_triad;
    }
    bool field_hot() const { return state().field_hot != 0; }

private:
    static std::int32_t clamp32(std::int64_t value);
    static std::int16_t clamp16(std::int64_t value);
    static std::int32_t dot(const std::int16_t* weights,
                            const std::array<std::int32_t, kMaxDim>& x,
                            std::size_t dim, int shift = 15);
    void ensure_seeded();

    Universe* universe_;
};

} // namespace nanlm
