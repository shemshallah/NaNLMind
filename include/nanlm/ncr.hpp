// NaN Cluster Runtime (NCR).
//
// Three levels:
//   system  = one physical machine
//   cluster = coordinated systems with a hardware profile
//   universe = one logical NaN computational space
//
// The first deployment can map 256 systems to 256 Heads one-to-one, but the
// mapping is many-to-many: one system may host several Heads, and a Head may
// have replicas. Identity and generation survive placement and failover.
#pragma once

#include "nanlm/ntf.hpp"

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace nanlm {

enum class Arch : std::uint8_t { X86 = 0, Arm = 1, RiscV = 2, Gpu = 3, Mixed = 4, Other = 5 };

struct SystemProfile {
    std::uint32_t id = 0;
    Arch arch = Arch::X86;
    std::uint32_t cores = 0;
    std::uint64_t ram_bytes = 0;
    std::uint32_t gpu_units = 0;
    std::uint64_t storage_bytes = 0;
    std::uint64_t bandwidth_bps = 0;
    bool available = true;
};

struct ClusterProfile {
    std::uint16_t universe = 0;
    Arch arch = Arch::Mixed;
    std::vector<SystemProfile> systems;
    std::uint64_t generation = 0;
    std::uint32_t capabilities = 0;
};

struct PlacementPolicy {
    bool one_to_one = true;
    std::uint32_t head_cores = 1;
    std::uint64_t head_ram_bytes = 0;
    std::uint32_t head_gpu_units = 0;
    std::uint32_t max_heads_per_system = 0; // 0 = unlimited by this policy
};

struct HeadPlacement {
    std::uint8_t head = 0;
    std::uint32_t system = 0;
    std::uint64_t generation = 0;
};

struct PlacementResult {
    bool ok = false;
    std::vector<HeadPlacement> placements;
    std::string error;
};

struct HandoffTicket {
    std::uint8_t head = 0;
    std::uint32_t from = 0;
    std::uint32_t to = 0;
    std::uint64_t from_generation = 0;
    std::uint64_t to_generation = 0;
    bool valid = false;
};

struct RecoveryEvent {
    std::uint8_t head = 0;
    std::uint32_t from = 0;
    std::uint32_t to = 0;
    std::uint64_t generation = 0;
};

struct MigrationPlan {
    bool ok = false;
    std::uint16_t universe = 0;
    std::uint64_t generation = 0;
    std::vector<std::uint8_t> heads;
    std::string error;
};

class ClusterRuntime {
public:
    void load(ClusterProfile cluster);

    const ClusterProfile& cluster() const { return cluster_; }
    PlacementResult place(const PlacementPolicy& policy = PlacementPolicy{});
    bool validate(std::string* error = nullptr) const;

    std::optional<std::uint32_t> owner(std::uint8_t head) const;
    std::uint64_t generation(std::uint8_t head) const;
    std::vector<std::uint8_t> heads_on(std::uint32_t system) const;
    std::size_t head_count_on(std::uint32_t system) const;

    HandoffTicket begin_handoff(std::uint8_t head, std::uint32_t to,
                                std::uint64_t expected_generation,
                                std::uint64_t new_generation,
                                std::string* error = nullptr);
    bool commit_handoff(const HandoffTicket& ticket, std::string* error = nullptr);
    bool abort_handoff(const HandoffTicket& ticket, std::string* error = nullptr);

    bool fail_system(std::uint32_t system, const PlacementPolicy& policy,
                     std::vector<RecoveryEvent>* events = nullptr,
                     std::string* error = nullptr);

    MigrationPlan plan_migration(const ClusterProfile& destination,
                                 const PlacementPolicy& policy) const;

private:
    SystemProfile* system(std::uint32_t id);
    const SystemProfile* system(std::uint32_t id) const;
    bool can_host(std::uint32_t system, const PlacementPolicy& policy) const;

    ClusterProfile cluster_{};
    std::array<std::vector<std::uint32_t>, 256> owners_{};
    std::array<std::uint64_t, 256> generations_{};
    std::unordered_map<std::uint8_t, HandoffTicket> pending_;
};

} // namespace nanlm
