// Bootstrap system-slot map and layer registry.
//
// The 2 GiB bootstrap map is represented by 256 metadata slots. Slot 1 is the
// bootstrap; the other 255 are reserved peers. No 8 MiB image is allocated here.
#pragma once

#include "nanlm/bootstrap_router.hpp"

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
    const SystemSlot* slot(std::uint16_t point) const;
    std::size_t active_slots() const;
    std::uint64_t allocated_bytes() const { return kSlotBytes; }
    Hash256 digest() const;

private:
    static std::size_t index_of(std::uint16_t point);
    std::array<SystemSlot, kSlotCount> slots_{};
};

} // namespace nanlm
