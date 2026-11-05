#include "nanlm/supercluster.hpp"

namespace nanlm {

void SuperclusterRuntime::load(SuperclusterProfile profile) {
    profile_ = std::move(profile);
    runtimes_.clear();
    runtimes_.reserve(profile_.clusters.size());
    for (const ClusterProfile& c : profile_.clusters) {
        ClusterRuntime r;
        r.load(c);
        runtimes_.push_back(std::move(r));
    }
    region_cluster_.fill(0);
    placed_ = false;
}

SuperclusterPlacement SuperclusterRuntime::place(const PlacementPolicy& policy) {
    SuperclusterPlacement result;
    if (profile_.clusters.size() < 256) {
        result.error = "supercluster needs 256 clusters";
        return result;
    }
    result.systems = 0;
    result.heads = 0;
    for (std::uint32_t r = 0; r < 256; ++r) {
        ClusterRuntime& cluster = runtimes_[r];
        const auto placed = cluster.place(policy);
        if (!placed.ok) {
            result.error = "region " + std::to_string(r) + ": " + placed.error;
            return result;
        }
        region_cluster_[r] = static_cast<std::uint16_t>(r);
        result.regions.push_back(
            RegionPlacement{static_cast<std::uint8_t>(r), static_cast<std::uint16_t>(r),
                            profile_.generation});
        result.systems += cluster.cluster().systems.size();
        result.heads += placed.placements.size();
    }
    placed_ = true;
    result.ok = true;
    return result;
}

bool SuperclusterRuntime::validate(std::string* error) const {
    if (!placed_) {
        if (error) *error = "supercluster not placed";
        return false;
    }
    for (std::uint32_t r = 0; r < 256; ++r) {
        const ClusterRuntime& cluster = runtimes_[region_cluster_[r]];
        std::string cluster_error;
        if (!cluster.validate(&cluster_error)) {
            if (error) *error = "region " + std::to_string(r) + ": " + cluster_error;
            return false;
        }
    }
    if (error) error->clear();
    return true;
}

std::optional<std::uint32_t> SuperclusterRuntime::system_for(std::uint8_t region,
                                                             std::uint8_t head) const {
    if (!placed_) return std::nullopt;
    const std::uint16_t cluster = region_cluster_[region];
    return runtimes_[cluster].owner(head);
}

std::optional<std::uint16_t> SuperclusterRuntime::cluster_for_region(
    std::uint8_t region) const {
    if (!placed_) return std::nullopt;
    return region_cluster_[region];
}

std::vector<HeadPlacement> SuperclusterRuntime::cluster_placements(
    std::uint16_t cluster) const {
    std::vector<HeadPlacement> out;
    if (cluster >= runtimes_.size()) return out;
    for (std::uint32_t h = 0; h < 256; ++h) {
        const auto owner = runtimes_[cluster].owner(static_cast<std::uint8_t>(h));
        if (owner) {
            out.push_back(HeadPlacement{static_cast<std::uint8_t>(h), *owner,
                                        runtimes_[cluster].generation(
                                            static_cast<std::uint8_t>(h))});
        }
    }
    return out;
}

std::size_t SuperclusterRuntime::total_systems() const {
    std::size_t n = 0;
    for (const auto& c : profile_.clusters) n += c.systems.size();
    return n;
}

std::size_t SuperclusterRuntime::total_heads() const {
    return profile_.clusters.size() * 256u;
}

bool SuperclusterRuntime::fail_system(std::uint16_t cluster, std::uint32_t system,
                                      const PlacementPolicy& policy,
                                      std::vector<RecoveryEvent>* events,
                                      std::string* error) {
    if (cluster >= runtimes_.size()) {
        if (error) *error = "cluster out of range";
        return false;
    }
    return runtimes_[cluster].fail_system(system, policy, events, error);
}

MigrationPlan SuperclusterRuntime::plan_region_migration(
    std::uint8_t region, const SuperclusterProfile& destination,
    const PlacementPolicy& policy) const {
    MigrationPlan plan;
    plan.universe = profile_.universe;
    plan.generation = profile_.generation;
    if (destination.clusters.size() < 256) {
        plan.error = "destination supercluster needs 256 clusters";
        return plan;
    }
    const ClusterProfile& dest_cluster = destination.clusters[region];
    ClusterRuntime tmp;
    tmp.load(dest_cluster);
    const auto placed = tmp.place(policy);
    if (!placed.ok) {
        plan.error = placed.error;
        return plan;
    }
    plan.ok = true;
    for (std::uint32_t h = 0; h < 256; ++h) plan.heads.push_back(static_cast<std::uint8_t>(h));
    return plan;
}

} // namespace nanlm
