// Bootstrap system-slot map and layer registry.
//
// The 2 GiB bootstrap map is represented by 256 metadata slots. Slot 1 is the
// bootstrap; the other 255 are reserved peers. No 8 MiB image is allocated here.
#pragma once

#include "nanlm/bootstrap_router.hpp"
#include "nanlm/overbootstrap.hpp"

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace nanlm {

struct LayerSpec {
    std::uint8_t layer = 0;
    LayerMath math = LayerMath::Boolean;
    LayerStorage storage = LayerStorage::Chart;
    LayerRef payload{};
    bool active = false;
    std::uint64_t epoch = 0;
    std::uint32_t flags = 0;
};

class LayerRegistry {
public:
    bool set(const LayerSpec& spec);
    bool remove(std::uint8_t layer);
    std::optional<LayerSpec> get(std::uint8_t layer) const;
    std::size_t size() const;
    Hash256 digest() const;

private:
    std::array<LayerSpec, 256> layers_{};
};

// Writes trained head vectors through the runner map into the 2 GiB head
// arena. This is the first train -> map -> persist path.
struct StoredSlot {
    std::int16_t key[HopfieldRouter::kDim]{};
    std::uint32_t value = 0;
    std::int16_t strength = 0;
    std::uint16_t used = 0;
    std::uint64_t epoch = 0;
};
static_assert(sizeof(StoredSlot) == 48);

class HeadStore {
public:
    static constexpr std::uint32_t kSlotOffset = sizeof(HopfieldRouter::Vector) + 2;
    static constexpr std::uint16_t kMaxStoredSlots =
        static_cast<std::uint16_t>((kHeadRegionBytes - kSlotOffset) / sizeof(StoredSlot));

    HeadStore(OverbootstrapMap& map, const RunnerMap& runner)
        : map_(&map), runner_(&runner) {}

    bool write_head(std::uint16_t head, const HopfieldRouter::Vector& vector);
    bool read_head(std::uint16_t head, HopfieldRouter::Vector& vector) const;
    bool write_slots(std::uint16_t head, const HopfieldRouter& router);
    bool read_slots(std::uint16_t head, const OverbootstrapMap& map,
                    std::vector<StoredSlot>& slots) const;
    bool write_all(const HopfieldRouter& router);
    std::size_t mapped_heads() const { return mapped_heads_; }
    std::size_t mapped_slots() const { return mapped_slots_; }

private:
    OverbootstrapMap* map_;
    const RunnerMap* runner_;
    std::size_t mapped_heads_ = 0;
    std::size_t mapped_slots_ = 0;
};

// Allocates per-layer payload regions in the 2 GiB map. Pages 0 and 1 are
// reserved for the live 8 MiB image and the head arena, so allocation starts
// at page 2. This is runner-side; Android never constructs it.
class LayerPayloadStore {
public:
    explicit LayerPayloadStore(OverbootstrapMap& map) : map_(&map) {}

    bool allocate(std::uint8_t layer, std::uint32_t bytes);
    bool write(std::uint8_t layer, std::uint32_t offset,
               const std::uint8_t* data, std::size_t bytes);
    bool read(std::uint8_t layer, std::uint32_t offset,
              std::uint8_t* out, std::size_t bytes) const;
    std::optional<RegionRef> region(std::uint8_t layer) const;
    std::size_t allocated() const { return allocated_; }

private:
    OverbootstrapMap* map_;
    std::uint32_t next_page_ = 2;
    std::array<RegionRef, 256> regions_{};
    std::size_t allocated_ = 0;
};

struct RouteDelta {
    std::uint8_t head = 0;
    LayerRef ref{};
    std::uint64_t epoch = 0;
};

struct RouteDiff {
    std::uint16_t node = 0;
    std::uint64_t base_generation = 0;
    std::uint64_t logical_tick = 0;
    std::vector<RouteDelta> entries;
};

struct SystemSlot {
    std::uint16_t point = 0; // 1..256
    bool active = false;
    std::uint8_t flags = 0;
    std::uint64_t generation = 0;
    std::uint64_t epoch = 0;
    LayerRef route{};
};

class BootstrapMap {
public:
    static constexpr std::uint16_t kSlotCount = 256;
    static constexpr std::uint16_t kBootstrapPoint = 1;
    static constexpr std::uint16_t kAndroidPoint = 2;
    static constexpr std::uint64_t kSlotBytes = 8ull * 1024ull * 1024ull;
    static constexpr std::uint64_t kTotalBytes = 256ull * kSlotBytes; // 2 GiB

    BootstrapMap();

    bool activate(std::uint16_t point, std::uint8_t flags = 0);
    bool deactivate(std::uint16_t point);
    bool is_active(std::uint16_t point) const;
    bool set_route(std::uint16_t point, LayerRef route);
    bool bump_generation(std::uint16_t point, std::uint64_t epoch = 0);
    const SystemSlot* slot(std::uint16_t point) const;
    std::size_t active_slots() const;
    std::uint64_t allocated_bytes() const { return kSlotBytes; }
    Hash256 digest() const;

private:
    static std::size_t index_of(std::uint16_t point);
    std::array<SystemSlot, kSlotCount> slots_{};
};

class RouteMerger {
public:
    static bool apply(BootstrapMap& map, PointRouter& router,
                      const RouteDiff& diff, std::string* error = nullptr);
};

} // namespace nanlm
