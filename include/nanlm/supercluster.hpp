// Supercluster: a cluster of clusters.
//
// Level 0: system (one machine / phone / point)
// Level 1: cluster = up to 256 systems
// Level 2: supercluster = 256 clusters = up to 65,536 systems
//
// A supercluster hosts 256 regions; each region is a 256-head cluster. The
// logical universe is still one object; the supercluster is a placement layer.
#pragma once

#include "nanlm/ncr.hpp"

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace nanlm {

struct SuperclusterProfile {
    std::uint16_t universe = 0;
    std::vector<ClusterProfile> clusters; // ideally 256
    std::uint64_t generation = 0;
};

struct RegionPlacement {
    std::uint8_t region = 0;
    std::uint16_t cluster = 0;
    std::uint64_t generation = 0;
};

struct SuperclusterPlacement {
    bool ok = false;
    std::string error;
    std::vector<RegionPlacement> regions;
    std::size_t systems = 0;
    std::size_t heads = 0;
};

class SuperclusterRuntime {
public:
    void load(SuperclusterProfile profile);

    const SuperclusterProfile& profile() const { return profile_; }
    SuperclusterPlacement place(const PlacementPolicy& policy = PlacementPolicy{});
    bool validate(std::string* error = nullptr) const;

    std::optional<std::uint32_t> system_for(std::uint8_t region, std::uint8_t head) const;
    std::optional<std::uint16_t> cluster_for_region(std::uint8_t region) const;
    std::vector<HeadPlacement> cluster_placements(std::uint16_t cluster) const;
    std::size_t total_systems() const;
    std::size_t total_heads() const;

    bool fail_system(std::uint16_t cluster, std::uint32_t system,
                     const PlacementPolicy& policy,
                     std::vector<RecoveryEvent>* events = nullptr,
                     std::string* error = nullptr);

    // Move one region's 256 heads to a compatible cluster in a destination
    // supercluster profile. The logical universe identity is unchanged.
    MigrationPlan plan_region_migration(std::uint8_t region,
                                        const SuperclusterProfile& destination,
                                        const PlacementPolicy& policy) const;

private:
    SuperclusterProfile profile_{};
    std::vector<ClusterRuntime> runtimes_;
    std::array<std::uint16_t, 256> region_cluster_{};
    bool placed_ = false;
};

} // namespace nanlm
