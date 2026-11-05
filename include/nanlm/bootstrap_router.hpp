// Point-1 bootstrap router and sparse Hopfield layer.
//
// The router is a role on a non-head portal (default point 1 = 0x0001).
// The Hopfield layer is deliberately bounded:
//   256 head vectors, top-k active heads, 32,640 pair slots.
// It is not a transformer and it does not allocate the 2 GiB bootstrap map.
#pragma once

#include "nanlm/nan16.hpp"
#include "nanlm/sha256.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace nanlm {

enum class LayerMath : std::uint8_t {
    Boolean = 0,
    Count = 1,
    Hopfield = 2,
    Temporal = 3,
    Rule = 4,
    Exact = 5,
    Retrieval = 6,
};

enum class LayerStorage : std::uint8_t {
    Chart = 0,
    VectorBin = 1,
    RuleBin = 2,
    CorpusBin = 3,
    RouteOnly = 4,
};

struct LayerRef {
    std::uint8_t layer = 0;
    std::uint8_t system_slot = 0;
    std::uint8_t head = 0;
    std::uint16_t bank = 0;
    std::uint32_t bin = 0;
    std::uint16_t slot = 0;

    bool valid() const { return bin != 0; }
    bool operator==(const LayerRef& other) const {
        return layer == other.layer && system_slot == other.system_slot &&
               head == other.head && bank == other.bank && bin == other.bin &&
               slot == other.slot;
    }
};

// A 256-entry route table for one universe. Point 1 is the default control
// portal; point 256 is accepted as the alternate mapping. Neither is a head.
class PointRouter {
public:
    static constexpr std::uint16_t kDefaultPoint = 1;
    static constexpr std::uint16_t kAlternatePoint = 256;

    explicit PointRouter(std::uint16_t point = kDefaultPoint);

    std::uint16_t point() const { return point_; }
    bool bind(std::uint8_t head, LayerRef ref);
    bool unbind(std::uint8_t head);
    std::optional<LayerRef> resolve(std::uint8_t head) const;
    std::size_t bindings() const;
    Hash256 digest() const;

private:
    std::uint16_t point_;
    std::array<LayerRef, 256> routes_{};
};

struct HopfieldConfig {
    std::uint8_t top_k = 8;
    std::int16_t max_strength = 1024;
    std::uint8_t dim = 16;
};

struct HopfieldPrediction {
    bool abstain = true;
    std::uint32_t token = 0;
    std::int64_t score = 0;
    std::vector<std::uint8_t> active;
};

class HopfieldRouter {
public:
    static constexpr std::uint8_t kDim = 16;
    using Vector = std::array<std::int16_t, kDim>;

    struct Slot {
        Vector key{};
        std::uint32_t value = 0;
        std::int16_t strength = 0;
        std::uint64_t epoch = 0;
        bool used = false;
    };

    explicit HopfieldRouter(HopfieldConfig config = {});

    void set_head(std::uint8_t head, const Vector& vector);
    const Vector& head(std::uint8_t head) const;
    const Slot& slot(std::uint32_t pair) const;
    std::size_t used_slots() const { return used_slots_; }

    HopfieldPrediction predict(const Vector& query) const;
    // Returns true when a slot was written or updated.
    bool learn(const Vector& query, std::uint32_t target);

    Hash256 digest() const;

private:
    std::int64_t dot(const Vector& a, const Vector& b) const;
    std::vector<std::uint8_t> active_heads(const Vector& query) const;
    std::vector<std::uint32_t> active_pairs(
        const std::vector<std::uint8_t>& active) const;
    std::uint32_t new_pair(const std::vector<std::uint8_t>& active) const;
    std::int16_t clamp_strength(std::int64_t value) const;

    HopfieldConfig config_;
    std::array<Vector, 256> heads_{};
    std::vector<Slot> slots_;
    std::size_t used_slots_ = 0;
    std::uint64_t epoch_ = 0;
};

} // namespace nanlm
